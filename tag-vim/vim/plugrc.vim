" jf{yi}@"    Type to apply a sorting
""   {j"qyi`@q}
" after an adding of new string do `:/\splug#begin/+1,/plug#end/-1 sort /\//`
let s:py3 = has('python3')

" This condition is goten from vim-gutentags:17
let s:guttentags_reqs = has('job') || (has('nvim') && exists('*jobwait'))

" w0rp/ale requirements
let s:ale_reqs = ( has('timers') && has('nvim-0.2.0') ) ||
  \ ( has('timers') && exists('*job_start') && exists('*ch_close_in') )


" to suppress an error on hosts w/o `git`
silent! call plug#begin()
Plug 'vim-scripts/Conque-GDB'
Plug 'Konfekt/FastFold' " solve dramatical slowdown for pymode inserts inside long fold
Plug 'Glench/Vim-Jinja2-Syntax'
Plug 'Valloric/YouCompleteMe', { 'do': 'git submodule update --init --recursive; ./install.py' }
if s:ale_reqs | Plug 'w0rp/ale' | endif
Plug 'jiangmiao/auto-pairs'
Plug 'ctrlpvim/ctrlp.vim'
Plug 'davidhalter/jedi-vim'
Plug 'nanotech/jellybeans.vim'
Plug 'scrooloose/nerdtree'
Plug 'chr4/nginx.vim'
Plug 'python-mode/python-mode', { 'branch': 'develop' }
Plug 'luochen1990/rainbow'
Plug 'saltstack/salt-vim'
Plug 'vim-syntastic/syntastic', { 'on': 'SyntasticReset' }
Plug 'godlygeek/tabular'
Plug 'majutsushi/tagbar'
Plug 'SirVer/ultisnips'
Plug 'junegunn/vader.vim'
if s:py3 | Plug 'vim-vdebug/vdebug' | endif
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'ivalkeen/vim-ctrlp-tjump'
Plug 'tpope/vim-fugitive'
Plug 'jamessan/vim-gnupg'
Plug 'fatih/vim-go', { 'for': 'go' }
if s:guttentags_reqs | Plug 'ludovicchabant/vim-gutentags' | endif
Plug 'lifepillar/vim-mucomplete', { 'on': 'MUcompleteAutoOn' }
Plug 'jistr/vim-nerdtree-tabs'
Plug 'rodjek/vim-puppet'
Plug 'Felixoid/vim-puppet-class-alignment'
Plug 'vim-ruby/vim-ruby'
Plug 'honza/vim-snippets'
Plug 'tpope/vim-surround'
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
