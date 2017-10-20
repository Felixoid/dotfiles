if exists(':AddTabularPattern')
  au FileType puppet AddTabularPattern class /$\S*/
  au FileType puppet inoremap <buffer> <silent> , ,<Esc>:Tabularize class<CR>a
endif
