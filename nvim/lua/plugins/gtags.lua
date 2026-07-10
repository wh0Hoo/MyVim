-- GNU Global(gtags) 기반 전체 트리 심볼 탐색
--
-- clangd 와 역할 분담:
--   <C-]>        정의로 점프: 붙어 있는 백엔드만 사용 (clangd 우선 → gtags 폴백)
--                clangd/gtags 중 있는 것만 시도하므로 없는 쪽 에러 노이즈가 없고,
--                둘 다 못 찾을 때만 "정의 없음" 을 알린다
--   gd           clangd 정의 (LSP 전용)
--   <C-\>*       gtags 검색 (전체 트리, 대형 코드베이스에 강함)
--
-- DB 빌드:  <C-\>b  (= :GtagsBuild)
--   실제 소스 파일 목록만 gtags 에 넘긴다 (git ls-files → 없으면 find).
--   트리 전체를 훑지 않으므로 dev/core(→/proc/kcore) 같은 특수 파일,
--   바이너리, 빌드 산출물이 인덱싱 대상에서 원천 제외된다.
-- 증분 갱신: 저장(BufWritePost)·nvim-tree 파일 조작 시 해당 파일만 자동 반영
--   (gtags --single-update). GTAGS 가 있는 프로젝트에서만 동작.
-- 사전 조건: GNU Global(gtags, gtags-cscope) 설치
--
-- 키맵 (<prefix> = <C-\>, 기존 .vim/plugin/cscope_maps.vim 스타일):
--   s 참조  g 정의  c 호출자  t 텍스트  e egrep
--   f 파일 열기  i 이 파일을 include 하는 파일  a 대입 위치  b DB 빌드
--   ※ d(피호출자)는 gtags-cscope 미지원

local SRC_EXT = "c,cpp,cc,cxx,h,hpp,hxx"  -- gtags 로 인덱싱할 확장자

local function notify(msg, level)
  vim.notify("[gtags] " .. msg, level or vim.log.levels.INFO)
end

-- gtags 실행 루트: ccgen 과 동일 규칙 — 활성 clangd root 우선, 없으면 cwd + 안내
local function project_root()
  for _, c in pairs(vim.lsp.get_clients({ name = "clangd" })) do
    if c.config.root_dir then return c.config.root_dir end
  end
  local cwd = vim.uv.cwd()
  notify("활성 clangd 가 없어 cwd 를 사용합니다: " .. cwd)
  return cwd
end

-- root 하위 소스 파일 목록(상대경로) 을 stdin 문자열로 → on_done(list_str) 또는 on_done(nil)
-- on_done 은 항상 정상 이벤트 컨텍스트에서 호출된다 (vim.system 콜백은 fast context)
local function collect_sources(root, on_done)
  local exts = vim.split(SRC_EXT, ",", { plain = true })
  local ext_set = {}
  for _, e in ipairs(exts) do ext_set["." .. e] = true end
  local done = vim.schedule_wrap(on_done)

  -- git 우선 (submodule 내부 추적 파일 포함, 미추적 포함, .gitignore 존중)
  -- --recurse-submodules 는 --others 와 조합 불가라 추적/미추적을 두 번 호출해 합친다
  vim.system(
    { "git", "-C", root, "ls-files", "--cached", "--recurse-submodules" },
    { text = true },
    function(res)
      if res.code == 0 then
        return vim.system(
          { "git", "-C", root, "ls-files", "--others", "--exclude-standard" },
          { text = true },
          function(res2)
            local list = {}
            local function add(out)
              for rel in vim.gsplit(out or "", "\n", { plain = true }) do
                local ext = rel:match("(%.[^%./]+)$")
                if rel ~= "" and ext and ext_set[ext] then table.insert(list, rel) end
              end
            end
            add(res.stdout)
            if res2.code == 0 then add(res2.stdout) end
            done(table.concat(list, "\n"))
          end
        )
      end
      -- 비-git: find -type f (심볼릭 링크/device 파일 제외)
      local args = { root, "-type", "f", "(" }
      for i, e in ipairs(exts) do
        if i > 1 then table.insert(args, "-o") end
        table.insert(args, "-name"); table.insert(args, "*." .. e)
      end
      table.insert(args, ")")
      vim.system(vim.list_extend({ "find" }, args), { text = true }, function(fres)
        if fres.code ~= 0 then return done(nil) end
        done(fres.stdout or "")
      end)
    end
  )
