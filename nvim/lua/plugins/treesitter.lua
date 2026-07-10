-- nvim-treesitter (main 브랜치, 재작성판)
--
-- main 브랜치는 구(master) API 와 다르다:
--   setup() 은 install_dir 만 받고, ensure_installed/highlight 옵션은 없다.
--   파서 설치는 install(), 하이라이팅은 파일 타입별 vim.treesitter.start() 로 켠다.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    config = function()
      local parsers = {
        "c", "cpp", "lua", "python", "javascript", "typescript", "bash", "vim", "vimdoc",
      }
      require("nvim-treesitter").install(parsers)

      -- 파서가 있는 파일 타입에서 treesitter 하이라이팅 활성화
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("TreesitterHighlight", { clear = true }),
        pattern = {
          "c", "cpp", "lua", "python", "javascript", "typescript", "sh", "bash", "vim",
        },
        callback = function()
          pcall(vim.treesitter.start)  -- 파서 미설치(설치 진행 중)면 조용히 건너뜀
        end,
      })
    end,
  },
}
