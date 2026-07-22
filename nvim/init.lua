-- nvim-tree 를 파일 탐색기로 쓰므로 내장 netrw 를 로드 전에 비활성화한다
-- (디렉토리를 첫 인자로 열 때 netrw 와의 경합·깜빡임 방지 — nvim-tree 공식 권장)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone",
    "--filter=blob:none",
    "--branch=stable",   -- 최신 안정 릴리스 태그 (main 최신 대신, lazy 공식 권장)
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("options")
require("keymaps")
require("ccgen")
require("lazy").setup("plugins")

vim.api.nvim_create_user_command("MyVimVersion", function()
  print("MyVim v" .. require("version"))
end, { desc = "MyVim 설정 버전 표시" })
