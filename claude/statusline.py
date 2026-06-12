#!/usr/bin/env python3
import json, sys, os, glob, time, re, shutil, fcntl, termios, struct
import hashlib, urllib.request
from datetime import datetime, timezone, timedelta

PRICING = {
    'claude-fable-5':     {'in': 10.0,  'out': 50.0,  'cw': 12.50, 'cr': 1.00},
    'claude-opus-4-8':    {'in': 5.0,   'out': 25.0,  'cw': 6.25,  'cr': 0.50},
    'claude-sonnet-4-6':  {'in': 3.0,   'out': 15.0,  'cw': 3.75,  'cr': 0.30},
    'claude-opus-4-7':    {'in': 5.0,   'out': 25.0,  'cw': 6.25,  'cr': 0.50},
    'claude-opus-4-5':    {'in': 5.0,   'out': 25.0,  'cw': 6.25,  'cr': 0.50},
    'claude-haiku-4-5':   {'in': 1.0,   'out': 5.0,   'cw': 1.25,  'cr': 0.10},
    'claude-sonnet-4-5':  {'in': 3.0,   'out': 15.0,  'cw': 3.75,  'cr': 0.30},
}
DEFAULT_P = PRICING['claude-sonnet-4-6']

ADVISOR_DISPLAY = {
    'opus':   'Opus',
    'sonnet': 'Sonnet',
    'haiku':  'Haiku',
}

WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
CACHE_PATH = '/tmp/statusline_weekly_cost.json'
CACHE_TTL = 300  # 5 minutes

R      = '\033[0m'
BOLD   = '\033[1m'
DIM    = '\033[2m'
CYAN   = '\033[1;36m'   # model name
YELLOW = '\033[1;33m'   # advisor, cost
GREEN  = '\033[1;32m'   # Session label
BLUE   = '\033[1;34m'   # Weekly label
MAGENTA= '\033[35m'     # ctx
RED    = '\033[1;31m'   # high usage

def _get_term_width() -> int:
    # /dev/tty로 제어 터미널 너비 직접 감지 (stdio가 파이프여도 동작)
    method = 'fallback'
    cols = 120
    try:
        fd = os.open('/dev/tty', os.O_RDONLY)
        try:
            buf = fcntl.ioctl(fd, termios.TIOCGWINSZ, b'\x00' * 8)
            c = struct.unpack('HH', buf[:4])[1]
            if c > 0:
                cols, method = c, '/dev/tty'
        finally:
            os.close(fd)
    except Exception as e:
        try:
            c = int(os.environ.get('COLUMNS', 0))
            if c > 0:
                cols, method = c, 'COLUMNS'
        except Exception:
            pass
    return cols - 4  # Claude Code statusline 표시 영역 여유 확보

def strip_ansi(s: str) -> str:
    return re.sub(r'\033\[[0-9;]*m', '', s)

def visible_len(s: str) -> int:
    return len(strip_ansi(s))

def wrap_segments(segments: list, sep: str, width: int) -> str:
    sep_vis = visible_len(sep)
    lines, cur, cur_len = [], [], 0
    for seg in segments:
        vlen = visible_len(seg)
        if cur:
            if cur_len + sep_vis + vlen > width:
                lines.append(sep.join(cur))
                cur, cur_len = [seg], vlen
            else:
                cur.append(seg)
                cur_len += sep_vis + vlen
        else:
            cur.append(seg)
            cur_len = vlen
    if cur:
        lines.append(sep.join(cur))
    return '\n'.join(lines)

def pct_color(pct) -> str:
    if pct is None:  return DIM
    if pct >= 80:    return RED
    if pct >= 50:    return YELLOW
    return GREEN

def get_pricing(model: str) -> dict:
    for key, p in PRICING.items():
        if key in (model or ''):
            return p
    return DEFAULT_P

def calc_cost(usage: dict, model: str) -> float:
    p = get_pricing(model)
    return (
        usage.get('input_tokens', 0)                * p['in']  / 1e6 +
        usage.get('output_tokens', 0)               * p['out'] / 1e6 +
        usage.get('cache_creation_input_tokens', 0) * p['cw']  / 1e6 +
        usage.get('cache_read_input_tokens', 0)     * p['cr']  / 1e6
    )

