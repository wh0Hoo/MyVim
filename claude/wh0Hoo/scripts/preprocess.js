#!/usr/bin/env node
/**
 * Transcript preprocessor — v6 compact format.
 * Reads a CC JSONL transcript and emits a compact text transcript used by the
 * /continue skill for cheap session-restore (no LLM summarization).
 *
 * Usage: node preprocess.js <transcript.jsonl>
 *
 * Self-managing cache: derives cache path from JSONL path, checks format
 * version + mtime, skips if fresh, writes to cache file if stale.
 * Callers just run this and then Read the cached compact.txt directly.
 *
 * Input:
 *   ~/.claude/projects/{PROJECT_HASH}/{SESSION_ID}.jsonl   (CC transcript file)
 *
 * Output (cache file, not stdout):
 *   ~/.claude/wh0Hoo/{projectHash}/{sessionId}/compact.txt
 */

const fs = require("fs");
const path = require("path");
const readline = require("readline");
const os = require("os");

const COMPACT_FORMAT_VERSION = 6;

// Truncation constants
const USER_MAX = 500;
const USER_HEAD = 300;
const USER_TAIL = 200;
const AI_MAX = 200;
const AI_HEAD = 100;
const AI_TAIL = 100;
const MAX_IMAGES_PER_MSG = 3;
const WORD_SNAP_WINDOW = 5;

const STRIP_PATTERNS = [
  /─{3,}[\s\S]*?bkit Feature Usage[\s\S]*?─{3,}/g,
  /✅ Used:.*$/gm,
  /⏭️? Not Used:.*$/gm,
  /💡 Recommended:.*$/gm,
  /★\s*Insight\s*─+[\s\S]*?─{3,}/g,
  /<local-command-caveat>[\s\S]*?<\/local-command-caveat>/g,
  /<command-name>[\s\S]*?<\/command-name>/g,
  /<command-message>[\s\S]*?<\/command-message>/g,
  /<command-args>[\s\S]*?<\/command-args>/g,
  /<local-command-stdout>[\s\S]*?<\/local-command-stdout>/g,
  /<system-reminder>[\s\S]*?<\/system-reminder>/g,
  /<task-notification>[\s\S]*?<\/task-notification>/g,
];

const SKIP_USER_PATTERNS = [/^\s*$/, /^<local-command/, /^Base directory for this skill:/];

function cleanText(text) {
  let cleaned = text || "";
  for (const pat of STRIP_PATTERNS) {
    cleaned = cleaned.replace(pat, "");
  }
  cleaned = cleaned.replace(/\n{3,}/g, "\n\n");
  return cleaned.trim();
}

function shouldSkipUser(text) {
  return SKIP_USER_PATTERNS.some((pat) => pat.test(text.trim()));
}

function extractAssistantText(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((b) => b && b.type === "text" && b.text)
    .map((b) => b.text)
    .join("\n");
}

function extractUserTextWithImages(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  let imageCount = 0;
  const texts = [];
  for (const b of content) {
    if (!b) continue;
    if (b.type === "image") {
      imageCount += 1;
    } else if (b.type === "text" && b.text) {
      texts.push(b.text);
    }
  }
  const body = texts.join("\n").trim();
  let prefix = "";
  if (imageCount > 0) {
    if (imageCount <= MAX_IMAGES_PER_MSG) {
      prefix = Array(imageCount).fill("[Image]").join(" ");
    } else {
      prefix = "[Image×" + imageCount + "]";
    }
  }
  if (prefix && body) return prefix + " " + body;
  if (prefix) return prefix;
  return body;
}

function snapToWordBoundary(s, idx, direction) {
  if (idx <= 0 || idx >= s.length) return idx;
  const lo = Math.max(0, idx - WORD_SNAP_WINDOW);
  const hi = Math.min(s.length, idx + WORD_SNAP_WINDOW);
  if (direction === "end") {
    for (let i = idx; i >= lo; i--) {
      if (/\s/.test(s[i])) return i;
    }
    for (let i = idx + 1; i <= hi; i++) {
      if (/\s/.test(s[i])) return i;
    }
  } else {
    for (let i = idx; i <= hi; i++) {
      if (/\s/.test(s[i])) return i;
    }
    for (let i = idx - 1; i >= lo; i--) {
      if (/\s/.test(s[i])) return i;
    }
  }
  return idx;
}

