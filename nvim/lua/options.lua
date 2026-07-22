local opt = vim.opt

-- editorconfig 활성 (Neovim 기본 on). 저장소별 .editorconfig 가 아래 옵션을 덮어씀:
-- 프로젝트에 .editorconfig 가 없으면 아래 전역 기본값이 적용된다.

-- 줄 번호
opt.number = true
opt.relativenumber = false

-- 탭/들여쓰기
opt.tabstop = 8        -- tab_width = 8
opt.shiftwidth = 8     -- indent_size = tab (tabstop 따라감)
opt.expandtab = false  -- indent_style = tab
opt.fileencoding = "utf-8"  -- charset = utf-8
opt.fileformat = "unix"     -- end_of_line = lf
opt.smartindent = true

-- 검색
opt.ignorecase = false
opt.smartcase = false
opt.hlsearch = true    -- 검색 결과 하이라이트
opt.incsearch = false  -- 입력 중 실시간 검색 비활성

-- UI
opt.termguicolors = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.scrolloff = 8
opt.wrap = true
opt.linebreak = true

-- 시스템 클립보드
-- opt.clipboard = "unnamedplus"

-- 마우스 비활성화
opt.mouse = ""

-- 분할 방향
opt.splitright = true
opt.splitbelow = true
opt.equalalways = false

-- 마지막 편집 위치로 복원
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function()
    -- 매번 새로 쓰는 버퍼(커밋 메시지 등)는 커서를 맨 위에 두는 게 자연스러움
    local ft = vim.bo.filetype
    if ft == "gitcommit" or ft == "gitrebase" then return end
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(0) then
      vim.api.nvim_win_set_cursor(0, mark)
    end
  end,
})
