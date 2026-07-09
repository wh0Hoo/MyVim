-------------------------------------------------------------------------------
-- ccgen.lua
--
-- clangd 용 compile_commands.json 자동 생성
--
-- 사용법:
--   :CCGen     — 스캔 → include 경로 추론 → compile_commands.json 생성 → clangd 재시작
--   :CCGenInfo — 파일을 만들지 않고 추론 결과 미리보기
--
-- 스캔 순서: git ls-files (미추적 포함) → 실패 시 파일시스템 스캔 폴백
--
-- 파일 목록이 담긴 compile_commands.json 이 있어야 clangd 백그라운드 인덱스가
-- 프로젝트 전체를 인덱싱하고, 열어본 적 없는 .c 의 구현부로도 점프할 수 있다.
-- 최초 생성 직후 인덱싱에 시간이 걸릴 수 있다 (캐시: ~/.cache/clangd/)
--
-- 프로젝트별 설정 (.ccgen.lua, 프로젝트 루트에 배치, 선택사항):
--
--   return {
--     -- 크로스 컴파일러 (없으면 "clang")
--     compiler = "/opt/toolchain/bin/arm-linux-gnueabihf-gcc",
--
--     -- 추가 플래그
--     flags = {
--       "--target=arm-linux-gnueabihf",
--       "--sysroot=/opt/toolchain/sysroot",
--       "-std=gnu11",
--     },
--
--     -- 추가 인클루드 경로 (자동 추론 외 수동 추가)
--     extra_includes = { "/opt/toolchain/sysroot/usr/include" },
--
--     -- whitelist: 지정 시 해당 경로만 스캔 (미지정 시 git → 전체 스캔)
--     source_dirs = { "src", "lib" },
--
--     -- 파일시스템 스캔 시 제외 디렉토리 (기본값에 추가)
--     ignore_dirs = { "build", "third_party" },
--   }
--
-- ※ 생성된 compile_commands.json 은 절대 경로를 포함하므로 커밋하지 말 것
-------------------------------------------------------------------------------

local M = {}

M.defaults = {
  compiler       = "clang",
  flags          = {},
  extra_includes = {},
  source_dirs    = {},  -- whitelist; 비어있으면 전체 스캔
  ignore_dirs    = {},

  source_extensions = { [".c"]=true, [".cpp"]=true, [".cc"]=true, [".cxx"]=true },
  header_extensions = { [".h"]=true, [".hpp"]=true, [".hxx"]=true },
  default_ignore_dirs = { "%.git", "node_modules", "%.cache", "__pycache__" },
}

-- include 분석 시 한 번에 처리할 파일 수 (배치 사이에 메인 루프에 양보)
local BATCH = 200

-- 실행 중 재진입 방지
local running = false

-------------------------------------------------------------------------------
-- 유틸리티
-------------------------------------------------------------------------------

local function notify(msg, level)
  vim.notify("[ccgen] " .. msg, level or vim.log.levels.INFO)
end

-- cmdline 한 줄 진행 표시 (메시지 히스토리에 남기지 않음)
local function progress(msg)
  vim.api.nvim_echo({ { "[ccgen] " .. msg } }, false, {})
end

local function get_ext(path)
  return path:match("(%.[^%.]+)$") or ""
end

local function read_file(path)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" then return nil end
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then return nil end
  local data = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  return data
end

-------------------------------------------------------------------------------
-- 설정
-------------------------------------------------------------------------------

local function resolve_config(root_dir)
  local proj = {}
  local path = root_dir .. "/.ccgen.lua"
  if vim.uv.fs_stat(path) then
    local ok, cfg = pcall(dofile, path)
    if not ok then
      notify(".ccgen.lua 로드 실패: " .. tostring(cfg), vim.log.levels.WARN)
    elseif type(cfg) == "table" then
      proj = cfg
    end
  end
  return {
    compiler       = proj.compiler or M.defaults.compiler,
    flags          = proj.flags or M.defaults.flags,
    extra_includes = proj.extra_includes or M.defaults.extra_includes,
    source_dirs    = proj.source_dirs or M.defaults.source_dirs,
    source_extensions = M.defaults.source_extensions,
    header_extensions = M.defaults.header_extensions,
    ignore_dirs = vim.list_extend(
      vim.deepcopy(M.defaults.default_ignore_dirs),
      proj.ignore_dirs or {}
    ),
  }
