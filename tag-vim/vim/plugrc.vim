let s:py3 = has('python3')
" This condition is goten from vim-gutentags:17
let s:job_api = has('job') || (has('nvim') && exists('*jobwait'))


" to suppress an error on hosts w/o `git`
" after an adding of new string do `:/plug#begin/+1,/plug#end/-1 sort /\//`
"   ("qyi`@q)
silent! call plug#begin()
Plug 'vim-scripts/Arduino-syntax-file'
Plug 'vim-scripts/Conque-GDB'
Plug 'Konfekt/FastFold' " solve dramatical slowdown for pymode inserts inside long fold
Plug 'Glench/Vim-Jinja2-Syntax'
Plug 'Valloric/YouCompleteMe', { 'do': 'git submodule update --init --recursive; ./install.py' }
Plug 'ctrlpvim/ctrlp.vim'
Plug 'Raimondi/delimitMate'
Plug 'davidhalter/jedi-vim'
Plug 'nanotech/jellybeans.vim'
Plug 'coddingtonbear/neomake-platformio'
Plug 'scrooloose/nerdtree'
Plug 'chr4/nginx.vim'
Plug 'python-mode/python-mode', { 'branch': 'master' }
Plug 'luochen1990/rainbow'
Plug 'saltstack/salt-vim'
Plug 'vim-syntastic/syntastic'
Plug 'godlygeek/tabular'
Plug 'majutsushi/tagbar'
Plug 'junegunn/vader.vim'
if s:py3 | Plug 'vim-vdebug/vdebug' | endif
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'ivalkeen/vim-ctrlp-tjump'
Plug 'tpope/vim-fugitive'
Plug 'jamessan/vim-gnupg'
Plug 'fatih/vim-go', { 'for': 'go' }
if s:job_api | Plug 'ludovicchabant/vim-gutentags' | endif
Plug 'jistr/vim-nerdtree-tabs'
Plug 'Felixoid/vim-puppet'
Plug 'vim-ruby/vim-ruby'
Plug 'tpope/vim-surround'
Plug 'lervag/vimtex'
Plug 'mattn/webapi-vim'
call plug#end()
