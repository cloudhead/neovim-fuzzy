"
" neovim-fuzzy
"
" Author:       Alexis Sellier <http://cloudhead.io>
" Version:      0.1
"
if exists("g:loaded_fuzzy") || &cp || !has('nvim')
  finish
endif
let g:loaded_fuzzy = 1

if !exists("g:fuzzy_find_command")
  let g:fuzzy_find_command =
    \ "ag --silent --nocolor -g '' -Q --path-to-agignore %s"
endif

let s:fuzzy_find_command_name = split(g:fuzzy_find_command)[0]
let s:fuzzy_job_id = 0
let s:fuzzy_prev_window = -1
let s:fuzzy_prev_window_height = -1
let s:fuzzy_bufnr = -1

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

  if !executable('fzy')
    echoerr "Fuzzy: the executable 'fzy' was not found in your path"
    return
  endif

  if !executable(s:fuzzy_find_command_name)
    echoerr "Fuzzy: the executable '" .
          \ s:fuzzy_find_command_name . "' was found in your path"
    return
  endif

  if ! exists("g:fuzzy_opencmd")
    let g:fuzzy_opencmd = 'edit'
  endif

  " Clear the command line.
  echo

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
  let files = systemlist(printf(g:fuzzy_find_command, ignores))

  " Put it all together.
  let result = bufs + files

  call writefile(result, inputs)

  let command = "fzy -l " . lines . " > " . outputs . " < " . inputs
  let opts = { 'outputs': outputs }

  function! opts.on_exit(id, code) abort
    " NOTE: The order of these operations is important: Doing the delete first
    " would leave an empty buffer in netrw. Doing the resize first would break
    " the height of other splits below it.
    call win_gotoid(s:fuzzy_prev_window)
    exe 'silent' 'bdelete!' s:fuzzy_bufnr
    exe 'resize' s:fuzzy_prev_window_height

    if a:code != 0 || !filereadable(self.outputs)
      return
    endif

    let result = readfile(self.outputs)
    if !empty(result)
      silent execute g:fuzzy_opencmd fnameescape(join(result))
    endif
  endfunction

  let s:fuzzy_prev_window = win_getid()
  let s:fuzzy_prev_window_height = winheight('%')

  if bufnr(s:fuzzy_bufnr) > 0
    exe 'keepalt' 'below' lines . 'sp' bufname(s:fuzzy_bufnr)
  else
    exe 'keepalt' 'below' lines . 'new'
    let s:fuzzy_job_id = termopen(command, opts)
    let b:fuzzy_status = 'FuzzyOpen (found ' . len(result) . ' files)'
    setlocal statusline=%{b:fuzzy_status}
  endif
  let s:fuzzy_bufnr = bufnr('%')
  set filetype=fuzzy
  startinsert
endfunction

