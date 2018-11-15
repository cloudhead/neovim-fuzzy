"
" neovim-fuzzy
"
" Author:       Alexis Sellier <http://cloudhead.io>
" Version:      0.2
"
if exists("g:loaded_fuzzy") || &cp || !has('nvim')
  finish
endif
let g:loaded_fuzzy = 1

if !exists("g:fuzzy_bufferpos")
  let g:fuzzy_bufferpos = 'below'
endif

if !exists("g:fuzzy_opencmd")
  let g:fuzzy_opencmd = 'edit'
endif

if !exists("g:fuzzy_executable")
  let g:fuzzy_executable = 'fzy'
endif

if !exists("g:fuzzy_winheight")
  let g:fuzzy_winheight = 12
endif

if !exists("g:fuzzy_rootcmds")
  let g:fuzzy_rootcmds = [
  \ 'git rev-parse --show-toplevel',
  \ 'hg root'
  \ ]
endif

let s:fuzzy_job_id = 0
let s:fuzzy_prev_window = -1
let s:fuzzy_prev_window_height = -1
let s:fuzzy_bufnr = -1
let s:fuzzy_source = {}

function! s:strip(str)
  return substitute(a:str, '\n*$', '', 'g')
endfunction

function! s:fuzzy_getroot()
  for cmd in g:fuzzy_rootcmds
    let result = system(cmd)
    if v:shell_error == 0
      return s:strip(result)
    endif
  endfor
  return "."
endfunction

function! s:fuzzy_err_noexec()
  throw "Fuzzy: no search executable was found. " .
      \ "Please make sure either '" .  s:ag.path .
      \ "' or '" . s:rg.path . "' are in your path"
endfunction

" Methods to be replaced by an actual implementation.
function! s:fuzzy_source.find(...) dict
  call s:fuzzy_err_noexec()
endfunction

function! s:fuzzy_source.find_contents(...) dict
  call s:fuzzy_err_noexec()
endfunction

"
" ag (the silver searcher)
"
let s:ag = { 'path': 'ag' }

function! s:ag.find(root, ignorelist) dict
  let ignorefile = tempname()
  call writefile(a:ignorelist, ignorefile, 's')
  return systemlist(
    \ s:ag.path . " --silent --nocolor -g '' -Q --path-to-ignore " . ignorefile . ' ' . a:root)
endfunction

function! s:ag.find_contents(query) dict
  let query = empty(a:query) ? '^(?=.)' : a:query
  return systemlist(s:ag.path . " --noheading --nogroup --nocolor -S " . shellescape(query) . " .")
endfunction

"
" rg (ripgrep)
"
let s:rg = { 'path': 'rg' }

function! s:rg.find(root, ignorelist) dict
  let ignores = []
  for str in a:ignorelist
    call add(ignores, printf("-g '!%s'", str))
  endfor
  return systemlist(s:rg.path . " --color never --files --fixed-strings " . join(ignores, ' ') . ' ' . a:root . ' 2>/dev/null')
endfunction

function! s:rg.find_contents(query) dict
  let query = empty(a:query) ? '.' : shellescape(a:query)
  return systemlist(s:rg.path . " -n --no-heading --color never -S " . query . " . 2>/dev/null")
endfunction

" Set the finder based on available binaries.
if executable(s:rg.path)
  let s:fuzzy_source = s:rg
elseif executable(s:ag.path)
  let s:fuzzy_source = s:ag
endif

command! -nargs=? FuzzyGrep   call s:fuzzy_grep(<q-args>)
command! -nargs=? FuzzyOpen   call s:fuzzy_open(<q-args>)
command!          FuzzyKill   call s:fuzzy_kill()

autocmd FileType fuzzy tnoremap <buffer> <Esc> <C-\><C-n>:FuzzyKill<CR>

function! s:fuzzy_kill()
  echo
  call jobstop(s:fuzzy_job_id)
endfunction

