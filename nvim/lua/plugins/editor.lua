return {
  {
    "nvim-tree/nvim-tree.lua",
    config = function()
      require("nvim-tree").setup()
      vim.keymap.set("n", "<leader>n", "<cmd>NvimTreeToggle<cr>", { desc = "파일 트리 토글" })
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
      local builtin = require("telescope.builtin")
      vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "파일명 검색" })
      vim.keymap.set("n", "<leader>fg", builtin.live_grep,  { desc = "내용 전체 검색" })
      vim.keymap.set("n", "<leader>fb", builtin.buffers,    { desc = "버퍼 목록" })
    end,
  },
}