end

-------------------------------------------------------------------------------
-- 파일 스캔 → 소스/헤더 절대 경로 목록
-------------------------------------------------------------------------------

local function classify(path, cfg, sources, headers)
  local ext = get_ext(path)
  if cfg.source_extensions[ext] then table.insert(sources, path) end
  if cfg.header_extensions[ext] then table.insert(headers, path) end
end

-- 상대 경로의 디렉토리 세그먼트가 ignore_dirs 패턴에 걸리는지 (파일명은 제외)
local function path_ignored(rel, patterns)
  local dir = rel:match("^(.+)/[^/]+$")
  if not dir then return false end
  for seg in dir:gmatch("[^/]+") do
    for _, p in ipairs(patterns) do
      if seg:match(p) then return true end
    end
  end
  return false
end

local function scan_fs(dir, cfg, sources, headers)
  local handle = vim.uv.fs_scandir(dir)
  if not handle then return end
  while true do
    local name, ftype = vim.uv.fs_scandir_next(handle)
    if not name then break end
    local full = dir .. "/" .. name
    if ftype == "link" then
      local st = vim.uv.fs_stat(full)
      ftype = st and st.type or nil
    end
    if ftype == "directory" then
      local ignored = false
      for _, p in ipairs(cfg.ignore_dirs) do
        if name:match(p) then ignored = true; break end
      end
      if not ignored then scan_fs(full, cfg, sources, headers) end
    elseif ftype == "file" then
      classify(full, cfg, sources, headers)
    end
  end
end

-- 성공 시 on_done(소스, 헤더), git 실패(비-git 저장소 등) 시 on_done(nil)
local function scan_git(root_dir, cfg, on_done)
  local ok = pcall(vim.system, {
    "git", "-C", root_dir,
    "ls-files", "--cached", "--others", "--exclude-standard",
  }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then return on_done(nil) end
      local sources, headers = {}, {}
      for rel in vim.gsplit(res.stdout or "", "\n", { plain = true }) do
        if rel ~= "" and not path_ignored(rel, cfg.ignore_dirs) then
          classify(root_dir .. "/" .. rel, cfg, sources, headers)
        end
      end
      on_done(sources, headers)
    end)
  end)
  if not ok then on_done(nil) end  -- git 미설치
end

local function scan_project(root_dir, cfg, on_done)
  if #cfg.source_dirs > 0 then
    local sources, headers = {}, {}
    for _, d in ipairs(cfg.source_dirs) do
      scan_fs(root_dir .. "/" .. d, cfg, sources, headers)
    end
    return on_done(sources, headers)
  end
  scan_git(root_dir, cfg, function(sources, headers)
    if sources then return on_done(sources, headers) end
    notify("git 스캔 실패, 파일시스템 스캔으로 대체합니다")
    local s, h = {}, {}
    scan_fs(root_dir, cfg, s, h)
    on_done(s, h)
  end)
end

-------------------------------------------------------------------------------
-- include 경로 추론 (파일별 전이 의존성)
--
-- CDB 크기 = 소스 수 × 엔트리당 -I 수 이므로, 전 엔트리에 프로젝트 전체
-- include 경로를 복제하면 대형 트리에서 폭발한다. 각 소스가 #include 체인으로
-- 실제 도달하는 헤더의 디렉토리만 그 엔트리에 담아 크기를 선형으로 유지한다.
-------------------------------------------------------------------------------

-- 헤더 basename → 위치한 디렉토리 목록 (파일 읽기 없음)
local function build_header_index(headers)
  local index = {}
  for _, path in ipairs(headers) do
    local name = path:match("([^/]+)$")
    local dir  = path:match("^(.+)/[^/]+$")
    if name and dir then
      index[name] = index[name] or {}
      table.insert(index[name], dir)
    end
  end
  return index
end

-- 파일의 #include 대상 이름 목록 (한 번 읽고 캐시)
local function file_includes(path, cache)
  local cached = cache[path]
  if cached then return cached end
  local out, seen = {}, {}
  local data = read_file(path)
  if data then
    for h in data:gmatch('#%s*include%s*["<]([^">]+)[">]') do
      if not seen[h] then seen[h] = true; table.insert(out, h) end
    end
  end
  cache[path] = out
  return out
end

