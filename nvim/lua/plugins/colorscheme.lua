return {
  { "folke/tokyonight.nvim", priority = 1000, config = function()
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          -- 투명 배경
          vim.api.nvim_set_hl(0, "Normal",      { bg = "none" })
          vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
          vim.api.nvim_set_hl(0, "SignColumn",  { bg = "none" })
          vim.api.nvim_set_hl(0, "Search",      { bg = "#ffff00", fg = "#000000" })
          vim.api.nvim_set_hl(0, "IncSearch",   { bg = "#ff8800", fg = "#000000" })
          -- diff
          vim.api.nvim_set_hl(0, "DiffAdd",     { bg = "DarkBlue" })
          vim.api.nvim_set_hl(0, "DiffDelete",  { fg = "Blue", bg = "DarkCyan", bold = true })
          vim.api.nvim_set_hl(0, "DiffChange",  { bg = "DarkMagenta" })
          vim.api.nvim_set_hl(0, "DiffText",    { bg = "Red", bold = true })
          vim.api.nvim_set_hl(0, "diffAdded",   { fg = "LimeGreen", bg = "NONE" })
          vim.api.nvim_set_hl(0, "diffRemoved", { fg = "Red", bg = "NONE" })
          vim.api.nvim_set_hl(0, "diffChanged", { fg = "DodgerBlue", bg = "NONE" })
          vim.api.nvim_set_hl(0, "diffFile",      { fg = "#60ff60" })
          vim.api.nvim_set_hl(0, "diffIndexLine", { fg = "#86e1fc" })
          vim.api.nvim_set_hl(0, "diffOldFile",   { fg = "#60ff60" })
          vim.api.nvim_set_hl(0, "diffNewFile",   { fg = "#60ff60" })
          vim.api.nvim_set_hl(0, "diffLine",      { fg = "#ffff60", bold = true })
          vim.api.nvim_set_hl(0, "diffComment", { fg = "#80a0ff" })
        end,
      })
      vim.cmd("colorscheme tokyonight")
  end },
}
