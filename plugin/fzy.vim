" vim: foldmethod=marker foldlevel=0 foldcolumn=3

" fzy.vim
"
" Authors:      Alexis Sellier <http://cloudhead.io>
"               nannery <https://github.com/nannery>
"               Romain Bossart <https://github.com/bosr>
" Version:      0.3
"

" global options{{{1

if !exists("g:fuzzy_bindkeys")
  let g:fuzzy_bindkeys = 0
endif

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

let g:fuzzy_splitcmd_map = {
  \ 'current' : 'edit',
  \ 'vsplit'  : 'vsplit',
  \ 'split'   : 'split',
  \ 'tab'     : 'tabe'
  \ }

let g:fuzzy_view_list = ['buffers', 'files']

let s:fuzzy_job_id = 0
let s:fuzzy_prev_window = -1
let s:fuzzy_prev_window_height = -1
let s:fuzzy_bufnr = -1
let s:fuzzy_source = {}
let s:fuzzy_selected_opencmd = ''
let g:fuzzy_view_current = 0  " index in g:fuzzy_view_list

" select contentsearch engine
let s:rg = {'path': 'rg'}
let s:ag = {'path': 'ag'}

if !exists("g:fuzzy_contentsearch_engine")
  " Set the finder based on available binaries.
  if executable(s:rg.path)
    let s:fuzzy_source = s:rg
  elseif executable(s:ag.path)
    let s:fuzzy_source = s:ag
  endif
else
  " user-provided engine
  if g:fuzzy_contentsearch_engine ==? 'rg'
    let s:fuzzy_source = s:rg
  elseif g:fuzzy_contentsearch_engine ==? 'ag'
    let s:fuzzy_source = s:ag
  endif
endif

if g:fuzzy_bindkeys
  augroup _fzy
    autocmd!
    autocmd FileType fuzzy tnoremap <silent> <buffer> <Esc> <C-\><C-n>:FuzzyKill<CR>
    " autocmd FileType fuzzy tnoremap <silent> <buffer> <C-T> <C-\><C-n>:FuzzyOpenFileInTab<CR>
    autocmd FileType fuzzy tnoremap <silent> <buffer> <C-S> <C-\><C-n>:FuzzyOpenFileInSplit<CR>
    autocmd FileType fuzzy tnoremap <silent> <buffer> <C-V> <C-\><C-n>:FuzzyOpenFileInVSplit<CR>
    autocmd FileType fuzzy tnoremap <silent> <buffer> <C-T> <C-\><C-n>:FuzzySwitch<CR>
  augroup END
endif

" }}}
" future implementations {{{1
"
" Methods to be replaced by an actual implementation.
function! s:fuzzy_source.find(...) dict
  call s:fuzzy_err_noexec()
endfunction

function! s:fuzzy_source.find_contents(...) dict
  call s:fuzzy_err_noexec()
endfunction

" }}}
" define commands {{{1
"
command! -nargs=? FuzzyGrep              call s:fuzzy_grep(<q-args>)
command! -nargs=? FuzzyOpen              call s:fuzzy_open(<q-args>)
command!          FuzzyOpenFiles         call s:fuzzy_open_args(<q-args>, 0)
command!          FuzzyOpenBuffers       call s:fuzzy_open_args(<q-args>, 1)
command!          FuzzyOpenFileInTab     call s:fuzzy_split('tab')
command!          FuzzyOpenFileInSplit   call s:fuzzy_split('split')
command!          FuzzyOpenFileInVSplit  call s:fuzzy_split('vsplit')
command!          FuzzySwitch            call s:fuzzy_switch()
command!          FuzzyKill              call s:fuzzy_kill()

" }}}

" utils
"

function! s:strip(str) " {{{1
  return substitute(a:str, '\n*$', '', 'g')
endfunction

function! s:fuzzy_getroot() " {{{1
  for cmd in g:fuzzy_rootcmds
    let result = system(cmd)
    if v:shell_error == 0
      return s:strip(result)
    endif
  endfor
  return "."
endfunction