def _model_id_to_display(model_id: str) -> str:
    m = model_id.lower()
    if 'opus' in m:   return 'Opus'
    if 'sonnet' in m: return 'Sonnet'
    if 'haiku' in m:  return 'Haiku'
    return model_id.capitalize() if model_id else ''

def read_advisor_model(transcript_path: str) -> str:
    # JSONL 트랜스크립트 끝에서부터 assistant 엔트리의 advisorModel 탐색
    if transcript_path:
        try:
            with open(transcript_path, 'rb') as f:
                f.seek(0, 2)
                size = f.tell()
                chunk = min(size, 8192)
                f.seek(-chunk, 2)
                tail = f.read().decode('utf-8', errors='ignore')
            for line in reversed(tail.splitlines()):
                if not line.strip():
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if d.get('type') == 'assistant' and 'advisorModel' in d:
                    return _model_id_to_display(d['advisorModel'])
        except Exception:
            pass
    # fallback: settings.json
    try:
        cfg_path = os.path.expanduser('~/.claude/settings.json')
        with open(cfg_path) as f:
            cfg = json.load(f)
        key = cfg.get('advisorModel', '')
        return ADVISOR_DISPLAY.get(key, _model_id_to_display(key))
    except Exception:
        return ''

def parse_ts(ts):
    try:
        if isinstance(ts, (int, float)):
            return datetime.fromtimestamp(ts, tz=timezone.utc)
        return datetime.fromisoformat(str(ts).replace('Z', '+00:00'))
    except Exception:
        return None

