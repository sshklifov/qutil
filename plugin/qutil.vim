" vim: set sw=2 ts=2 sts=2 foldmethod=marker:

if exists(':Old')
  finish
endif

function! s:OpenQfResults()
  let len = getqflist({"size": 1})['size']
  if len == 0
    echo "No results"
  elseif len == 1
    cc
  else
    copen
  endif
endfunction

function! s:IsQfOpen()
  let tabnr = tabpagenr()
  let wins = filter(getwininfo(), {_, w -> w['tabnr'] == tabnr && w['quickfix'] == 1 && w['loclist'] == 0})
  return !empty(wins)
endfunction

function! s:IsBufferQf()
  let tabnr = tabpagenr()
  let bufnr = bufnr()
  let wins = filter(getwininfo(), {_, w -> w['tabnr'] == tabnr && w['quickfix'] == 1 && w['bufnr'] == bufnr})
  return !empty(wins)
endfunction

""""""""""""""""""""""""""""""""""""""Old""""""""""""""""""""""""""""""""""""""" {{{
function! s:OldFiles(read_shada)
  if a:read_shada
    rsh!
  endif

  let items = deepcopy(v:oldfiles)
  let items = map(items, {_, f -> {"filename": f, "lnum": 1, 'text': fnamemodify(f, ":t")}})
  call setqflist([], ' ', {'title': 'Oldfiles', 'items': items})
  call s:OpenQfResults()
endfunction

command -nargs=0 -bang Old call s:OldFiles(<bang>0)
""""""""""""""""""""""""""""""""""""""Old""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Cdelete""""""""""""""""""""""""""""""""""""""" {{{
function! s:DeleteQfEntries(a, b)
  let qflist = filter(getqflist(), {i, _ -> i+1 < a:a || i+1 > a:b})
  call setqflist([], ' ', {'title': 'Cdelete', 'items': qflist})
endfunction

autocmd FileType qf command! -buffer -range Cdelete call <SID>DeleteQfEntries(<line1>, <line2>)
""""""""""""""""""""""""""""""""""""""Cdelete""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""JumpList""""""""""""""""""""""""""""""""""""""" {{{
function! s:OpenJumpList()
  let jl = deepcopy(getjumplist())
  let entries = jl[0]
  let idx = jl[1]

  for i in range(len(entries))
    if !bufloaded(entries[i]['bufnr'])
      let entries[i] = #{text: "Not loaded"}
    else
      let lines = getbufline(entries[i]['bufnr'], entries[i]['lnum'])
      if len(lines) > 0
        let entries[i]['text'] = lines[0]
      endif
    endif
  endfor

  call setqflist([], 'r', {'title': 'Jump', 'items': entries})
  " Open quickfix at the relevant position
  if idx < len(entries)
    exe "keepjumps crewind " . (idx + 1)
  endif
  " Keep the same window focused
  let nr = winnr()
  keepjumps copen
  exec "keepjumps " . nr . "wincmd w"
endfunction

function! s:Jump(scope)
  if s:IsBufferQf()
    if a:scope == "i"
      try
        silent cnew
      catch
        echo "Hit newest list"
      endtry
    elseif a:scope == "o"
      try
        silent cold
      catch
        echo "Hit oldest list"
      endtry
    endif
    return
  endif

  " Pass 1 to normal so vim doesn't interpret ^i as a TAB (they use the same keycode of 9)
  if a:scope == "i"
    exe "normal! 1" . "\<c-i>"
  elseif a:scope == "o"
    exe "normal! 1" . "\<c-o>"
  endif

  " Refresh jump list
  if s:IsQfOpen()
    let title = getqflist({'title': 1})['title']
    if title == "Jump"
      call s:OpenJumpList()
    endif
  endif
endfunction

nnoremap <silent> <leader>ju :call <SID>OpenJumpList()<CR>
nnoremap <silent> <c-i> :call <SID>Jump("i")<CR>
nnoremap <silent> <c-o> :call <SID>Jump("o")<CR>
""""""""""""""""""""""""""""""""""""""JumpList""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""ShowBuffers""""""""""""""""""""""""""""""""""""""" {{{
function! s:ShowBuffers(pat)
  let pat = ".*" . a:pat . ".*"
  if a:pat !~# "[A-Z]"
    let pat = '\c' . pat
  else
    let pat = '\C' . pat
  endif

  function! s:GetBufferItem(_, n) closure
    let name = expand('#' . a:n . ':p')
    if !filereadable(name) || match(name, pat) < 0
      return {}
    endif

    let bufinfo = getbufinfo(a:n)[0]
    let text = "" . a:n
    if bufinfo["changed"]
      let text = text . " (modified)"
    endif
    return {"bufnr": a:n, "text": text, "lnum": bufinfo["lnum"]}
  endfunction

  let items = map(range(1, bufnr('$')), function("s:GetBufferItem"))
  let items = filter(items, "!empty(v:val)")
  call setqflist([], 'r', {'title' : 'Buffers', 'items' : items})
  call s:OpenQfResults()
endfunction

nnoremap <silent> <leader>buf :call <SID>ShowBuffers("")<CR>
""""""""""""""""""""""""""""""""""""""Buffer""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Buffer""""""""""""""""""""""""""""""""""""""" {{{
function! BufferCompl(ArgLead, CmdLine, CursorPos)
  if a:CursorPos < len(a:CmdLine)
    return []
  endif

  let pat = ".*" . a:ArgLead . ".*"
  if pat !~# "[A-Z]"
    let pat = '\c' . pat
  else
    let pat = '\C' . pat
  endif

  let names = map(range(1, bufnr('$')), "bufname(v:val)")
  let names = filter(names, "filereadable(v:val)")
  let compl = []
  for name in names
    let parts = split(name, "/")
    for part in parts
      if match(part, pat) >= 0
        call add(compl, part)
      endif
    endfor
  endfor
  return uniq(sort(compl))
endfunction

command! -nargs=? -complete=customlist,BufferCompl Buffer call <SID>ShowBuffers(<q-args>)
""""""""""""""""""""""""""""""""""""""Buffer""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""ToggleQf""""""""""""""""""""""""""""""""""""""" {{{
function! s:ToggleQf()
  if s:IsQfOpen()
    cclose
  else
    copen
  endif
endfunction

nnoremap <silent> <leader>cc :call <SID>ToggleQf()<CR>
""""""""""""""""""""""""""""""""""""""ToggleQf""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""ShowWorkspaces""""""""""""""""""""""""""""""""""""""" {{{
function! s:ShowWorkspaces(bang)
  if empty(a:bang)
    let names = deepcopy(v:oldfiles)
  else
    let names = map(range(1, bufnr('$')), "bufname(v:val)")
    let names = filter(names, "filereadable(v:val)")
  endif
  let git = filter(map(names, "FugitiveExtractGitDir(v:val)"), "!empty(v:val)")
  let git = uniq(sort(git))
  let repos = map(git, "fnamemodify(v:val, ':h')")
  let items = map(repos, {_, f -> {"filename": f, "lnum": 1, 'text': fnamemodify(f, ":t")}})
  call setqflist([], ' ', {'title': 'Git', 'items': items})
  call s:OpenQfResults()
endfunction

command! -nargs=0 -bang Repos call <SID>ShowWorkspaces('<bang>')
""""""""""""""""""""""""""""""""""""""ShowWorkspaces""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Make""""""""""""""""""""""""""""""""""""""" {{{
function! Make(command, bang)
  function! OnStdout(id, data, event)
    for data in a:data
      let text = substitute(data, '\n', '', 'g')
      if len(text) > 0
        let m = matchlist(text, '\[ *\([0-9]\+%\)\]')
        if len(m) > 1 && !empty(m[1])
          let g:statusline_dict['make'] = m[1]
        endif
      endif
    endfor
  endfunction

  function! OnStderr(id, data, event)
    for data in a:data
      let text = substitute(data, '\n', '', 'g')
      if len(text) > 0
        let m = matchlist(text, '\(.*\):\([0-9]\+\):\([0-9]\+\): \(.*\)')
        if len(m) >= 5
          let file = m[1]
          let lnum = m[2]
          let col = m[3]
          let text = m[4]
          if filereadable(file) && (stridx(text, "error:") >= 0 || stridx(text, "warning:") >= 0)
            let item = #{filename: file, text: text, lnum: lnum, col: col}
            call add(g:make_error_list, item)
          endif
        endif
      endif
    endfor
  endfunction

  function! OnExit(id, code, event)
    if a:code == 0
      echom "Make successful!"
      exe "LspRestart"
    else
      echom "Make failed!"
      if exists("g:make_error_list") && len(g:make_error_list) > 0
        call setqflist([], ' ', #{title: "Make", items: g:make_error_list})
        copen
      endif
    endif
    silent! unlet g:make_error_list
    silent! unlet g:statusline_dict['make']
  endfunction

  if a:bang == ""
    let g:make_error_list = []
    let opts = #{cwd: FugitiveWorkTree(), on_stdout: function("OnStdout"), on_stderr: function("OnStderr"), on_exit: function("OnExit")}
    call jobstart(a:command, opts)
  else
    bot new
    let id = termopen(a:command, #{cwd: FugitiveWorkTree(), on_exit: function("OnExit")})
    call cursor("$", 1)
  endif
endfunction

function! MakeTargets(makefile)
  let cmd = 'make -f ' . a:makefile . ' '
  let complete = 'complete -C ' . shellescape(cmd)
  let output = systemlist(["/usr/bin/fish", "-c", complete])
  " Remove color codes
  let output = filter(output, "char2nr(v:val[0]) != 27")
  " Split by tab
  let pairs = map(output, "split(v:val, nr2char(9))")
  " Filter out targets only
  let target_pairs = filter(pairs, "len(v:val) == 2 && v:val[1] == 'Target'")
  " Return the targets
  return map(target_pairs, "v:val[0]")
endfunction
""""""""""""""""""""""""""""""""""""""Make""""""""""""""""""""""""""""""""""""""" }}}