function! s:fuzzy_grep(str) abort
  try
    let contents = s:fuzzy_source.find_contents(a:str)
  catch
    echoerr v:exception
    return
  endtry

  let opts = { 'lines': g:fuzzy_winheight, 'statusfmt': 'FuzzyGrep %s (%d results)', 'root': '.' }

  function! opts.handler(result) abort
    let parts = split(join(a:result), ':')
    let name = parts[0]
    let lnum = parts[1]
    let text = parts[2] " Not used.

    return { 'name': name, 'lnum': lnum }
  endfunction

  return s:fuzzy(contents, opts)
endfunction

function! s:fuzzy_open(root) abort
  let root = empty(a:root) ? s:fuzzy_getroot() : a:root
  exe 'lcd' root

  " Get open buffers.
  let bufs = filter(range(1, bufnr('$')),
    \ 'buflisted(v:val) && bufnr("%") != v:val && bufnr("#") != v:val && !empty(bufname(v:val))')
  let bufs = map(bufs, 'expand(bufname(v:val))')

  " Add the '#' buffer at the head of the list.
  if bufnr('#') > 0 && bufnr('%') != bufnr('#')
    let altbufname = expand(bufname('#'))
    if !empty(altbufname) && buflisted(altbufname)
      call insert(bufs, altbufname)
    end
  endif

  " Save a list of files the find command should ignore.
  let ignorelist = !empty(bufname('%')) ? bufs + [expand(bufname('%'))] : bufs

  " Get all files, minus the open buffers.
  try
    let files = s:fuzzy_source.find('', ignorelist)
  catch
    echoerr v:exception
    return
  finally
    lcd -
  endtry

  " Put it all together.
  let result = bufs + files

  let opts = { 'lines': g:fuzzy_winheight, 'statusfmt': 'FuzzyOpen %s (%d files)', 'root': root }
  function! opts.handler(result)
    return { 'name': join(a:result) }
  endfunction

  return s:fuzzy(result, opts)
endfunction

function! s:fuzzy(choices, opts) abort
  let inputs = tempname()
  let outputs = tempname()

  if !executable(g:fuzzy_executable)
    echoerr "Fuzzy: the executable '" . g:fuzzy_executable . "' was not found in your path"
    return
  endif

  " Clear the command line.
  echo

  call writefile(a:choices, inputs)

  let command = g:fuzzy_executable . " -l " . a:opts.lines . " > " . outputs . " < " . inputs
  let opts = { 'outputs': outputs, 'handler': a:opts.handler, 'root': a:opts.root }

  function! opts.on_exit(id, code, _event) abort
    " NOTE: The order of these operations is important: Doing the delete first
    " would leave an empty buffer in netrw. Doing the resize first would break
    " the height of other splits below it.
    call win_gotoid(s:fuzzy_prev_window)
    exe 'silent' 'bdelete!' s:fuzzy_bufnr
    exe 'resize' s:fuzzy_prev_window_height

    if a:code != 0 || !filereadable(self.outputs)
      return
    endif

    let results = readfile(self.outputs)
    if !empty(results)
      for result in results
        let file = self.handler([result])
        exe 'lcd' self.root
        silent execute g:fuzzy_opencmd fnameescape(expand(file.name))
        lcd -
        if has_key(file, 'lnum')
          silent execute file.lnum
          normal! zz
        endif
      endfor
    endif
  endfunction

  let s:fuzzy_prev_window = win_getid()
  let s:fuzzy_prev_window_height = winheight('%')

  if bufnr(s:fuzzy_bufnr) > 0
    exe 'keepalt' g:fuzzy_bufferpos a:opts.lines . 'sp' bufname(s:fuzzy_bufnr)
  else
    exe 'keepalt' g:fuzzy_bufferpos a:opts.lines . 'new'
    let s:fuzzy_job_id = termopen(command, opts)
    let b:fuzzy_status = printf(
      \ a:opts.statusfmt,
      \ fnamemodify(opts.root, ':~:.'),
      \ len(a:choices))
    setlocal statusline=%{b:fuzzy_status}
    set norelativenumber
    set nonumber
  endif
  let s:fuzzy_bufnr = bufnr('%')
  set filetype=fuzzy
  startinsert
endfunction