function abstractUserContent(text) {
  let result = text;
  result = result.replace(/```[\s\S]*?```/g, "[Code]");
  result = result.replace(
    /(?:^\|[^\n]+\|\n\|\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)+\|\n(?:\|[^\n]+\|\n?)*)/gm,
    "[Table]"
  );
  result = result.replace(
    /(?:^[\s]{0,4}(?:[-*+]|\d+[.)])\s+[^\n]{1,500}(?:\n|$)){3,}/gm,
    "[List]"
  );
  return result;
}

function truncateUser(text) {
  const flat = text.replace(/\s+/g, " ").trim();
  if (flat.length <= USER_MAX) return flat;
  const originalLineCount = text.split("\n").length;
  const headEnd = snapToWordBoundary(flat, USER_HEAD, "end");
  const tailStart = snapToWordBoundary(flat, flat.length - USER_TAIL, "start");
  const head = flat.slice(0, headEnd).trim();
  const tail = flat.slice(tailStart).trim();
  const omittedLines = Math.max(1, originalLineCount - 2);
  return head + ` ..[${omittedLines}lines omitted].. ` + tail;
}

function truncateAssistant(text) {
  const oneLine = text.replace(/\s+/g, " ").trim();
  if (oneLine.length <= AI_MAX) return oneLine;
  const headEnd = snapToWordBoundary(oneLine, AI_HEAD, "end");
  const tailStart = snapToWordBoundary(oneLine, oneLine.length - AI_TAIL, "start");
  const head = oneLine.slice(0, headEnd).trim();
  const tail = oneLine.slice(tailStart).trim();
  return head + " [...truncated...] " + tail;
}

