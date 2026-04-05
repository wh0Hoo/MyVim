return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      -- 최신 nvim-treesitter API (configs 모듈 제거됨)
      vim.treesitter.language.register("lua",        "lua")
      vim.treesitter.language.register("python",     "python")
      vim.treesitter.language.register("javascript", "javascript")
      vim.treesitter.language.register("typescript", "typescript")
      vim.treesitter.language.register("bash",       "bash")
      vim.treesitter.language.register("vim",        "vim")

      require("nvim-treesitter").setup({
        ensure_installed = { "lua", "python", "javascript", "typescript", "bash", "vim" },
        auto_install = true,
        highlight = { enable = true },
      })
    end,
  },
}
