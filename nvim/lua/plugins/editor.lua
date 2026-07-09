return {
  {
    "nvim-tree/nvim-tree.lua",
    config = function()
      require("nvim-tree").setup()
    end,
  },
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("telescope").setup({
        -- normal 모드로 시작 → 목록을 hjkl 로 바로 탐색 (필터는 i 또는 /)
        defaults = { initial_mode = "normal" },
      })
    end,
  },
}
