# Changelog

MyVim 의 버전별 변경 이력. [Semantic Versioning](https://semver.org/lang/ko/) 을 따른다 —
0.x 동안은 MINOR = 기능 추가, PATCH = 버그 수정. 버전은 설정(`nvim/`, `.vim/`, `.vimrc`)의
변경에만 부여하며, 문서·Pages 만의 변경은 버전에 반영하지 않는다. 의미 있는 변경 묶음이
완결될 때 annotated tag (`v0.x.y`) 로 릴리즈하며, 릴리즈 시 `nvim/lua/version.lua` 를 함께
갱신한다. 설치된 설정의 버전은 nvim 에서 `:MyVimVersion` 으로 확인한다.

## [0.1.0] - 2026-07-10

초기 릴리즈 — NeoVim 전환 및 C/C++ 소스 분석 체계 구축.

### Added

- **C/C++ 소스 분석 2트랙 체계**
  - `ccgen`: clangd 용 `compile_commands.json` 생성기 (`:CCGen` / `:CCGenInfo`).
    파일별 최소 `-I` 추론으로 대형 트리에서도 크기 선형 유지
  - gtags: 전체 트리 심볼·참조 검색 (`Ctrl-\` + s/g/c/t/e/f/i/a, cscope_maps.nvim + gtags-cscope)
- **스마트 `Ctrl-]`**: clangd 우선 → gtags 폴백 — 있는 백엔드만 조용히 사용, `Ctrl-t` 복귀 지원
- **`:CCGen` 범위 인자**: 디렉토리 지정(복수 가능), `.` = 현재 작업 디렉토리, `%` = 현재 파일 위치
- **규모 확인 게이트**: 소스 10,000개 초과 시 생성 전 확인 (clangd 인덱싱 OOM 예방)
- **gtags 증분 갱신**: 저장·nvim-tree 파일 조작(생성/삭제/이름변경) 시 해당 파일만 자동 반영
- **git submodule 지원**: ccgen/gtags 스캔이 submodule 내부 추적 파일 포함
- **진행 표시 스피너**: `:CCGen`/`:GtagsBuild` 진행 상황·경과 시간 표시 (ccgen/gtags 공용)
- **Telescope 통합**: 다중 결과 검색 시 팝업 선택 (normal 모드 시작, 점프 후 자동 닫힘),
  `<leader>ff`/`fg`/`fb` 검색 키맵
- **`:MyVimVersion`**: 설치된 설정의 버전 표시
- **문서**: 사용법 매뉴얼(manual.md), 설치·요구사항(index.md), 저장소↔실사용 동기화 방법 안내

### Changed

- Treesitter 설정을 main 브랜치 API 로 재작성 (파서 자동 설치·하이라이팅 실동작)
- LSP 부트스트랩을 mason-lspconfig v2 자동 enable 로 전환 (새 머신 첫 실행 대응)
- 하이라이트 제거 키맵 `Esc Esc` → `Esc` (Telescope 닫기 지연 해소)
