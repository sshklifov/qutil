" vim: set sw=2 ts=2 sts=2 foldmethod=marker:

if exists(':Old')
  finish
endif

""""""""""""""""""""""""""""""""""""""Custom quickfix""""""""""""""""""""""""""""""""""""""" {{{
function! qutil#CreateCommandQuickfix(lines, name, cmd)
  if len(a:lines) <= 0
    echo "No entries"
    return -1
  endif
  call assert_true(type(a:lines[0]) == type(""))
  call qutil#CloseQuickfix()

  let nr = init#CustomBottomBuffer(a:name, a:lines)
  call setbufvar(nr, '&modifiable', v:true)
  resize 10
  setlocal cursorline
  exe "nnoremap <silent> <buffer> <CR> :" .. a:cmd .. '<CR>'
  let b:custom_quickfix = 1
  return nr
endfunction

function! qutil#CreateCustomQuickfix(lines, name, cb, ...)
  let Cb = function(a:cb, a:000)
  let cmd = "call " .. string(Cb) .. "()"
  return qutil#CreateCommandQuickfix(a:lines, a:name, cmd)
endfunction

function! qutil#CreateOneShotQuickfix(lines, name, cb, ...)
  if len(a:lines) == 1
    let Cb = function(a:cb, a:000)
    call Cb(a:lines[0])
    return -1
  endif
  return qutil#CreateCustomQuickfix(a:lines, a:name, '<SID>OneShotQuickfix', a:cb, a:000)
endfunction

function s:OneShotQuickfix(cb, args)
  let entry = getline('.')
  quit
  let Partial = function(a:cb, a:args)
  call Partial(entry)
endfunction

function qutil#CreateMultiQuickfix(lines, enabled, name, cb, ...)
  let nr = qutil#CreateCustomQuickfix(a:lines, a:name, function('s:OnMultiQuickfixToggle'))
  let ns = nvim_create_namespace('multi_quickfix')
  for idx in range(len(a:enabled))
    let hl = a:enabled[idx] ? 'DiagnosticOk' : 'DiagnosticUnnecessary'
    call nvim_buf_set_extmark(nr, ns, idx, 0, #{line_hl_group: hl})
  endfor
  call init#OnBufDelete(nr, function("s:OnMultiQuickfixExit", [a:cb, a:000]))
endfunction

function! s:OnMultiQuickfixToggle()
  let idx = line('.') - 1
  let nr = bufnr()
  let ns = nvim_create_namespace('multi_quickfix')
  let extmark = nvim_buf_get_extmarks(nr, ns, [idx, 0], [idx, 0], #{details: 1})[0]
  call nvim_buf_del_extmark(nr, ns, extmark[0])
  let old_hl = extmark[3]["line_hl_group"]
  let new_hl = old_hl == 'DiagnosticOk' ? 'DiagnosticUnnecessary' : 'DiagnosticOk'
  call nvim_buf_set_extmark(nr, ns, idx, 0, #{line_hl_group: new_hl})
endfunction

function! s:OnMultiQuickfixExit(cb, args)
  let lines = line('$')
  let nr = str2nr(expand("<abuf>"))
  let ns = nvim_create_namespace('multi_quickfix')
  let extmarks = nvim_buf_get_extmarks(nr, ns, [0, 0], [lines, 0], #{details: 1})
  let enabled = map(extmarks, 'v:val[3].line_hl_group == "DiagnosticOk"')

  let Cb = function(a:cb, a:args)
  call Cb(enabled)
endfunction

""""""""""""""""""""""""""""""""""""""Custom quickfix""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Functions""""""""""""""""""""""""""""""""""""""" {{{
function! s:IsQuickfix(_, w)
  if a:w['tabnr'] != tabpagenr()
    return v:false
  endif
  if a:w['loclist']
    return v:false
  endif
  
  if a:w['quickfix']
    return v:true
  endif
  let bufnr = winbufnr(a:w['winid'])
  return getbufvar(bufnr, 'custom_quickfix', v:null)
endfunction

function! qutil#GetQuickfixWins()
  let wininfos = filter(getwininfo(), function('s:IsQuickfix'))
  return map(wininfos, 'v:val.winid')
endfunction

function! qutil#IsQuickfixOpen()
  return !empty(qutil#GetQuickfixWins())
endfunction

function! qutil#IsQuickfix()
  let matches = qutil#GetQuickfixWins()
  return !empty(filter(matches, 'v:val == win_getid()'))
endfunction

function! qutil#CloseQuickfix()
  for winid in qutil#GetQuickfixWins()
    call nvim_win_close(winid, v:false)
  endfor
endfunction

function! qutil#SetQuickfix(items, title, ...)
  if len(a:items) <= 0
    echo "No entries"
    return
  endif
  if type(a:items[0]) == type(#{})
    let items = a:items
  else
    let items = map(a:items, "#{filename: v:val}")
  endif
  " Close special quickfix windows
  call qutil#CloseQuickfix()

  let opts = get(a:000, 0, #{})
  if has_key(opts, 'oneshot') && len(items) == 1
    let item = items[0]
    if has_key(item, 'bufnr') && bufnr() != item.bufnr
      exe "buffer " . item.bufnr
    elseif has_key(item, 'filename') && bufnr() != bufnr(item.filename)
      exe "edit " . item.filename
    endif
    if has_key(item, 'lnum')
      exe item.lnum
    endif
    if has_key(item, 'col')
      exe printf("normal %d|", item.col)
    endif
  else
    call setqflist([], ' ', #{title: a:title, items: items})
    if has_key(opts, 'hide')
      cc 1
    else
      copen
    endif
  endif
endfunction

function! qutil#MapQuickfix(Cb)
  let winids = qutil#GetQuickfixWins()
  if empty(winids)
    return []
  endif
  let bufnr = winbufnr(winids[0])
  let is_custom = getbufvar(bufnr, 'custom_quickfix', v:null)

  if is_custom
    return map(getbufline(a:bufnr, 1, '$'), 'a:Cb(#{text: v:val})')
  else
    return map(getqflist(), 'a:Cb(v:val)')
  endif
endfunction

function! qutil#FilterQuickfix(Cb)
  let winids = qutil#GetQuickfixWins()
  if empty(winids)
    return []
  endif
  let bufnr = winbufnr(winids[0])
  let is_custom = getbufvar(bufnr, 'custom_quickfix', v:null)

  if is_custom
    let lines = filter(getbufline(bufnr, 1, '$'), 'a:Cb(#{text: v:val})')
    call nvim_buf_set_lines(bufnr, 0, -1, v:false, lines)
  else
    let list = getqflist(#{items: 1, title: 1})
    let list = filter(list.items, 'a:Cb(v:val)')
    call setqflist([], ' ', list)
  endif
endfunction

function! qutil#DropInQuickfix(items, title)
  return qutil#SetQuickfix(a:items, a:title, #{oneshot: v:true})
endfunction

function! qutil#LoadQuickfix(items, title)
  return qutil#SetQuickfix(a:items, a:title, #{oneshot: v:true, hide: v:true})
endfunction

function! qutil#FileFilter(list, str, ...)
  let opts = get(a:000, 0, #{})
  let items = copy(a:list)

  if has_key(opts, 'basename')
    let items = map(items, 'fnamemodify(v:val, ":t")')
  endif
  if has_key(opts, 'component')
    let items = flatten(map(items, 'split(fnamemodify(v:val, ":p"), "/")'))
    let exclude = ["home", $USER]
    let items = filter(items, "index(exclude, v:val) < 0")
  endif
  if has_key(opts, 'unique')
    let items = uniq(sort(items))
  endif
  if has_key(opts, 'sort')
    let items = map(items, '[stridx(v:val, a:str), v:val]')
    call filter(items, 'v:val[0] >= 0')
    call sort(items)
    let items = map(items, 'v:val[1]')
  else
    let items = filter(items, "stridx(v:val, a:str) >= 0")
  endif
  return items
endfunction

function! qutil#BasenameFilter(list, str, ...)
  let opts = get(a:000, 0, #{})
  let ret = []
  for item in a:list
    let b = fnamemodify(item, ":t")
    if has_key(opts, 'oneshot') && b ==# a:str
      return [item]
    endif
    if stridx(b, a:str) >= 0
      call add(ret, item)
    endif
  endfor
  return ret
endfunction

function! qutil#FileCompletionPass(list, arg)
  return qutil#FileFilter(a:list, a:arg, #{basename: 1, sort: 1, unique: 1})
endfunction

function! qutil#ComponentCompletionPass(list, arg)
  return qutil#FileFilter(a:list, a:arg, #{component: 1, sort: 1, unique: 1})
endfunction

function! qutil#CommandPass(list, arg)
  return qutil#BasenameFilter(a:list, a:arg, #{oneshot: 1})
endfunction

function! qutil#AddLinePreview(list)
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
function! s:GetOldFiles(bang)
  let files = filter(deepcopy(v:oldfiles), "filereadable(v:val)")
  if !empty(a:bang)
    let dir = getcwd()
    let ncmp = len(dir) - 1
    call filter(files, 'v:val[:ncmp] == dir')
  endif
  return files
endfunction

function! qutil#OldCompl(ArgLead, CmdLine, CursorPos)
  if a:CursorPos < len(a:CmdLine)
    return []
  endif
  let idx = stridx(a:CmdLine, "!")
  let bang = idx > 0 && idx <= 3 ? "!" : ""
  return s:GetOldFiles(bang)->qutil#FileFilter(a:ArgLead, #{basename: 1})
endfunction

command -nargs=? -bang -complete=customlist,qutil#OldCompl Old call s:GetOldFiles("<bang>")->qutil#CommandPass(<q-args>)->qutil#DropInQuickfix("Old")
""""""""""""""""""""""""""""""""""""""Old""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Cdelete""""""""""""""""""""""""""""""""""""""" {{{
function! s:DeleteQfEntries(a, b)
  let view = winsaveview()
  let qflist = filter(getqflist(), {i, _ -> i+1 < a:a || i+1 > a:b})
  call qutil#SetQuickfix(qflist, 'Cdelete')
  call winrestview(view)
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
  if qutil#IsQuickfix()
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
  if qutil#IsQuickfixOpen()
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

nnoremap <silent> <leader>ch <cmd>call <SID>GetChangeList()->qutil#AddLinePreview()->qutil#LoadQuickfix("Change")<CR>

""""""""""""""""""""""""""""""""""""""JumpList""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""ShowBuffers""""""""""""""""""""""""""""""""""""""" {{{
function! s:ShowBuffers(pat)
  let items = []
  for bufnr in range(1, bufnr('$'))
    let name = expand('#' .. bufnr .. ':p')
    if !filereadable(name) || stridx(name, a:pat) < 0
      continue
    endif

    let bufinfo = getbufinfo(bufnr)[0]
    let lnum = bufinfo["lnum"]
    let text = string(bufnr)
    if bufinfo["changed"]
      let text = text . " (modified)"
    endif
    call add(items, #{bufnr: a:n, text: text, lnum: lnum})
  endfor
  call qutil#DropInQuickfix(items, "Buffers")
endfunction

nnoremap <silent> <leader>buf :call <SID>ShowBuffers("")<CR>
""""""""""""""""""""""""""""""""""""""ShowBuffers""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Modified""""""""""""""""""""""""""""""""""""""" {{{
function! s:GetModified()
  let infos = filter(getbufinfo(), "v:val.changed")
  let nrs = map(infos, "v:val.bufnr")
  let names = map(nrs, 'expand("#" . v:val . ":p")')
  return filter(names, "filereadable(v:val)")
endfunction

command! -nargs=0 Modified call s:GetModified()->qutil#DropInQuickfix("Modified")
""""""""""""""""""""""""""""""""""""""Modified""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Unique""""""""""""""""""""""""""""""""""""""" {{{
function! s:UniqueQuickfix()
  let qf = copy(getqflist())
  call map(qf, {key, value -> #{key: key, value: value}})
  let Cmp = {a, b, -> a.value['bufnr'] - b.value['bufnr']}
  call uniq(sort(qf, Cmp), Cmp)
  call sort(qf, {a, b -> a.key - b.key})
  call map(qf, 'v:val.value')
  call qutil#SetQuickfix(qf, "Unique")
endfunction

command! -nargs=0 Unique call s:UniqueQuickfix() 
""""""""""""""""""""""""""""""""""""""Unique""""""""""""""""""""""""""""""""""""""" }}}

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
function! s:IsGitDir(dir)
  if a:dir[-1:-1] == '/'
    " Unlikely branch
    let git_dir = a:dir[:-2]
  else
    let git_dir = a:dir
  endif
  let git_dir ..= "/.git"
  return isdirectory(git_dir)
endfunction

function! s:CacheRepos()
  " Sanity check
  if !empty($GIT_CEILING_DIRECTORIES) || !empty($GIT_WORK_TREE) || !empty($GIT_DIR)
    call nvim_echo([["Git environment variables detected (not supported)!", "WarningMsg"]], v:true, #{})
    let s:repos = []
    return
  endif

  let memo = {}
  let old = filter(deepcopy(v:oldfiles), "filereadable(v:val)")
  for file in old
    let old_subdir = file
    let subdir = fnamemodify(old_subdir, ":h")
    while subdir != old_subdir
      if !has_key(memo, subdir)
        let memo[subdir] = s:IsGitDir(subdir)
      else
        break
      endif
      let old_subdir = subdir
      let subdir = fnamemodify(subdir, ":h")
    endwhile
  endfor
  let s:repos = keys(filter(memo, 'v:val'))
endfunction

function! qutil#GetRepos()
  if !exists('s:repos')
    call s:CacheRepos()
  endif
  return copy(s:repos)
endfunction

function! qutil#ReposCompl(ArgLead, CmdLine, CursorPos)
  if a:CursorPos < len(a:CmdLine)
    return []
  endif
  return qutil#GetRepos()->qutil#FileCompletionPass(a:ArgLead)
endfunction

command! -bang -nargs=? -complete=customlist,qutil#ReposCompl Repos
      \ call qutil#GetRepos()->qutil#CommandPass(<q-args>)->qutil#DropInQuickfix("Repos")
""""""""""""""""""""""""""""""""""""""Repos""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""CmdCompl""""""""""""""""""""""""""""""""""""""" {{{
function! qutil#CmdCompl(cmdline)
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
function! qutil#Make(command, ...)
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
            let types = ["error:", "warning:", "required from here"]
            let matched_types = filter(types, "stridx(text, v:val) >= 0")
            if !empty(matched_types)
              let item = #{filename: file, text: text, lnum: lnum, col: col}
              call add(g:make_error_list, item)
            endif
          endif
        endif
        let m = matchlist(text, '\(.*\):\([0-9]\+\):\s*\(.*\)')
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
      call nvim_echo([["Make failed!", "ErrorMsg"]], v:true, #{})
    endif
    if exists("g:make_error_list") && len(g:make_error_list) > 0
      call qutil#SetQuickfix(g:make_error_list, "Make")
      copen
    endif
    silent! unlet g:make_error_list
    let g:statusline_dict['make'] = ''
  endfunction

  let command = a:command
  if empty(command)
    return init#Warn("Empty command supplied")
  endif
  let bang = get(a:000, 0, "")
  if bang == ""
    let g:make_error_list = []
    let opts = #{cwd: FugitiveWorkTree(), on_stdout: funcref("s:OnStdout"), on_stderr: funcref("s:OnStderr"), on_exit: funcref("s:OnExit")}
    return init#Jobstart(command, opts)
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
  call qutil#SetQuickfix(list, 'Marks')
endfunction

command! -nargs=0 -bang Mark call <SID>OpenMarks("<bang>")
""""""""""""""""""""""""""""""""""""""Mark""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Cff""""""""""""""""""""""""""""""""""""""" {{{

function! s:CustomQuickfixFilter(bufnr, bang, arg)
  let mod = getbufvar(a:bufnr, '&modifiable', v:null)
  if !mod
    echo "Not modifiable!"
    return
  endif

  let expr =  'stridx(v:val, a:arg)'
  if empty(a:bang)
    let expr ..= ' >= 0'
  else
    let expr ..= ' < 0'
  endif
  let lines = filter(getbufline(a:bufnr, 1, '$'), expr)
  call nvim_buf_set_lines(a:bufnr, 0, -1, v:false, lines)
endfunction

function! s:QuickfixFileFilter(bang, arg)
  let winids = qutil#GetQuickfixWins()
  if empty(winids)
    return
  endif
  let bufnr = winbufnr(winids[0])
  let is_custom = getbufvar(bufnr, 'custom_quickfix', v:null)

  if is_custom
    call s:CustomQuickfixFilter(bufnr, a:bang, a:arg)
  else
    let expr = 'stridx(expand("#".v:val.bufnr.":p"), a:arg)'
    if empty(a:bang)
      let list = filter(getqflist(), expr . ' >= 0')
    else
      let list = filter(getqflist(), expr . ' < 0')
    endif
    call qutil#SetQuickfix(list, "Cff")
  endif
endfunction

command! -nargs=1 -bang Cff call <SID>QuickfixFileFilter("<bang>", <q-args>)
""""""""""""""""""""""""""""""""""""""Cff""""""""""""""""""""""""""""""""""""""" }}}

""""""""""""""""""""""""""""""""""""""Cf""""""""""""""""""""""""""""""""""""""" {{{
function! s:QuickfixTextFilt(bang, arg)
  let winids = qutil#GetQuickfixWins()
  if empty(winids)
    return
  endif
  let bufnr = winbufnr(winids[0])
  let is_custom = getbufvar(bufnr, 'custom_quickfix', v:null)

  if is_custom
    call s:CustomQuickfixFilter(bufnr, a:bang, a:arg)
  else
    let expr = 'stridx(v:val.text, a:arg)'
    if empty(a:bang)
      let list = filter(getqflist(), expr . ' >= 0')
    else
      let list = filter(getqflist(), expr . ' < 0')
    endif
    call qutil#SetQuickfix(list, "Cf")
  endif
endfunction

command! -nargs=1 -bang Cf call <SID>QuickfixTextFilt("<bang>", <q-args>)
""""""""""""""""""""""""""""""""""""""Cf""""""""""""""""""""""""""""""""""""""" }}}
