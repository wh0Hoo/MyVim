set nocompatible	" Use Vim defaults (much better!)
set bs=2		" allow backspacing over everything in insert mode
set autoindent		" always set autoindenting on
"set backup		" keep a backup file
set viminfo='20,\"50	" read/write a .viminfo file, don't store more
			" than 50 lines of registers
set history=50		" keep 50 lines of command line history
set ruler		" show the cursor position all the time(화면 우측 하단에 현재 커서의 위치(줄,칸)를 보여준다.)
set smarttab
set tabstop=4		" 탭간격
set shiftwidth=4	" 들여쓰기 간격
set number
"set ls=2		"항상 status 라인을 표시하도록 함.
filetype indent plugin on	"파일 종류를 자동으로 인식
"set nocindent
set cindent		"C 프로그래밍용 자동 들여쓰기
set smartindent		"스마트한 들여쓰기
"set expandtab		" 탭대신 스페이스
"set foldcolumn=3
"set paste		"붙이기일 때 계단현상 제거 - indent 와 충돌
set pt=<Ins>		"Insert 키로 paste 상태와 nopaste 상태를 전환한다.
"set fencs=ucs-bom,utf-8,cp949
"set incsearch		"키워드 입력시 점진적 검색
"set ignorecase		"검색시 대소문자 무시, set ic 도 가능

autocmd BufRead *.c,*.cpp,*.h loadview
autocmd BufWrite *.c,*.cpp,*.h mkview

" Only do this part when compiled with support for autocommands
if has("autocmd")
  " In text files, always limit the width of text to 78 characters
  autocmd BufRead *.txt set tw=78
  " When editing a file, always jump to the last cursor position
  autocmd BufReadPost *
  \ if line("'\"") > 0 && line ("'\"") <= line("$") |
  \   exe "normal g'\"" |
  \ endif
endif

" Don't use Ex mode, use Q for formatting
map Q gq

" Switch syntax highlighting on, when the terminal has colors
" Also switch on highlighting the last used search pattern.
if &t_Co > 2 || has("gui_running")
  syntax on
  set hlsearch		"검색어 하이라이트
endif

if &term=="xterm"
     set t_Co=8
     set t_Sb=^[4%dm
     set t_Sf=^[3%dm
endif

" some extra commands for HTML editing
nmap ,mh wbgueyei<<ESC>ea></<ESC>pa><ESC>bba
nmap ,h1 _i<h1><ESC>A</h1><ESC>
nmap ,h2 _i<h2><ESC>A</h2><ESC>
nmap ,h3 _i<h3><ESC>A</h3><ESC>
nmap ,h4 _i<h4><ESC>A</h4><ESC>
nmap ,h5 _i<h5><ESC>A</h5><ESC>
nmap ,h6 _i<h6><ESC>A</h6><ESC>
nmap ,hb wbi<b><ESC>ea</b><ESC>bb
nmap ,he wbi<em><ESC>ea</em><ESC>bb
nmap ,hi wbi<i><ESC>ea</i><ESC>bb
nmap ,hu wbi<u><ESC>ea</i><ESC>bb
nmap ,hs wbi<strong><ESC>ea</strong><ESC>bb
nmap ,ht wbi<tt><ESC>ea</tt><ESC>bb
nmap ,hx wbF<df>f<df>

" CTRL-X and SHIFT-Del are Cut
vnoremap <C-X> "*x

" CTRL-C and CTRL-Insert are Copy
vnoremap <C-C> "*y
vnoremap <C-V> "*p

map <C-V> "*p
nmap <C-V> "*p
inoremap <C-V> "*p

"exe 'inoremap <script> <C-V>' paste#paste_cmd['i']
"exe 'vnoremap <script> <C-V>' paste#paste_cmd['v']
nmap <C-C> :normal I/* <Esc>A */<Esc>

" clear pattern search
"nnoremap <silent> <Esc><Esc> :let @/=""<CR>
nnoremap <silent> <Esc><Esc> :noh<CR> " turn off highlighting until next search
