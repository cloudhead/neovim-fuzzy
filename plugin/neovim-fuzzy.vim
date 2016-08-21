"
" neovim-fuzzy
"
" Author:       Alexis Sellier <http://cloudhead.io>
" Version:      0.1
"
if exists("g:loaded_fuzzy") || &cp || !executable('fzy') || !has('nvim')
  finish
endif
let g:loaded_fuzzy = 1

let g:fuzzy_find_command = "ag -g ''"
let s:fuzzy_job_id = 0

command! FuzzyOpen call s:fuzzy()
command! FuzzyKill call s:fuzzy_kill()

autocmd FileType fuzzy tnoremap <buffer> <Esc> <C-\><C-n>:FuzzyKill<CR>

function! s:fuzzy_kill()
  echo
  call jobstop(s:fuzzy_job_id)
endfunction

function! s:fuzzy() abort
  let lines = 12
  let inputs = tempname()
  let outputs = tempname()

  " Get open buffers.
  let bufs = filter(range(1, bufnr('$')),
    \ 'buflisted(v:val) && bufnr("%") != v:val && bufnr("#") != v:val')
  let bufs = map(bufs, 'bufname(v:val)')
  call reverse(bufs)

  " Add the '#' buffer at the head of the list.
  if bufnr('%') != bufnr('#')
    call insert(bufs, bufname('#'))
  endif

  " Get all files, minus the open buffers.
  let files = systemlist(g:fuzzy_find_command)
  let files = filter(files,
    \ 'index(bufs, v:val) == -1 && bufname("#") != v:val && bufname("%") != v:val')

  " Put it all together.
  let result = bufs + files

  call writefile(result, inputs)

  let command = "fzy -l " . lines . " > " . outputs . " < " . inputs
  let opts = { 'outputs': outputs }

  function! opts.on_exit(id, code) abort
    bdelete!

    if a:code != 0 || !filereadable(self.outputs)
      return
    endif

    let result = readfile(self.outputs)
    if !empty(result)
      execute 'edit' fnameescape(join(result))
    endif
  endfunction

  below new
  execute 'resize' lines + 1
  set filetype=fuzzy

  if bufnr('FuzzyOpen') > 0
    execute 'buffer' bufnr('FuzzyOpen')
  else
    call termopen(command, opts)
    let s:fuzzy_job_id = b:terminal_job_id
    file FuzzyOpen
  endif
  startinsert
endfunction

