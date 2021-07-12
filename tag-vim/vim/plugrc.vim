" jf{yi}@"    Type to apply a sorting
""   {j"qyi`@q}
" after an adding of new string do `:/\splug#begin/+1,/plug#end/-1 sort /\//`
let s:py3 = has('python3')
let s:py2 = has('python')
let s:py  = s:py2 || s:py3


" This condition is goten from vim-gutentags:17
let s:guttentags_reqs = has('job') || (has('nvim') && exists('*jobwait'))

" w0rp/ale requirements
let s:ale_reqs = ( has('timers') && has('nvim-0.2.0') ) ||
  \ ( has('timers') && exists('*job_start') && exists('*ch_close_in') )


" to suppress an error on hosts w/o `git`
silent! call plug#begin()
Plug 'vim-scripts/Conque-GDB', { 'on': ['ConqueTerm', 'ConqueTermTab'] }
Plug 'Konfekt/FastFold' " solve dramatical slowdown for pymode inserts inside long fold
Plug 'tmhedberg/SimpylFold'
Plug 'Glench/Vim-Jinja2-Syntax'
Plug 'ycm-core/YouCompleteMe', { 'do': 'git submodule update --init --recursive && GOFLAGS=-modcacherw ./install.py --clangd-completer --go-completer' }
if s:ale_reqs | Plug 'w0rp/ale' | endif
Plug 'jiangmiao/auto-pairs'
Plug 'wellle/context.vim'
Plug 'ctrlpvim/ctrlp.vim'
if s:py | Plug 'davidhalter/jedi-vim' | endif
Plug 'nanotech/jellybeans.vim'
Plug 'iamcco/markdown-preview.vim'
Plug 'scrooloose/nerdtree'
Plug 'chr4/nginx.vim'
if s:py | Plug 'python-mode/python-mode', { 'branch': 'develop' } | endif
Plug 'luochen1990/rainbow'
Plug 'saltstack/salt-vim'
Plug 'vim-syntastic/syntastic', { 'on': 'SyntasticReset' }
Plug 'godlygeek/tabular'
Plug 'majutsushi/tagbar'
if s:py3 | Plug 'SirVer/ultisnips' | endif
Plug 'junegunn/vader.vim'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'ivalkeen/vim-ctrlp-tjump'
Plug 'tpope/vim-dadbod'
Plug 'kristijanhusak/vim-dadbod-ui'
Plug 'tpope/vim-dispatch'
Plug 'tpope/vim-fugitive'
Plug 'jamessan/vim-gnupg', { 'branch': 'main' }
Plug 'fatih/vim-go', { 'for': 'go', 'do': ':GoUpdateBinaries' }
if s:guttentags_reqs | Plug 'ludovicchabant/vim-gutentags' | endif
Plug 'vim-latex/vim-latex'
Plug 'andymass/vim-matchup'
Plug 'lifepillar/vim-mucomplete', { 'on': 'MUcompleteAutoOn' }
Plug 'jistr/vim-nerdtree-tabs'
Plug 'jceb/vim-orgmode' | Plug 'tpope/vim-speeddating'
Plug 'lifepillar/vim-outlaw'
Plug 'vim-pandoc/vim-pandoc'
Plug 'vim-pandoc/vim-pandoc-syntax'
Plug 'junegunn/vim-plug'
Plug 'rodjek/vim-puppet'
Plug 'Felixoid/vim-puppet-class-alignment'
Plug 'vim-ruby/vim-ruby'
Plug 'honza/vim-snippets'
if s:py | Plug 'brianrodri/vim-sort-folds' | endif
Plug 'tpope/vim-surround'
Plug 'tpope/vim-unimpaired'
Plug 'lervag/vimtex'
call plug#end()

" Load vim-mucomplete if there's no YCM
if !isdirectory(g:plug_home . '/YouCompleteMe')
  au VimEnter * silent! MUcompleteAutoOn
  set completeopt+=menuone,menu
  if has('patch-7.4.775')
    set completeopt+=noinsert
  else
    set completeopt-=longest
  end
end

" Load syntastic if couldn't load ale
if !s:ale_reqs
  SyntasticReset
end
