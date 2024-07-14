" vim: set sw=2 ts=2 sts=2 foldmethod=marker:

if exists(':Old')
  finish
endif

""""""""""""""""""""""""""""""""""""""Functions""""""""""""""""""""""""""""""""""""""" {{{
function! IsQfOpen()
  let tabnr = tabpagenr()
  let wins = filter(getwininfo(), {_, w -> w['tabnr'] == tabnr && w['quickfix'] == 1 && w['loclist'] == 0})
  return !empty(wins)
endfunction

function! IsBufferQf()
  let tabnr = tabpagenr()
  let bufnr = bufnr()
  let wins = filter(getwininfo(), {_, w -> w['tabnr'] == tabnr && w['quickfix'] == 1 && w['bufnr'] == bufnr})
  return !empty(wins)
endfunction

function! DropInQf(files, title)
  if len(a:files) <= 0
    echo "No entries"
    return
  endif
  if type(a:files[0]) == type(#{})
    let items = a:files
  else
    let items = map(a:files, "#{filename: v:val}")
  endif

  if len(items) == 1
    if has_key(items[0], 'bufnr') && bufnr() != items[0].buffnr
      exe "buffer " . items[0].buffnr
    elseif has_key(items[0], 'filename') && bufnr() != bufnr(items[0].filename)
      exe "edit " . items[0].filename
    endif
  else
    call setqflist([], ' ', #{title: a:title, items: items})
    copen
  endif
endfunction

function! DisplayInQf(files, title)
  if len(a:files) <= 0
    echo "No entries"
    return
  endif
  if type(a:files[0]) == v:t_dict
    let items = a:files
  else
    let items = map(a:files, "#{filename: v:val}")
  endif

  call setqflist([], ' ', #{title: a:title, items: items})
  copen
endfunction

function ArgFilter(list, args)
  return filter(a:list, "stridx(v:val, a:args) >= 0")
endfunction

function! SplitItems(items, args)
  if len(a:items) > 0 && type(a:items[0]) == v:t_dict
    if has_key(a:items[0], "bufnr")
      let nrs = map(copy(a:items), "v:val.bufnr")
      let items = map(nrs, 'expand("#" . v:val . ":p")')
    else
      let items = map(copy(a:items), "v:val.filename")
    endif
  else
    let items = a:items
  endif

  let compl = []
  for item in items
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

function! UnorderedTailItems(list, args)
  let items = map(a:list, 'fnamemodify(v:val, ":t")')
  let items = filter(items, 'stridx(v:val, a:args) >= 0')
  return items
endfunction

function! TailItems(list, args)
  return UnorderedTailItems(a:list, a:args)->sort()->uniq()
endfunction

function! LinePreview(list)
  for item in a:list
    if has_key(item, 'bufnr')
      let text = getbufline(item.bufnr, item.lnum)
      if !empty(text)
        let item['text'] = text[0]
      endif
    endif
  endfor
  return a:list
endfunction
""""""""""""""""""""""""""""""""""""""Functions""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Old""""""""""""""""""""""""""""""""""""""" {{{
function! s:GetOldFiles()
  return filter(deepcopy(v:oldfiles), "filereadable(v:val)")
endfunction

function! OldCompl(ArgLead, CmdLine, CursorPos)
  if a:CursorPos < len(a:CmdLine)
    return []
  endif
  return s:GetOldFiles()->UnorderedTailItems(a:ArgLead)
endfunction

command -nargs=? -complete=customlist,OldCompl Old call s:GetOldFiles()->ArgFilter(<q-args>)->DropInQf("Old")
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
  if IsBufferQf()
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
  if IsQfOpen()
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

""""""""""""""""""""""""""""""""""""""ChangeList""""""""""""""""""""""""""""""""""""""" {{{
function s:GetChangeList()
  let list = reverse(getchangelist()[0])
  return map(list, "#{col: v:val.col, lnum: v:val.lnum, bufnr: bufnr()}")
endfunction

nnoremap <silent> <leader>ch <cmd>call <SID>GetChangeList()->LinePreview()->DisplayInQf("Change")<CR>

""""""""""""""""""""""""""""""""""""""JumpList""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""ShowBuffers""""""""""""""""""""""""""""""""""""""" {{{
function! s:ShowBuffers(pat)
  function! GetBufferItem(pat, m, n) closure
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

  let items = map(range(1, bufnr('$')), funcref("GetBufferItem", [a:pat]))
  let items = filter(items, "!empty(v:val)")
  call DropInQf(items, "Buffers")
endfunction

nnoremap <silent> <leader>buf :call <SID>ShowBuffers("")<CR>
""""""""""""""""""""""""""""""""""""""ShowBuffers""""""""""""""""""""""""""""""""""""""" }}}

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

command! -nargs=? -complete=customlist,BufferCompl Buffer call s:GetBuffers()->ArgFilter(<q-args>)->DropInQf("Buffer")
""""""""""""""""""""""""""""""""""""""Buffer""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Modified""""""""""""""""""""""""""""""""""""""" {{{
function! s:GetModified()
  let infos = filter(getbufinfo(), "v:val.changed")
  let nrs = map(infos, "v:val.bufnr")
  let names = map(nrs, 'expand("#" . v:val . ":p")')
  return filter(names, "filereadable(v:val)")
endfunction

command! -nargs=0 Modified call s:GetModified()->DisplayInQf("Modified")
""""""""""""""""""""""""""""""""""""""Modified""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Cfdo""""""""""""""""""""""""""""""""""""""" {{{
function! s:QuickfixExMap(cmd)
  let nrs = map(getqflist(), "v:val.bufnr")
  let nrs = uniq(sort(nrs))
  let oldbuf = bufnr()
  for nr in nrs
    exe "keepjumps b " . nr
    let v:errmsg = ""
    silent! exe a:cmd
    if !empty(v:errmsg)
      echom "Error in: " . bufname(nr)
      echom v:errmsg
      break
    endif
  endfor
  exe "b " . oldbuf
endfunction

command! -nargs=+ Cfdo call s:QuickfixExMap(<q-args>)
""""""""""""""""""""""""""""""""""""""Cfdo""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Repos""""""""""""""""""""""""""""""""""""""" {{{
function! GetRepos(force)
  if a:force || !exists('g:PLUGIN_QUTIL_REPOS')
    let old = filter(deepcopy(v:oldfiles), "filereadable(v:val) || isdirectory(v:val)")
    let git = filter(map(old,  "FugitiveExtractGitDir(v:val)"), "!empty(v:val)")
    let repos = map(git, "fnamemodify(v:val, ':h')")
    let g:PLUGIN_QUTIL_REPOS = uniq(sort(repos))
  endif
  return copy(g:PLUGIN_QUTIL_REPOS)
endfunction

function! ReposCompl(ArgLead, CmdLine, CursorPos)
  if a:CursorPos < len(a:CmdLine)
    return []
  endif
  return GetRepos(v:false)->TailItems(a:ArgLead)
endfunction

command! -bang -nargs=? -complete=customlist,ReposCompl Repos
      \ call GetRepos(<bang>v:false)->ArgFilter(<q-args>)->DropInQf("Repos")
""""""""""""""""""""""""""""""""""""""Repos""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""CmdCompl""""""""""""""""""""""""""""""""""""""" {{{
function! CmdCompl(cmdline)
  let complete = 'complete -C ' . shellescape(a:cmdline)
  let output = system(["/usr/bin/fish", "-c", complete])

  " Remove color codes
  let esc = 27
  let pat = printf('%c][^\\]*%c\\', esc, esc)
  let output = substitute(output, pat, "", "g")

  " Split into lines
  let output = split(output, nr2char(10))
  " Split by tab (remove completion description)
  let compl = map(output, "split(v:val, nr2char(9))[0]")
  return compl
endfunction
""""""""""""""""""""""""""""""""""""""CmdCompl""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Make""""""""""""""""""""""""""""""""""""""" {{{
function! Make(...)
  if has_key(g:statusline_dict, "make") && !empty(g:statusline_dict['make'])
    return -1
  endif

  function! s:OnStdout(id, data, event)
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

  function! s:OnStderr(id, data, event)
    for data in a:data
      let text = substitute(data, '\n', '', 'g')
      if len(text) > 0
        let m = matchlist(text, '\(.*\):\([0-9]\+\):\([0-9]\+\): \(.*\)')
        if len(m) >= 5
          let file = m[1]
          let lnum = m[2]
          let col = m[3]
          let text = m[4]
          if filereadable(file)
            let types = ["error:", "warning:"]
            let matched_types = filter(types, "stridx(text, v:val) >= 0")
            if !empty(matched_types)
              let item = #{filename: file, text: text, lnum: lnum, col: col}
              call add(g:make_error_list, item)
            endif
          endif
        endif
        let m = matchlist(text, '\(.*\):\([0-9]\+\): \(.*\)')
        if len(m) >= 4
          let file = m[1]
          let lnum = m[2]
          let text = m[3]
          if filereadable(file)
            let types = ["undefined reference"]
            let matched_types = filter(types, "stridx(text, v:val) >= 0")
            if !empty(matched_types)
              let item = #{filename: file, text: text, lnum: lnum}
              call add(g:make_error_list, item)
            endif
          endif
        endif
      endif
    endfor
  endfunction

  function! s:OnExit(id, code, event)
    if a:code == 0
      echom "Make successful!"
      if exists('#User#MakeSuccessful')
        doauto <nomodeline> User MakeSuccessful
      endif
    else
      echom "Make failed!"
    endif
    if exists("g:make_error_list") && len(g:make_error_list) > 0
      call setqflist([], ' ', #{title: "Make", items: g:make_error_list})
      copen
    endif
    silent! unlet g:make_error_list
    let g:statusline_dict['make'] = ''
  endfunction

  let command = get(a:, 1, "")
  let bang = get(a:, 2, "")
  if bang == ""
    let g:make_error_list = []
    let opts = #{cwd: FugitiveWorkTree(), on_stdout: funcref("s:OnStdout"), on_stderr: funcref("s:OnStderr"), on_exit: funcref("s:OnExit")}
    return jobstart(command, opts)
  else
    bot new
    let id = termopen(command, #{cwd: FugitiveWorkTree(), on_exit: funcref("s:OnExit")})
    call cursor("$", 1)
    return id
  endif
endfunction
""""""""""""""""""""""""""""""""""""""Make""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Mark""""""""""""""""""""""""""""""""""""""" {{{
function! s:OpenMarks(bang)
  if a:bang == "!"
    let nrs = range(1, bufnr("$"))
  else
    let nrs = [bufnr()]
  endif

  let list = []
  for i in nrs
    if buflisted(i)
      let buf_marks = getmarklist(i)
      let buf_marks = map(buf_marks, "#{bufnr: i, lnum: v:val.pos[1], col: v:val.pos[2], text: v:val.mark[1]}")
      let buf_marks = filter(buf_marks, 'v:val.text =~ "\\a"')
      let list += buf_marks
    endif
  endfor
  call DisplayInQf(list, 'Marks')
endfunction

command! -nargs=0 -bang Mark call <SID>OpenMarks("<bang>")
""""""""""""""""""""""""""""""""""""""Mark""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Cff""""""""""""""""""""""""""""""""""""""" {{{
function! s:QuickfixFileFilt(bang, arg)
  let expr = 'stridx(expand("#".v:val.bufnr.":p"), a:arg)'
  if empty(a:bang)
    let list = filter(getqflist(), expr . ' >= 0')
  else
    let list = filter(getqflist(), expr . ' < 0')
  endif
  call DisplayInQf(list, "Cff")
endfunction

command! -nargs=1 -bang Cff call <SID>QuickfixFileFilt("<bang>", <q-args>)
""""""""""""""""""""""""""""""""""""""Cff""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Cf""""""""""""""""""""""""""""""""""""""" {{{
function! s:QuickfixTextFilt(bang, arg)
  let expr = 'stridx(v:val.text, a:arg)'
  if empty(a:bang)
    let list = filter(getqflist(), expr . ' >= 0')
  else
    let list = filter(getqflist(), expr . ' < 0')
  endif
  call DisplayInQf(list, "Cf")
endfunction

command! -nargs=1 -bang Cf call <SID>QuickfixTextFilt("<bang>", <q-args>)
""""""""""""""""""""""""""""""""""""""Cf""""""""""""""""""""""""""""""""""""""" }}}