function countStructural(text) {
  const fenceMatches = text.match(/```/g);
  const codeCount = fenceMatches ? Math.floor(fenceMatches.length / 2) : 0;
  const tableMatches = text.match(/^\s*\|?[\s:-]*\|[\s:|-]*\|?\s*$/gm) || [];
  const tableCount = tableMatches.filter((l) => /---/.test(l)).length;
  const listLineRe = /^\s*(?:[-*+]|\d+\.)\s+/;
  const linesArr = text.split("\n");
  let listBlocks = 0;
  let run = 0;
  for (const ln of linesArr) {
    if (listLineRe.test(ln)) {
      run++;
    } else {
      if (run >= 3) listBlocks++;
      run = 0;
    }
  }
  if (run >= 3) listBlocks++;
  return { code: codeCount, table: tableCount, list: listBlocks };
}

function formatStructural(counts) {
  const parts = [];
  if (counts.code > 0) parts.push(`+${counts.code} code`);
  if (counts.table > 0) parts.push(`${counts.table} table`);
  if (counts.list > 0) parts.push(`${counts.list} list`);
  if (parts.length === 0) return "";
  return " [" + parts.join(", ") + "]";
}

function toISOUtc(ts) {
  if (!ts) return "";
  try {
    const d = new Date(ts);
    if (isNaN(d.getTime())) return "";
    return d.toISOString().replace(/\.\d{3}Z$/, "Z");
  } catch {
    return "";
  }
}

function deriveCachePath(jsonlAbsPath) {
  const sessionId = path.basename(jsonlAbsPath, ".jsonl");
  const projectHash = path.basename(path.dirname(jsonlAbsPath));
  const cacheDir = path.join(os.homedir(), ".claude", "wh0Hoo", projectHash, sessionId);
  return { cacheDir, cachePath: path.join(cacheDir, "compact.txt"), sessionId, projectHash };
}

function readFormatVersion(filePath) {
  try {
    const fd = fs.openSync(filePath, "r");
    const buf = Buffer.alloc(128);
    const n = fs.readSync(fd, buf, 0, 128, 0);
    fs.closeSync(fd);
    const m = buf.toString("utf8").match(/^# compact-format:\s*(\d+)/m);
    return m ? Number(m[1]) : 1;
  } catch { return 0; }
}

function isCacheFresh(cachePath, jsonlPath) {
  if (!fs.existsSync(cachePath)) return false;
  try {
    const ver = readFormatVersion(cachePath);
    if (ver < COMPACT_FORMAT_VERSION) return false;
    const cacheMtime = fs.statSync(cachePath).mtime;
    const jsonlMtime = fs.statSync(jsonlPath).mtime;
    return cacheMtime >= jsonlMtime;
  } catch { return false; }
}

async function main() {
  const filePath = process.argv[2];

  if (!filePath) {
    process.stderr.write("Usage: node preprocess.js <transcript.jsonl>\n");
    process.exit(1);
  }

  const absPath = path.resolve(filePath);
  if (!fs.existsSync(absPath)) {
    process.stderr.write(`Error: file not found: ${absPath}\n`);
    process.exit(1);
  }

  const { cacheDir, cachePath, projectHash } = deriveCachePath(absPath);

  // Sweep project cache: delete all pre-v6 compact files
  const projectCacheDir = path.join(os.homedir(), ".claude", "wh0Hoo", projectHash);
  if (fs.existsSync(projectCacheDir)) {
    for (const entry of fs.readdirSync(projectCacheDir)) {
      const sessionDir = path.join(projectCacheDir, entry);
      try { if (!fs.statSync(sessionDir).isDirectory()) continue; } catch { continue; }
      for (const name of ["compact.txt", "compact.aggressive.txt"]) {
        const p = path.join(sessionDir, name);
        if (!fs.existsSync(p)) continue;
        if (readFormatVersion(p) < 6) { try { fs.unlinkSync(p); } catch {} }
      }
    }
  }

  if (isCacheFresh(cachePath, absPath)) return;

  const baseName = path.basename(absPath, ".jsonl");
  const sid8 = baseName.slice(0, 8);

  const stream = fs.createReadStream(absPath, { encoding: "utf-8" });
  const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });

  const messages = [];
  let pendingMarker = "";
  let lineNum = 0;
  let isFirstUserMessage = true;
  let inContinueSkill = false;
  const continueCompactFiles = new Set();

  function addMarker(mark) {
    if (mark === "@@") {
      if (!pendingMarker.includes("@@")) pendingMarker = "@@" + pendingMarker;
    } else if (mark === "++") {
      if (!pendingMarker.includes("++")) {
        if (pendingMarker.endsWith("+") && !pendingMarker.endsWith("++")) {
          pendingMarker = pendingMarker.slice(0, -1) + "++";
        } else {
          pendingMarker += "++";
        }
      }
    } else if (mark === "+") {
      if (!pendingMarker.includes("+")) pendingMarker += "+";
    } else {
      if (!pendingMarker.includes(mark)) pendingMarker += mark;
    }
  }

  function flushContinueMarker() {
    if (inContinueSkill) {
      const mark = continueCompactFiles.size > 1 ? "^^" : "^";
      addMarker(mark);
      continueCompactFiles.clear();
    }
    inContinueSkill = false;
  }

  for await (const line of rl) {
    lineNum++;
    const trimmed = line.trim();
    if (!trimmed) continue;

    let obj;
    try {
      obj = JSON.parse(trimmed);
    } catch {
      continue;
    }

    const type = obj.type;
    const content = obj.message?.content ?? obj.content;
    const ts = obj.timestamp || obj.message?.timestamp || "";

    if (type === "system" && obj.subtype === "compact_boundary") {
      const trigger = obj.compactMetadata && obj.compactMetadata.trigger;
      if (trigger === "auto") addMarker("++");
      else addMarker("+");
      messages.push({
        kind: "system",
        raw: trigger === "auto" ? "[auto-compact boundary]" : "[manual compact boundary]",
        lineNum,
        ts,
        markers: "",
      });
      continue;
    }

    if (obj.message && obj.message.isCompactSummary === true) {
      addMarker("++");
      messages.push({
        kind: "system",
        raw: "[auto-compact summary injected]",
        lineNum,
        ts,
        markers: "",
      });
      continue;
    }

    if (type === "user") {
      let rawForCmd = typeof content === "string" ? content : extractAssistantText(content);
      rawForCmd = rawForCmd.replace(/<task-notification>[\s\S]*?<\/task-notification>/g, "");
      const cmdNameMatch = rawForCmd && rawForCmd.match(/<command-name>(\/[^<]+)<\/command-name>/);

      if (cmdNameMatch) {
        const cmdName = cmdNameMatch[1].trim();
        const cmdArgsMatch = rawForCmd.match(/<command-args>([^<]*)<\/command-args>/);
        const cmdArgs = cmdArgsMatch ? cmdArgsMatch[1].trim() : "";

        const cmdKey = cmdName.replace(/^\//, "").split(":").pop();
        if (cmdKey === "clear") addMarker("@@");
        else if (cmdKey === "compact") addMarker("+");
        else if (cmdKey === "reload-plugins") addMarker("~");
        else if (cmdKey === "model") addMarker("!");

        if (cmdKey === "clear") continue;

        if (cmdKey === "continue") {
          inContinueSkill = true;
        }

        const commandText = cmdArgs ? `${cmdName} ${cmdArgs}` : cmdName;
        messages.push({
          kind: "user",
          raw: commandText,
          lineNum,
          ts,
          markers: "",
        });
        continue;
      }

      if (inContinueSkill && !obj.isMeta) {
        flushContinueMarker();
      }

      if (obj.isMeta) continue;

      if (Array.isArray(content)) {
        const hasText = content.some((b) => b && b.type === "text" && b.text);
        const hasImage = content.some((b) => b && b.type === "image");
        if (!hasText && !hasImage) continue;
      }

      const rawText = extractUserTextWithImages(content);
      const cleaned = cleanText(rawText);
      const text = abstractUserContent(cleaned);
      if (!text || shouldSkipUser(text)) continue;

      let markers = pendingMarker;
      if (isFirstUserMessage && !markers) {
        markers = "@";
      }
      isFirstUserMessage = false;
      pendingMarker = "";

      messages.push({
        kind: "user",
        raw: text,
        lineNum,
        ts,
        markers,
      });
    } else if (type === "assistant") {
      if (obj.error === "rate_limit") continue;
      if (inContinueSkill && Array.isArray(content)) {
        for (const block of content) {
          if (block && block.type === "tool_use" && block.name === "Read" && block.input && block.input.file_path) {
            const m = block.input.file_path.match(/\/wh0Hoo\/[^/]+\/([^/]+)\/compact/);
            if (m) continueCompactFiles.add(m[1]);
          }
        }
      }
      const rawText = extractAssistantText(content);
      const cleaned = cleanText(rawText);
      if (!cleaned) continue;
      messages.push({
        kind: "asst",
        raw: cleaned,
        lineNum,
        ts,
      });
    }
  }

  // Group into turns
  const turns = [];
  let current = null;
  for (const m of messages) {
    if (m.kind === "user" || m.kind === "system") {
      if (current) turns.push(current);
      current = { user: m, assts: [] };
    } else if (m.kind === "asst") {
      if (current) current.assts.push(m);
    }
  }
  if (current) turns.push(current);

  // Render
  const out = [];
  out.push(`# compact-format: ${COMPACT_FORMAT_VERSION}`);
  out.push("");

  for (const turn of turns) {
    const u = turn.user;
    const iso = toISOUtc(u.ts);
    const header = `[Session:${sid8} ${iso} L${u.lineNum}]${u.markers}`;
    const roleLabel = u.kind === "system" ? "System" : "User";
    const userPreview = truncateUser(u.raw).replace(/\n/g, " ");
    out.push(`${header} ${roleLabel}: "${userPreview}"`);

    const assts = turn.assts;
    if (assts.length === 0) {
      out.push(`-> 0 AI responses`);
      out.push("");
      continue;
    }

    const lineNums = assts.map((a) => a.lineNum);
    const minL = Math.min(...lineNums);
    const maxL = Math.max(...lineNums);
    const refLabel =
      assts.length === 1
        ? `-> 1 AI response at line ${minL}:`
        : `-> ${assts.length} AI responses at lines ${minL}-${maxL}:`;
    out.push(refLabel);

    assts.forEach((a, i) => {
      const preview = truncateAssistant(a.raw).replace(/\n/g, " ");
      const counts = countStructural(a.raw);
      const suffix = formatStructural(counts);
      out.push(`${i + 1}. "${preview}"${suffix}`);
    });
    out.push("");
  }

  out.push("---");
  out.push("# Session references:");
  out.push(`- Session ${sid8} → ${absPath}`);
  out.push(`# [Session:{sid} {ISO} L{n}] headers link to original transcripts at ~/.claude/projects/{projectHash}/{sessionId}.jsonl — use L{n} to read the exact line.`);

  fs.mkdirSync(cacheDir, { recursive: true });
  fs.writeFileSync(cachePath, out.join("\n") + "\n");
}

main().catch((err) => {
  process.stderr.write(`preprocess.js error: ${err.message}\n`);
  process.exit(1);
});
