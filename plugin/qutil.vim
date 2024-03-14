" vim: set sw=2 ts=2 sts=2 foldmethod=marker:

if exists(':Old')
  finish
endif

function! ToQuickfix(files, title)
  if len(a:files) <= 0
    echo "No entries"
    return
  endif

  if type(a:files[0]) == type(#{})
    let items = a:files
  else
    let items = map(a:files, "#{filename: v:val}")
  endif

  call setqflist([], ' ', #{title: a:title, items: items})
  if len(items) == 1
    cc
  else
    copen
  endif
endfunction

function ArgFilter(list, args)
  return filter(a:list, "stridx(v:val, a:args) >= 0")
endfunction

function! SplitItems(list, args)
  let compl = []
  for item in a:list
    let fullname = fnamemodify(item, ':p')
    let parts = split(fullname, "/")
    for part in parts
      if stridx(part, a:args) >= 0
        call add(compl, part)
      endif
    endfor
  endfor
  let res = uniq(sort(compl))
  let exclude = ["home", $USER]
  return filter(res, "index(exclude, v:val) < 0")
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
function! s:GetOldFiles()
  return deepcopy(v:oldfiles)
endfunction

function! OldCompl(ArgLead, CmdLine, CursorPos)
  if a:CursorPos < len(a:CmdLine)
    return []
  endif
  return s:GetOldFiles()->SplitItems(a:ArgLead)
endfunction

command -nargs=? -complete=customlist,OldCompl Old call s:GetOldFiles()->ArgFilter(<q-args>)->ToQuickfix("Old")
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
      let entries[i] = #{text: "Not loaded", valid: 0}
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
  function! s:GetBufferItem(pat, m, n) closure
    let name = expand('#' . a:n . ':p')
    if !filereadable(name) || stridx(name, a:pat) < 0
      return #{}
    endif

    let bufinfo = getbufinfo(a:n)[0]
    let lnum = bufinfo["lnum"]
    let text = string(a:n)
    if bufinfo["changed"]
      let text = text . " (modified)"
    endif
    return #{bufnr: a:n, text: text, lnum: lnum}
  endfunction

  let items = map(range(1, bufnr('$')), function("s:GetBufferItem", [a:pat]))
  let items = filter(items, "!empty(v:val)")
  call ToQuickfix(items, "Buffers")
endfunction

nnoremap <silent> <leader>buf :call <SID>ShowBuffers("")<CR>
""""""""""""""""""""""""""""""""""""""Buffer""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Buffer""""""""""""""""""""""""""""""""""""""" {{{
function! s:GetBuffers()
  let names = map(range(1, bufnr('$')), "bufname(v:val)")
  return filter(names, "filereadable(v:val)")
endfunction

function! BufferCompl(ArgLead, CmdLine, CursorPos)
  if a:CursorPos < len(a:CmdLine)
    return []
  endif
  return s:GetBuffers()->SplitItems(a:ArgLead)
endfunction

command! -nargs=? -complete=customlist,BufferCompl Buffer call s:GetBuffers()->ArgFilter(<q-args>)->ToQuickfix("Buffer")
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

""""""""""""""""""""""""""""""""""""""Repos""""""""""""""""""""""""""""""""""""""" {{{
function! s:GetRepos()
  let names = deepcopy(v:oldfiles)
  let git = filter(map(names, "FugitiveExtractGitDir(v:val)"), "!empty(v:val)")
  let git = uniq(sort(git))
  let repos = map(git, "fnamemodify(v:val, ':h')")
  return repos
endfunction

function! ReposCompl(ArgLead, CmdLine, CursorPos)
  if a:CursorPos < len(a:CmdLine)
    return []
  endif
  return s:GetRepos()->SplitItems(a:ArgLead)
endfunction

command! -nargs=? -complete=customlist,ReposCompl Repos call s:GetRepos()->ArgFilter(<q-args>)->ToQuickfix("Repos")
""""""""""""""""""""""""""""""""""""""Repos""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Make""""""""""""""""""""""""""""""""""""""" {{{
function! Make(...)
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
    let g:statusline_dict['make'] = ''
  endfunction

  let command = get(a:, 1, "")
  let bang = get(a:, 2, "")
  if bang == ""
    let g:make_error_list = []
    let opts = #{cwd: FugitiveWorkTree(), on_stdout: function("OnStdout"), on_stderr: function("OnStderr"), on_exit: function("OnExit")}
    return jobstart(command, opts)
  else
    bot new
    let id = termopen(command, #{cwd: FugitiveWorkTree(), on_exit: function("OnExit")})
    call cursor("$", 1)
    return id
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
