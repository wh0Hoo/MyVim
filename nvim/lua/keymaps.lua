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

-- 삭제 계열 → 블랙홀 (클립보드 영향 없음)
vim.keymap.set({ "n", "v" }, "d",  '"_d')
vim.keymap.set({ "n", "v" }, "D",  '"_D')
vim.keymap.set({ "n", "v" }, "c",  '"_c')
vim.keymap.set({ "n", "v" }, "C",  '"_C')
vim.keymap.set({ "n", "v" }, "s",  '"_s')
vim.keymap.set({ "n", "v" }, "S",  '"_S')
vim.keymap.set({ "n", "v" }, "x",  '"_x')
vim.keymap.set({ "n", "v" }, "X",  '"_X')

-- 비주얼 붙여넣기 → 클립보드 유지
vim.keymap.set("v", "p", '"_dP')
