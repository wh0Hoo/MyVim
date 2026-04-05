return {
  { "folke/tokyonight.nvim", priority = 1000, config = function()
      vim.cmd("colorscheme tokyonight")
      -- 투명 배경
      vim.api.nvim_set_hl(0, "Normal",      { bg = "none" })
      vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
      vim.api.nvim_set_hl(0, "SignColumn",  { bg = "none" })
  end },
}
