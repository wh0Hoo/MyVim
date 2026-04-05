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
