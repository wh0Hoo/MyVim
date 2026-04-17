local map = vim.keymap.set

vim.g.mapleader = " "  -- Space를 leader로

-- 저장 / 종료
map("n", "<leader>w", "<cmd>w<cr>")
map("n", "<leader>q", "<cmd>q<cr>")

-- 창 이동
map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")

-- 버퍼 이동
map("n", "<S-l>", "<cmd>bnext<cr>")
map("n", "<S-h>", "<cmd>bprev<cr>")

-- 들여쓰기 유지
map("v", "<", "<gv")
map("v", ">", ">gv")

-- relativenumber 토글
vim.keymap.set("n", "<leader>tr", function()
  vim.opt.relativenumber = not vim.opt.relativenumber:get()
  print("relativenumber: " .. tostring(vim.opt.relativenumber:get()))
end, { desc = "relativenumber 토글" })

-- mouse 토글
vim.keymap.set("n", "<leader>tm", function()
  if vim.opt.mouse:get().a then
    vim.opt.mouse = ""
    print("mouse: off")
  else
    vim.opt.mouse = "a"
    print("mouse: on")
  end
end, { desc = "mouse 토글" })

-- 시스템 클립보드로 복사
vim.keymap.set("v", "<C-c>", '"+y', { desc = "시스템 클립보드로 복사" })
