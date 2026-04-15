# wh0Hoo

회사 다니면서 사용했던 나의 vim 설정들이지만,,,

복귀하면서 예전에 사용했던 `.vimrc` 가 사라져서 박성욱에게 다시 받았는데 아주 예전에 쓰던 것이다   
물론 `.vim/` 에 있는 것들도 내 메일을 뒤져서 찾은 예전 것이다   
퇴사 직전에 쓰던 것은 사라졌다

NeoVim 으로 이전했다   
따라서 설정은 nvim 폴더를 ~/.config/ 에 복사해서 사용하자

---

## ⚡ Quick Start for NeoVim

```bash
git clone https://github.com/wh0Hoo/MyVim
cd MyVim
# 기존 내용을 모두 제거하면서 복사한다
rsync -av --delete ./nvim/ ~/.config/nvim/
```

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