-- include 이름 → { {dir=-I경로, file=해석된 헤더경로}, ... } (한 번 계산하고 캐시)
-- "sub/foo.h" 형태는 sub 를 뺀 상위 디렉토리를 -I 로 사용
local function resolve_include(inc, header_index, cache)
  local cached = cache[inc]
  if cached then return cached end
  local out = {}
  local basename = inc:match("([^/]+)$")
  local subpath  = inc:match("^(.+)/[^/]+$")
  for _, dir in ipairs(header_index[basename] or {}) do
    if subpath then
      local suffix = "/" .. subpath
      if dir:sub(-#suffix) == suffix then
        local parent = dir:sub(1, -#suffix - 1)
        if parent ~= "" then
          table.insert(out, { dir = parent, file = dir .. "/" .. basename })
        end
      end
    else
      table.insert(out, { dir = dir, file = dir .. "/" .. basename })
    end
  end
  cache[inc] = out
  return out
end

-- 소스 하나가 전이적으로 필요로 하는 -I 디렉토리 (정렬된 목록)
-- visited 집합으로 순환 include 를 차단, inc_cache/res_cache 는 소스 간 공유
local function source_include_dirs(src, header_index, inc_cache, res_cache)
  local dirs, visited = {}, { [src] = true }
  local stack = { src }
  while #stack > 0 do
    local f = table.remove(stack)
    for _, inc in ipairs(file_includes(f, inc_cache)) do
      for _, r in ipairs(resolve_include(inc, header_index, res_cache)) do
        dirs[r.dir] = true
        if not visited[r.file] then
          visited[r.file] = true
          stack[#stack + 1] = r.file
        end
      end
    end
  end
  local list = {}
  for d in pairs(dirs) do list[#list + 1] = d end
  table.sort(list)
  return list
end

-- 각 소스별 -I 목록 계산 → on_done({ [src]=dirs })
-- 소스를 BATCH 단위로 처리하고 사이사이 메인 루프에 양보해 UI 를 유지한다
local function infer_per_file(sources, headers, on_done)
  local header_index = build_header_index(headers)
  local inc_cache, res_cache = {}, {}
  local per_file = {}
  local pos = 1
  local function step()
    local last = math.min(pos + BATCH - 1, #sources)
    for i = pos, last do
      per_file[sources[i]] =
        source_include_dirs(sources[i], header_index, inc_cache, res_cache)
    end
    pos = last + 1
    progress(string.format("include 분석 %d/%d...", last, #sources))
    if pos <= #sources then return vim.schedule(step) end
    on_done(per_file)
  end
  step()
end

-- per_file 에서 통계 (전체 고유 -I 수, 엔트리당 최대) 산출
local function dir_stats(per_file)
  local union, max_n = {}, 0
  for _, dirs in pairs(per_file) do
    if #dirs > max_n then max_n = #dirs end
    for _, d in ipairs(dirs) do union[d] = true end
  end
  return vim.tbl_count(union), max_n
end

-------------------------------------------------------------------------------
-- compile_commands.json 생성
-------------------------------------------------------------------------------

-- 소스 하나의 arguments = compiler + flags + 그 파일의 -I + extra_includes + -c file
local function entry_args(cfg, dirs, src)
  local args = { cfg.compiler }
  for _, f in ipairs(cfg.flags) do table.insert(args, f) end
  for _, dir in ipairs(dirs) do table.insert(args, "-I" .. dir) end
  for _, dir in ipairs(cfg.extra_includes) do table.insert(args, "-I" .. dir) end
  table.insert(args, "-c")
  table.insert(args, src)
  return args
end

-- 엔트리별 개별 인코딩 후 순차 기록 — 전체 일괄 인코딩은 문자열 길이 한계 위험
local function write_cdb(root_dir, cfg, per_file, sources)
  local path = root_dir .. "/compile_commands.json"
  local tmp = path .. ".tmp"
  local fd = vim.uv.fs_open(tmp, "w", 420)
  if not fd then
    notify("파일 쓰기 실패: " .. tmp, vim.log.levels.ERROR)
    return false
  end
  local offset, ok = 0, true
  local function write(s)
    if not ok then return end
    local bytes = vim.uv.fs_write(fd, s, offset)
    if not bytes or bytes < #s then ok = false; return end
    offset = offset + bytes
  end
  write("[\n")
  for i, src in ipairs(sources) do
    write((i > 1 and ",\n" or "") .. vim.json.encode({
      directory = root_dir, file = src,
      arguments = entry_args(cfg, per_file[src], src),
    }))
  end
  write("\n]\n")
  vim.uv.fs_close(fd)
  if not ok then
    vim.uv.fs_unlink(tmp)
    notify("파일 쓰기 실패: " .. tmp, vim.log.levels.ERROR)
    return false
  end
  if not vim.uv.fs_rename(tmp, path) then
    notify("파일 이름 변경 실패: " .. path, vim.log.levels.ERROR)
    return false
  end
  return true
end

-- clangd 는 이미 열린 파일에 CDB 변경을 반영하지 않으므로 재시작 (0.11.2+)
local function restart_clangd()
  if #vim.lsp.get_clients({ name = "clangd" }) == 0 then return end
  vim.lsp.enable("clangd", false)
  vim.defer_fn(function() vim.lsp.enable("clangd") end, 200)
end

-------------------------------------------------------------------------------
-- 공개 API / 사용자 명령
-------------------------------------------------------------------------------

local function project_root()
  for _, c in pairs(vim.lsp.get_clients({ name = "clangd" })) do
    if c.config.root_dir then return c.config.root_dir end
  end
  local cwd = vim.uv.cwd()
  notify("활성 clangd 가 없어 cwd 를 사용합니다: " .. cwd)
  return cwd
end

function M.generate()
  if running then return notify("이미 실행 중입니다", vim.log.levels.WARN) end
  running = true
  local root_dir = project_root()
  local cfg = resolve_config(root_dir)
  progress("파일 스캔 중...")
  scan_project(root_dir, cfg, function(sources, headers)
    if #sources == 0 then
      running = false
      return notify("소스 파일을 찾지 못했습니다: " .. root_dir, vim.log.levels.WARN)
    end
    infer_per_file(sources, headers, function(per_file)
      progress("compile_commands.json 쓰는 중...")
      local ok = write_cdb(root_dir, cfg, per_file, sources)
      running = false
      if not ok then return end
      local total, max_n = dir_stats(per_file)
      notify(string.format("완료: 소스 %d개, 고유 -I %d개 (엔트리당 최대 %d개) → %s/compile_commands.json",
        #sources, total, max_n, root_dir))
      restart_clangd()
    end)
  end)
end

function M.info()
  if running then return notify("이미 실행 중입니다", vim.log.levels.WARN) end
  running = true
  local root_dir = project_root()
  local cfg = resolve_config(root_dir)
  progress("파일 스캔 중...")
  scan_project(root_dir, cfg, function(sources, headers)
  infer_per_file(sources, headers, function(per_file)
  running = false

  local union = {}
  for _, dirs in pairs(per_file) do
    for _, d in ipairs(dirs) do union[d] = true end
  end
  local dirs = {}
  for d in pairs(union) do table.insert(dirs, d) end
  table.sort(dirs)
  local _, max_n = dir_stats(per_file)

  local lines = {
    "프로젝트: " .. root_dir,
    "컴파일러: " .. cfg.compiler,
    "플래그: " .. (#cfg.flags > 0 and table.concat(cfg.flags, " ") or "(없음)"),
    "소스 파일: " .. #sources .. "개",
    string.format("고유 -I: %d개 (엔트리당 최대 %d개)", #dirs, max_n),
    "",
    "자동 추론 -I:",
  }
  for _, dir in ipairs(dirs) do
    local rel = dir
    if dir:sub(1, #root_dir + 1) == root_dir .. "/" then
      rel = dir:sub(#root_dir + 2)
    elseif dir == root_dir then
      rel = "."
    end
    table.insert(lines, "  " .. rel)
  end
  if #cfg.extra_includes > 0 then
    table.insert(lines, "")
    table.insert(lines, "수동 추가 (" .. #cfg.extra_includes .. "개):")
    for _, dir in ipairs(cfg.extra_includes) do
      table.insert(lines, "  " .. dir)
    end
  end
  notify(table.concat(lines, "\n"))
  end) -- infer_per_file
  end) -- scan_project
end

vim.api.nvim_create_user_command("CCGen", M.generate, { desc = "compile_commands.json 생성 후 clangd 재시작" })
vim.api.nvim_create_user_command("CCGenInfo", M.info, { desc = "추론된 include 경로 미리보기" })

return M
