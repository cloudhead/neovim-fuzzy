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

let g:fuzzy_find_command = "ag --silent -g ''"
let s:fuzzy_job_id = 0
let s:fuzzy_prev_window = -1
let s:fuzzy_prev_window_height = -1

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
  let ignores = tempname()

  if ! exists("g:fuzzy_opencmd")
    let g:fuzzy_opencmd = 'edit'
  endif

  " Get open buffers.
  let bufs = filter(range(1, bufnr('$')),
    \ 'buflisted(v:val) && bufnr("%") != v:val && bufnr("#") != v:val')
  let bufs = map(bufs, 'bufname(v:val)')
  call reverse(bufs)

  " Add the '#' buffer at the head of the list.
  if bufnr('#') > 0 && bufnr('%') != bufnr('#')
    call insert(bufs, bufname('#'))
  endif

  " Save a list of files the find command should ignore.
  let ignorelist = !empty(bufname('%')) ? bufs + [bufname('%')] : bufs
  call writefile(ignorelist, ignores, 'w')

  " Get all files, minus the open buffers.
  let files = systemlist(g:fuzzy_find_command . ' -Q --path-to-agignore ' . ignores)

  " Put it all together.
  let result = bufs + files

  call writefile(result, inputs)

  let command = "fzy -l " . lines . " > " . outputs . " < " . inputs
  let opts = { 'outputs': outputs }

  function! opts.on_exit(id, code) abort
    bdelete!
    call win_gotoid(s:fuzzy_prev_window)
    exe 'resize' s:fuzzy_prev_window_height

    if a:code != 0 || !filereadable(self.outputs)
      return
    endif

    let result = readfile(self.outputs)
    if !empty(result)
      execute g:fuzzy_opencmd fnameescape(join(result))
    endif
  endfunction

  let s:fuzzy_prev_window = win_getid()
  let s:fuzzy_prev_window_height = winheight('%')

  if bufnr('FuzzyOpen') > 0
    exe 'keepalt' 'below' lines . 'sp' bufname('FuzzyOpen')
  else
    exe 'keepalt' 'below' lines . 'new'
    let s:fuzzy_job_id = termopen(command, opts)
    let b:fuzzy_status = 'FuzzyOpen (found ' . len(result) . ' files)'
    file FuzzyOpen
    setlocal statusline=%{b:fuzzy_status}
  endif
  set filetype=fuzzy
  startinsert
endfunction

