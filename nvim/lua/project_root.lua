-- 프로젝트 루트 결정 (gtags·ccgen 공용)
--
-- 현재 파일 위치에서 마커를 위로 탐색해 첫 히트 디렉토리를 반환한다. 없으면 cwd.
-- 마커 우선순위: .projectroot → .git(디렉토리만) → .hg → .svn
--   .git 은 디렉토리일 때만 인정 → submodule 의 .git(gitlink 파일)은 건너뛰어
--   슈퍼프로젝트 루트를 잡는다.
local M = {}

local function has_marker(dir)
  if vim.uv.fs_stat(dir .. "/.projectroot") then return true end
  local git = vim.uv.fs_stat(dir .. "/.git")
  if git and git.type == "directory" then return true end
  if vim.uv.fs_stat(dir .. "/.hg") then return true end
  if vim.uv.fs_stat(dir .. "/.svn") then return true end
  return false
end

-- path(파일 또는 디렉토리) 위치에서 위로 마커 탐색. 못 찾으면 cwd.
function M.find(path)
  local dir
  if path and path ~= "" then
    dir = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
  else
    dir = vim.uv.cwd()
  end
  local cur = vim.fs.normalize(dir)
  while true do
    if has_marker(cur) then return cur end
    local parent = vim.fs.dirname(cur)
    if parent == cur then break end  -- 파일시스템 루트 도달
    cur = parent
  end
  return vim.fs.normalize(vim.uv.cwd())
end

return M
