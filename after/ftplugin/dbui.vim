function! s:is_main_edit_candidate(win) abort
  let ft = getwinvar(a:win, '&filetype')
  let bt = getwinvar(a:win, '&buftype')

  if ft ==# 'dbui' || ft ==# 'snacks_dashboard'
    return 1
  endif

  if bt !=# ''
    return 0
  endif

  if ft =~# '^snacks_' || ft ==# 'neo-tree'
    return 0
  endif

  return 1
endfunction

function! s:find_main_edit_window() abort
  let dashboard = 0
  let widest = 0
  let widest_width = -1

  for win in range(1, winnr('$'))
    let ft = getwinvar(win, '&filetype')
    if ft ==# 'snacks_dashboard'
      let dashboard = win
      break
    endif
  endfor

  if dashboard > 0
    return dashboard
  endif

  for win in range(1, winnr('$'))
    if !s:is_main_edit_candidate(win)
      continue
    endif
    let width = winwidth(win)
    if width > widest_width
      let widest = win
      let widest_width = width
    endif
  endfor

  return widest
endfunction

function! s:dbui_open_like_file() abort
  let drawer = db_ui#drawer#get()
  let item = drawer.get_current_item()

  if get(item, 'action', '') !=# 'open'
    return drawer.toggle_line('edit')
  endif

  let target = s:find_main_edit_window()
  if target <= 0
    return drawer.toggle_line('edit')
  endif

  let save_win = win_getid()
  call win_gotoid(win_getid(target))

  if &filetype ==# 'snacks_dashboard' || &buftype ==# 'nofile'
    enew
  endif

  let db = drawer.dbui.dbs[item.dbui_db_key_name]
  let query = drawer.get_query()
  let opts = {
        \ 'table': get(item, 'table', ''),
        \ 'schema': get(item, 'schema', ''),
        \ }
  if has_key(item, 'content')
    let opts.content = item.content
  endif

  if item.type ==# 'buffer'
    call query.open_buffer(db, item.file_path, 'keepalt edit')
  else
    let buffer_name = query.generate_buffer_name(db, {
          \ 'schema': opts.schema,
          \ 'table': opts.table,
          \ 'label': get(item, 'label', ''),
          \ 'filetype': db.filetype,
          \ })
    call query.open_buffer(db, buffer_name, 'keepalt edit', opts)
  endif

  if win_getid() != save_win && &filetype ==# 'dbui'
    call win_gotoid(save_win)
  endif
endfunction

nnoremap <silent><buffer> <CR> :call <SID>dbui_open_like_file()<CR>
