local opt = vim.opt

-- 줄 번호
opt.number = true
opt.relativenumber = true

-- 탭/들여쓰기
opt.tabstop = 8        -- tab_width = 8
opt.shiftwidth = 8     -- indent_size = tab (tabstop 따라감)
opt.expandtab = false  -- indent_style = tab
opt.fileencoding = "utf-8"  -- charset = utf-8
opt.fileformat = "unix"     -- end_of_line = lf
opt.smartindent = true

-- 검색
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = false

-- UI
opt.termguicolors = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.scrolloff = 8
opt.wrap = true
opt.linebreak = true

-- 시스템 클립보드
opt.clipboard = "unnamedplus"

-- 분할 방향
opt.splitright = true
opt.splitbelow = true
opt.equalalways = false

-- 마지막 편집 위치로 복원
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(0) then
      vim.api.nvim_win_set_cursor(0, mark)
    end
  end,
})
