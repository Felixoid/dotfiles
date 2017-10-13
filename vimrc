" Plug sources
source ~/.vim/plugrc.vim

" GVIM
if has('gui_running')
  lcd %:p:h
  set guifont=Monaco\ for\ Powerline\ 11
endif

" theming
colorscheme jellybeans
set list
set listchars=tab:\|—,trail:~
set cursorline
set hlsearch
filetype plugin on
syntax on
set number
set relativenumber
set linebreak

" tabulation
set autoindent
set expandtab
set ts=4
set sw=2
set sts=2

" Airline
let g:airline_theme='base16_ashes'
set laststatus=2
let g:airline#extensions#vimagit#enabled=1
let g:airline#extensions#branch#enabled=1
let g:airline#extensions#keymap#enabled=0
" more compact position section
let g:airline_section_z="%1p%%%#__accent_bold#%{g:airline_symbols.linenr}%2l%#__restore__#%#__accent_bold#/%L%{g:airline_symbols.maxlinenr}%#__restore__#:%2v"

" Necocompete
set completeopt-=preview
let g:neocomplete#enable_at_startup = 1
let g:neocomplete#enable_auto_select = 1

" Rainbow
let g:rainbow_active = 1
let g:rainbow_operators = 1
set clipboard-=autoselect

" NERDTree
let g:NERDTreeWinSize=22
autocmd vimenter * NERDTree
" and back to last window
autocmd VimEnter * wincmd p


" function to change file encoding
function! ChangeFileencoding()
	let encodings = ['cp1251', 'koi8-r', 'cp866', 'utf8']
	let prompt_encs = []
	let index = 0
	while index < len(encodings)
		call add(prompt_encs, index.'. '.encodings[index])
		let index = index + 1
	endwhile
	let choice = inputlist(prompt_encs)
	if choice >= 0 && choice < len(encodings)
		execute 'e ++enc='.encodings[choice].' %:p'
	endif
endf
nmap <F8> :call ChangeFileencoding()<CR>

" toggles maps
nmap <F7> :set number! relativenumber!<CR>
nmap  :set expandtab!<CR>
nmap  :set paste!<CR>

set keymap=russian-jcukenwin
set iminsert=0
set imsearch=0
imap  
highlight lCursor guifg=Red guibg=Cyan ctermfg=Red ctermbg=Cyan
highlight Folded ctermbg=black
"setlocal spell spelllang=ru_yo,en_us
set nospell

" pymode
let g:pymode_rope_lookup_project = 1 " recursively search .ropeproject
let g:pymode_lint_ignore="E501" " ignore 'too long lines'
let g:pymode_lint = 1
let g:pymode_options_max_line_length = 119
au FileType python setlocal wrap

" vim-go
au FileType go set noexpandtab
au FileType go set ts=4
au FileType go set sw=4
au FileType go set sts=4
au FileType go nmap <leader>r <Plug>(go-run)
au FileType go nmap <leader>b :GoBuild!
au FileType go nmap <leader>t <Plug>(go-test)
au FileType go nmap <leader>c <Plug>(go-coverage)
au FileType go nmap <Leader>ds <Plug>(go-def-split)
au FileType go nmap <Leader>dv <Plug>(go-def-vertical)
au FileType go nmap <Leader>dt <Plug>(go-def-tab)
au FileType go nmap <Leader>gd <Plug>(go-doc)
au FileType go nmap <Leader>gv <Plug>(go-doc-vertical)