def fmt_remain(seconds: float) -> str:
    if seconds <= 0:
        return '0h00m'
    total_min = int(seconds // 60)
    days = total_min // (24 * 60)
    hours = (total_min % (24 * 60)) // 60
    mins = total_min % 60
    if days >= 1:
        return f'{days}d{hours}h'
    return f'{hours}h{mins:02d}m'

def fmt_limit(rate_limit: dict, is_5h: bool) -> str:
    if not rate_limit:
        return '(--, --) --%'

    resets_at = rate_limit.get('resets_at')
    used_pct = rate_limit.get('used_percentage')

    if not resets_at:
        return '(--, --) --%'

    reset_dt = parse_ts(resets_at)
    if not reset_dt:
        return '(--, --) --%'

    now = datetime.now(timezone.utc)
    local_dt = reset_dt.astimezone()

    if is_5h:
        abs_str = local_dt.strftime('%H:%M')
    else:
        weekday = WEEKDAYS[local_dt.weekday()]
        abs_str = f'{weekday} {local_dt.strftime("%H:%M")}'

    remain_sec = (reset_dt - now).total_seconds()
    rel_str = fmt_remain(remain_sec)

    pc = pct_color(used_pct)
    pct_str = f'{pc}{used_pct:.0f}%{R}' if used_pct is not None else f'{DIM}--%{R}'

    return f'({DIM}{abs_str}{R}, in {rel_str}) {pct_str}'

def compute_weekly_cost() -> float:
    now = datetime.now(timezone.utc)
    week_ago = now - timedelta(days=7)
    total = 0.0
    for fpath in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
        try:
            with open(fpath, 'r', errors='ignore') as f:
                for line in f:
                    if not line.strip():
                        continue
                    try:
                        d = json.loads(line)
                    except Exception:
                        continue
                    if d.get('type') != 'assistant':
                        continue
                    ts = parse_ts(d.get('timestamp', ''))
                    if not ts or ts < week_ago:
                        continue
                    msg = d.get('message') or {}
                    usage = msg.get('usage') or d.get('usage') or {}
                    model = msg.get('model', '')
                    if usage:
                        total += calc_cost(usage, model)
        except Exception:
            continue
    return total

def get_weekly_cost() -> float:
    try:
        with open(CACHE_PATH) as f:
            cache = json.load(f)
        if time.time() - cache.get('ts', 0) < CACHE_TTL:
            return cache.get('cost', 0.0)
    except Exception:
        pass
    cost = compute_weekly_cost()
    try:
        with open(CACHE_PATH, 'w') as f:
            json.dump({'ts': time.time(), 'cost': cost}, f)
    except Exception:
        pass
    return cost

def probe_rate_limits():
    # ANTHROPIC_AUTH_TOKEN 세션용: Claude Code가 rate_limits를 전달하지 않으므로
    # 최소 비용 API 호출의 응답 헤더(anthropic-ratelimit-unified-*)에서 직접 조회
    token = os.environ.get('ANTHROPIC_AUTH_TOKEN')
    if not token:
        return None
    h = hashlib.sha256(token.encode()).hexdigest()[:12]
    cache_path = f'/tmp/statusline_probe_{h}.json'
    cached = None
    try:
        with open(cache_path) as f:
            cached = json.load(f)
        if time.time() - cached.get('ts', 0) < CACHE_TTL:
            return cached.get('data')
    except Exception:
        pass
    # 동시 실행 중복 호출 방지: ts를 먼저 기록 (다른 인스턴스는 5분간 stale 사용)
    try:
        with open(cache_path, 'w') as f:
            json.dump({'ts': time.time(),
                       'data': cached.get('data') if cached else None}, f)
    except Exception:
        pass
    try:
        req = urllib.request.Request(
            'https://api.anthropic.com/v1/messages',
            data=json.dumps({
                'model': 'claude-haiku-4-5', 'max_tokens': 1,
                'messages': [{'role': 'user', 'content': 'hi'}],
            }).encode(),
            headers={
                'Authorization': f'Bearer {token}',
                'anthropic-version': '2023-06-01',
                'anthropic-beta': 'oauth-2025-04-20',
                'content-type': 'application/json',
            },
        )
        with urllib.request.urlopen(req, timeout=3) as resp:
            hdr = resp.headers
        data = {}
        for key, prefix in (('five_hour', '5h'), ('seven_day', '7d')):
            util = hdr.get(f'anthropic-ratelimit-unified-{prefix}-utilization')
            reset = hdr.get(f'anthropic-ratelimit-unified-{prefix}-reset')
            if util is not None and reset is not None:
                data[key] = {'used_percentage': float(util) * 100,
                             'resets_at': int(reset)}
        if not data:
            raise ValueError('no rate limit headers')
        with open(cache_path, 'w') as f:
            json.dump({'ts': time.time(), 'data': data}, f)
        return data
    except Exception:
        return cached.get('data') if cached else None


def main():
    stdin_data = json.loads(sys.stdin.read() or '{}')

    model_name = (stdin_data.get('model') or {}).get('display_name') or 'unknown'
    transcript_path = stdin_data.get('transcript_path', '')
    advisor = read_advisor_model(transcript_path)
    model_str = (f'{CYAN}{model_name}{R}({YELLOW}{advisor}{R})'
                 if advisor else f'{CYAN}{model_name}{R}')

    rate_limits = stdin_data.get('rate_limits') or {}
    if not rate_limits:
        rate_limits = probe_rate_limits() or {}
    session_str = fmt_limit(rate_limits.get('five_hour') or {}, is_5h=True)
    weekly_str  = fmt_limit(rate_limits.get('seven_day') or {}, is_5h=False)

    cost_data = stdin_data.get('cost')
    if cost_data is not None and 'total_cost_usd' in cost_data:
        session_cost_str = f'{YELLOW}${cost_data["total_cost_usd"]:.2f}{R}'
    else:
        session_cost_str = f'{DIM}$--{R}'

    weekly_cost_str = f'{YELLOW}${get_weekly_cost():.2f}{R}'

    ctx_pct = (stdin_data.get('context_window') or {}).get('used_percentage')
    ctx_color = pct_color(ctx_pct)
    ctx_str = (f'{MAGENTA}ctx{R} {ctx_color}{ctx_pct:.0f}%{R}'
               if ctx_pct is not None else f'{MAGENTA}ctx{R} {DIM}--%{R}')

    sep = f' {DIM}|{R} '
    term_width = _get_term_width()
    segments = [
        model_str,
        f'{GREEN}Session{R} {session_str}',
        f'{BLUE}Weekly{R} {weekly_str}',
        ctx_str,
        f'{GREEN}Session{R} {session_cost_str}',
        f'{BLUE}Weekly{R} {weekly_cost_str}',
    ]
    sys.stdout.write(wrap_segments(segments, sep, term_width))
    sys.stdout.flush()

if __name__ == '__main__':
    main()
