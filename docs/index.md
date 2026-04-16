주로 Vim 을 사용했었는데   
AI 가 대세가 되면서 AI 를 편집기에 연동시켜서 사용하기 위해서 NeoVim 으로 이전하였다

이 프로젝트에는 여전히 Vim 설정들이 존재한다   
이는 내가 사용하던 설정들이다

nvim 폴더의 설정들은 아래 설명하는 내 방식의 NeoVim 을 사용하는 설정이다   
이는 Vim 에서 넘어오는 분들이 사용하기 편한 방식일거라고 생각한다

---

## 📌 Info

<div class="commit-card">
  <div class="commit-row">
    <span class="label">🕒 Last updated</span>
    <span class="value">{{ site.data.commit.date }}</span>
  </div>

  <div class="commit-row">
    <span class="label">🔗 Commit</span>
    <span class="value">
      <a href="{{ site.github.repository_url }}/commit/{{ site.data.commit.hash }}">
        {{ site.data.commit.short }}
      </a>
    </span>
  </div>

  <div class="commit-row">
    <span class="label">📝 Message</span>
    <span class="value">{{ site.data.commit.message }}</span>
  </div>

  <div class="commit-row">
    <span class="label">👤 Author</span>
    <span class="value">{{ site.data.commit.author }}</span>
  </div>
</div>

---

## ⚡ Quick Start for MyVim

```bash
git clone https://github.com/wh0Hoo/MyVim
cd MyVim
# 기존 내용을 모두 제거하면서 복사한다
rsync -av --delete ./nvim/ ~/.config/nvim/
```

### 사전 설치 요구사항

**필수**

| 항목 | 용도 | 설치 예 (Ubuntu/Debian) |
|------|------|------------------------|
| `nvim >= 0.11` | `vim.lsp.config` API가 0.11부터 지원 | `snap install nvim --classic` |
| `git` | lazy.nvim 자동 설치에 필요 | `apt install git` |
| `gcc` 또는 `clang` | nvim-treesitter 파서 빌드 | `apt install gcc` |
| `node.js` | Mason이 `pyright`, `vtsls` 설치 시 필요 | `apt install nodejs` |
| `ripgrep` | Telescope `live_grep` 동작 조건 | `apt install ripgrep` |

**기능별 선택**

| 항목 | 용도 | 설치 예 |
|------|------|---------|
| `gtags` / `global` | `<Space>ga` 등 gtags 키맵 | `apt install global` |
| `claude` CLI | `claude-code.nvim` 플러그인 동작 조건 | Anthropic 공식 설치 방법 따름 |

**자동으로 설치되는 것들 (수동 불필요)**

- **lazy.nvim** — `init.lua`에서 없으면 git clone 자동 실행
- **모든 플러그인** — lazy.nvim이 처음 실행 시 자동 설치
- **LSP 서버** (`lua_ls`, `pyright`, `vtsls`, `clangd`, `rust_analyzer`) — `automatic_installation = true` 설정으로 자동
- **Treesitter 파서** — `auto_install = true` 설정으로 파일 열 때 자동

**버전 확인**

`vim.lsp.config()` / `vim.lsp.enable()` API는 Neovim 0.11부터 지원된다. 0.10 이하이면 LSP가 동작하지 않는다.

```bash
nvim --version  # NVIM v0.11.x 이상인지 확인
```

---

{% include_relative manual.md %}