function! s:fuzzy_get_buffernames() " {{{1
  " 1. Get open buffers.
  " Iterate over the listed buffer ids (the ones listed by :buffers)
  " excluding the current ('%') and previous ('#') buffer ids.
  let bufs = filter(range(1, bufnr('$')),
        \ 'buflisted(v:val)
        \ && bufnr("%") != v:val
        \ && bufnr("#") != v:val
        \ && !empty(bufname(v:val))')
  let bufs = map(bufs, 'expand(bufname(v:val))') " map to filepaths

  " 2. Add the '#' buffer at the head of the list.
  if bufnr('#') > 0 && bufnr('%') != bufnr('#')
    let altbufname = expand(bufname('#'))
    if !empty(altbufname) && buflisted(altbufname)
      call insert(bufs, altbufname)
    end
  endif

  return bufs
endfunction

function! s:fuzzy_switch() " {{{1
  " 'buffers' -> 'files', 'files' -> 'buffers'
  let g:fuzzy_view_current = (g:fuzzy_view_current + 1) % len(g:fuzzy_view_list)
  return s:fuzzy_kill()
endfunction

function! s:fuzzy_kill() " {{{1
  echo
  call jobstop(s:fuzzy_job_id)
endfunction

function! s:fuzzy_err_noexec() " {{{1
  throw "Fuzzy: no search executable was found. " .
      \ "Please make sure either '" .  s:ag.path .
      \ "' or '" . s:rg.path . "' are in your path"
endfunction " }}}

" core functions
"
function! s:ag.find(root, ignorelist) dict " {{{1
  let ignorefile = tempname()
  call writefile(a:ignorelist, ignorefile, 's')
  return systemlist(
    \ s:ag.path . " --silent --nocolor -g '' -Q --path-to-ignore " . ignorefile . ' ' . a:root)
endfunction

function! s:ag.find_contents(query) dict " {{{1
  let query = empty(a:query) ? '^(?=.)' : a:query
  return systemlist(s:ag.path . " --noheading --nogroup --nocolor -S " . shellescape(query) . " .")
endfunction " }}}

function! s:rg.find(root, ignorelist) dict " {{{1
  let ignores = []
  for str in a:ignorelist
    call add(ignores, printf("-g '!%s'", str))
  endfor
  return systemlist(s:rg.path . " --color never --files --fixed-strings " . join(ignores, ' ') . ' ' . a:root . ' 2>/dev/null')
endfunction

function! s:rg.find_contents(query) dict " {{{1
  let query = empty(a:query) ? '.' : shellescape(a:query)
  return systemlist(s:rg.path . " -n --no-heading --color never -S " . query . " . 2>/dev/null")
endfunction " }}}


function! s:fuzzy_grep(str) abort " {{{1
  try
    let contents = s:fuzzy_source.find_contents(a:str)
  catch
    echoerr v:exception
    return
  endtry

  let opts = { 'lines': g:fuzzy_winheight, 'statusfmt': '%s (%d results)', 'root': '.' }

  function! opts.handler(result) abort
    let parts = split(join(a:result), ':')
    let name = parts[0]
    let lnum = parts[1]
    let text = parts[2] " Not used.

    return { 'name': name, 'lnum': lnum }
  endfunction

  return s:fuzzy(contents, opts)
endfunction

function! s:fuzzy_open(root) abort " {{{1
  " prepare the call to fuzzy_open_args
  let current_view = g:fuzzy_view_list[g:fuzzy_view_current]
  let buf_only = current_view == 'buffers' ? 1 : 0
  return s:fuzzy_open_args(a:root, buf_only)

endfunction

function! s:fuzzy_open_args(root, buf_only) abort " {{{1
  let root = empty(a:root) ? s:fuzzy_getroot() : a:root
  exe 'lcd' root

  " get opened buffer names
  let buffernames = s:fuzzy_get_buffernames()
  let filenames = []

  if a:buf_only == 0
    " save a list of files the find command should ignore.
    let ignorelist = !empty(bufname('%')) ? buffernames + [expand(bufname('%'))] : buffernames

    " get all filenames, minus the open buffers.
    try
      let filenames = s:fuzzy_source.find('.', ignorelist)
    catch
      echoerr v:exception
      return
    finally
      lcd -
    endtry
  end

  " put it all together.
  let itemnames = buffernames + filenames

  let opts = {
        \ 'lines': g:fuzzy_winheight,
        \ 'statusfmt': '%s (%d files)',
        \ 'root': root }
  if a:buf_only == 1
    let opts.statusfmt = '%s (%d bufs)'
  endif
  function! opts.handler(itemnames)
    return { 'name': join(a:itemnames) }
  endfunction

  return s:fuzzy(itemnames, opts)
endfunction

function! s:fuzzy(choices, opts) abort " {{{1
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

        if s:fuzzy_selected_opencmd == ''
          let s:fuzzy_selected_opencmd = g:fuzzy_opencmd
        endif

        silent execute s:fuzzy_selected_opencmd . ' ' . fnameescape(expand(file.name))

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
    let s:fuzzy_selected_opencmd = ""
    let s:fuzzy_job_id = termopen(command, opts)
    let b:fuzzy_status_string = printf(
      \ a:opts.statusfmt,
      \ pathshorten(fnamemodify(opts.root, ":~:.:f")),
      \ len(a:choices))
    " setlocal statusline=%{b:fuzzy_status_string}  " too intrusive
    set norelativenumber
    set nonumber
  endif
  let s:fuzzy_bufnr = bufnr('%')
  set filetype=fuzzy
  startinsert
endfunction

function! s:fuzzy_split(split) " {{{1
  let cmd = get(g:fuzzy_splitcmd_map, a:split, '')
  if cmd != ''
    let s:fuzzy_selected_opencmd = cmd
    if exists('*chansend')
      call chansend(s:fuzzy_job_id, "\r\n")
    else
      call jobsend(s:fuzzy_job_id, "\r\n")
    endif
  endif
endfunction " }}}

" API
"
function! fzy#get_status_string() abort " {{{1
  return b:fuzzy_status_string
endfunction

function! fzy#get_view_string() abort " {{{1
  return 'FZY ' . toupper(g:fuzzy_view_list[g:fuzzy_view_current])
endfunction " }}}
