if exists(':AddTabularPattern')
  au FileType puppet AddTabularPattern! class /$\S*/
  au FileType puppet inoremap <buffer> <silent> ,<CR> ,<Esc>:Tabularize class<CR>o
endif