end

local function remove_partial(root)
  for _, f in ipairs({ "GTAGS", "GRTAGS", "GPATH" }) do
    vim.uv.fs_unlink(root .. "/" .. f)
  end
end

-- 현재 버퍼 위/상위 디렉토리에 GTAGS 가 있는지
local function has_gtags()
  local dir = vim.fn.expand("%:p:h")
  if dir == "" then dir = vim.uv.cwd() end
  return #vim.fs.find("GTAGS", { upward = true, path = dir, type = "file" }) > 0
end

-- <C-t> 로 돌아올 수 있게 현재 위치를 태그스택에 push
local function push_tagstack(word)
  local from = { vim.fn.bufnr("%"), vim.fn.line("."), vim.fn.col("."), 0 }
  vim.fn.settagstack(vim.fn.win_getid(), { items = { { tagname = word, from = from } } }, "t")
end

-- LSP Location/LocationLink → (파일, 줄)
local function loc_file_line(loc)
  local uri = loc.uri or loc.targetUri
  local rng = loc.range or loc.targetRange
  if not uri or not rng then return nil end
  return vim.uri_to_fname(uri), rng.start.line + 1
end

-- <C-]>: 붙어 있는 백엔드만 골라 정의로 점프 (clangd 우선 → gtags 폴백)
local function smart_tag()
  local word = vim.fn.expand("<cword>")
  if word == "" then return end
  local curfile = vim.api.nvim_buf_get_name(0)
  local curline = vim.fn.line(".")

  -- 1) clangd 정의 (동기). 유효한 '다른' 위치를 주면 사용.
  --    인덱스가 불완전한 clangd 는 정의를 못 찾으면 현재 위치를 되돌려주는데,
  --    그건 무의미하므로 무시하고 gtags 로 넘어간다.
  local clients = vim.lsp.get_clients({ bufnr = 0, method = "textDocument/definition" })
  if #clients > 0 then
    local enc = clients[1].offset_encoding or "utf-16"
    local params = vim.lsp.util.make_position_params(0, enc)
    local resp = vim.lsp.buf_request_sync(0, "textDocument/definition", params, 3000) or {}
    for _, r in pairs(resp) do
      local result = r.result
      local loc = result and (result[1] or (result.uri and result))
      if loc then
        local file, line = loc_file_line(loc)
        if file and not (file == curfile and line == curline) then
          push_tagstack(word)
          vim.cmd("normal! m'")
          vim.lsp.util.show_document(loc, enc, { focus = true })
          return
        end
      end
    end
  end

  -- 2) gtags 폴백 (cscope_maps 가 tagstack push 및 점프 처리)
  if has_gtags() then
    vim.cmd("Cscope find g " .. word)  -- 단일 결과 점프, 없으면 "no results"
  else
    vim.notify("[jump] clangd 정의 없음 & GTAGS 없음 — :GtagsBuild 로 DB 생성", vim.log.levels.WARN)
  end
end

local building = false

local function build()
  if building then return notify("이미 빌드 중입니다", vim.log.levels.WARN) end
  if vim.fn.executable("gtags") ~= 1 then
    return notify("gtags 가 설치되어 있지 않습니다", vim.log.levels.ERROR)
  end
  building = true
  local root = project_root()
  local spin = require("spinner").new("[gtags]", "소스 목록 수집 중...")
  collect_sources(root, function(list)
    if not list or list == "" then
      spin:stop()
      building = false
      return notify("소스 파일을 찾지 못했습니다: " .. root, vim.log.levels.WARN)
    end
    spin:set("gtags 인덱싱 중...")
    -- gtags -f - : stdin 의 파일 목록만 인덱싱 (트리 traversal 안 함)
    vim.system(
      { "gtags", "-f", "-" },
      { cwd = root, stdin = list, text = true },
      vim.schedule_wrap(function(res)
        spin:stop()
        building = false
        if res.code == 0 then
          notify("완료: " .. root .. "/GTAGS")
        else
          remove_partial(root)  -- 0바이트 손상 파일이 다음 빌드를 막지 않도록
          notify("빌드 실패: " .. (res.stderr or ""), vim.log.levels.ERROR)
        end
      end)
    )
  end)
