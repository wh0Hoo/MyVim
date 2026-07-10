-------------------------------------------------------------------------------
-- spinner.lua
--
-- 비동기 작업 중 "작업 중" 표시 (스피너 + 경과 시간 + 선택적 진행 카운트).
-- cmdline 한 줄을 100ms 주기로 갱신하며, 메시지 히스토리에는 남기지 않는다.
--
--   local s = require("spinner").new("[ccgen]", "파일 스캔 중...")
--   s:count(1200, 101383)   -- "... 1200/101383" 형태로 갱신
--   s:set("include 분석")   -- 라벨 변경 (카운트 초기화)
--   s:stop()                -- 완료 시 반드시 호출
--
-- ※ 동기로 블로킹되는 구간에서는 스피너가 잠시 멈춘다 (타이머가 못 돌기 때문).
-------------------------------------------------------------------------------

local M = {}

local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local Spinner = {}
Spinner.__index = Spinner

function M.new(prefix, label)
  local self = setmetatable({
    prefix = prefix,
    label  = label,
    n = nil, total = nil,
    idx = 1,
    start = vim.uv.hrtime(),
    timer = vim.uv.new_timer(),
  }, Spinner)
  self.timer:start(0, 100, vim.schedule_wrap(function() self:_render() end))
  return self
end

function Spinner:_render()
  if not self.timer then return end
  local elapsed = (vim.uv.hrtime() - self.start) / 1e9
  local body = self.label
  if self.n then body = string.format("%s %d/%d", self.label, self.n, self.total) end
  vim.api.nvim_echo(
    { { string.format("%s %s %s (%.1fs)", self.prefix, FRAMES[self.idx], body, elapsed) } },
    false, {}
  )
  -- 바쁜 루프 중에는 idle redraw 가 오지 않아 echo 가 화면에 반영되지 않으므로 강제
  vim.cmd("redraw")
  self.idx = self.idx % #FRAMES + 1
end

-- 수동 갱신: 바쁜 동기 루프(예: ccgen coroutine)에서는 별도 타이머가 굶으므로
-- 작업 쪽에서 직접 호출한다. 과도한 echo 를 막기 위해 80ms 로 throttle 한다.
function Spinner:tick()
  local now = vim.uv.hrtime()
  if not self._last or (now - self._last) / 1e6 >= 80 then
    self._last = now
    self:_render()
  end
end

function Spinner:set(label)
  self.label = label
  self.n, self.total = nil, nil
end

function Spinner:count(n, total)
  self.n, self.total = n, total
end

function Spinner:stop()
  if self.timer and not self.timer:is_closing() then
    self.timer:stop()
    self.timer:close()
  end
  self.timer = nil
end

return M
