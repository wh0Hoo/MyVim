return {
  {
    "greggh/claude-code.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("claude-code").setup({
        window = {
          position = "horizontal",  -- "vertical" | "horizontal" | "float"
          size = 0.4,             -- 화면의 40%
        },
      })

      vim.keymap.set("n", "<leader>ac", "<cmd>ClaudeCode<cr>",         { desc = "Claude Code 토글" })
      vim.keymap.set("n", "<leader>ar", "<cmd>ClaudeCodeResume<cr>",   { desc = "Claude Code 재개" })
      vim.keymap.set("n", "<leader>aC", "<cmd>ClaudeCodeContinue<cr>", { desc = "Claude Code 계속" })
    end,
  },
}