end

-- 증분 갱신: nvim 안의 파일 변경(저장·생성·삭제·이름변경)을 한 파일 단위로 DB 에 반영.
-- gtags --single-update 는 수정·신규·삭제를 모두 처리한다.
-- 에디터 밖 변경(git pull 등)은 :GtagsBuild 전체 재빌드 담당.
local upd_ext = {}
for _, e in ipairs(vim.split(SRC_EXT, ",", { plain = true })) do upd_ext["." .. e] = true end

local updating = false
local pending = {}  -- path → true (갱신 중 들어온 요청은 병합 후 순차 처리)

local function run_single_update(path)
  local found = vim.fs.find("GTAGS", { upward = true, path = vim.fs.dirname(path), type = "file" })
  if #found == 0 then return end  -- DB 없는 프로젝트: 아무것도 하지 않음
  local root = vim.fs.dirname(found[1])
  updating = true
  vim.system(
    { "gtags", "--single-update", path:sub(#root + 2) },
    { cwd = root },
    vim.schedule_wrap(function()
      updating = false  -- 실패해도 조용히 무시 (다음 전체 재빌드에서 해소)
      local queued = next(pending)
      if queued then
        pending[queued] = nil
        run_single_update(queued)
      end
    end)
  )
end

local function single_update(path)
  if building then return end
  if not path or path == "" or vim.fn.executable("gtags") ~= 1 then return end
  path = vim.fs.normalize(path)
  local ext = path:match("(%.[^%./]+)$")
  if not ext or not upd_ext[ext] then return end
  if updating then
    pending[path] = true
    return
  end
  run_single_update(path)
end

return {
  {
    "dhananjaylatkar/cscope_maps.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
    config = function()
      require("cscope_maps").setup({
        prefix = "<C-\\>",
        skip_input_prompt = true,  -- 프롬프트 없이 커서 밑 단어(<cword>/<cfile>)로 즉시 검색
        cscope = {
          exec = "gtags-cscope",
          picker = "telescope",  -- 팝업 리스트, 선택·점프 후 자동으로 닫힘 (split 안 남음)
          skip_picker_for_single_result = true,  -- 결과 1건이면 picker 없이 바로 점프
          project_rooter = { enable = true },     -- 상위 디렉토리에서 GTAGS 탐색
          tag = { keymap = false },  -- <C-]> 는 아래 smart_tag 로 직접 바인딩
        },
      })

      -- DB 빌드를 파일 목록 기반으로 교체 (플러그인 기본 gtags-cscope -bqkv 는
      -- 트리 전체를 훑다 특수 파일에서 실패하므로 <C-\>b 를 :GtagsBuild 로 덮어씀)
      vim.api.nvim_create_user_command("GtagsBuild", build, { desc = "소스 목록 기반 gtags DB 빌드" })
      vim.keymap.set({ "n", "v" }, "<C-\\>b", "<cmd>GtagsBuild<cr>", { desc = "Build gtags database" })

      -- <C-]>: clangd/gtags 중 있는 것만 사용 (없는 백엔드 에러 노이즈 방지)
      vim.keymap.set("n", "<C-]>", smart_tag, { desc = "정의로 점프 (clangd → gtags)" })

      -- 증분 갱신 트리거 (GTAGS 가 있는 프로젝트에서만 동작)
      vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = { "*.c", "*.cpp", "*.cc", "*.cxx", "*.h", "*.hpp", "*.hxx" },
        callback = function(args)
          single_update(vim.api.nvim_buf_get_name(args.buf))
        end,
        desc = "gtags 증분 갱신 (저장)",
      })
      local ok, nt = pcall(require, "nvim-tree.api")
      if ok then
        local E = nt.events.Event
        nt.events.subscribe(E.FileCreated, function(d) single_update(d.fname) end)
        nt.events.subscribe(E.FileRemoved, function(d) single_update(d.fname) end)
        nt.events.subscribe(E.NodeRenamed, function(d)
          single_update(d.old_name)  -- 옛 경로 제거
          single_update(d.new_name)  -- 새 경로 등록
        end)
      end
    end,
  },
}
