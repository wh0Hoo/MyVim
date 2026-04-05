local gtags_dbs = {}

-- DB 추가
vim.keymap.set("n", "<leader>ga", function()
  local db = vim.fn.input("gtags DB 폴더: ", vim.fn.getcwd() .. "/", "dir")
  if db ~= "" then
    table.insert(gtags_dbs, db)
    vim.env.GTAGSDBPATH = table.concat(gtags_dbs, ":")
    vim.env.GTAGSROOT = "/"
    print("added: " .. db)
  end
end, { desc = "gtags DB 추가" })

-- 심볼 검색
vim.keymap.set("n", "<leader>gs", function()
  local word = vim.fn.expand("<cword>")
  require("telescope.builtin").grep_string({
    search = word,
    prompt_title = "gtags: " .. word,
  })
end, { desc = "gtags 심볼 검색" })

-- 정의 검색
vim.keymap.set("n", "<leader>gg", function()
  local word = vim.fn.expand("<cword>")
  local result = vim.fn.systemlist("global -d " .. word)
  if #result == 0 then
    print("정의 없음: " .. word)
    return
  end
  require("telescope.builtin").live_grep({
    search_dirs = gtags_dbs,
    default_text = word,
    prompt_title = "gtags 정의: " .. word,
  })
end, { desc = "gtags 정의 검색" })

-- DB 목록
vim.keymap.set("n", "<leader>gl", function()
  if #gtags_dbs == 0 then
    print("추가된 DB 없음")
  else
    print(table.concat(gtags_dbs, "\n"))
  end
end, { desc = "gtags DB 목록" })

-- DB 초기화
vim.keymap.set("n", "<leader>gc", function()
  gtags_dbs = {}
  vim.env.GTAGSDBPATH = ""
  print("gtags DB 초기화됨")
end, { desc = "gtags DB 초기화" })
