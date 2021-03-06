let s:save_cpo = &cpo
set cpo&vim

let s:Vital    = vital#of('J6uil')
let s:Web_JSON = s:Vital.import('Web.JSON')
unlet s:Vital

let s:connect_time = localtime()

let s:config = {
  \ 'buf_name'          : 'J6uil',
  \ 'archive_statement' : '-- archive --',
  \ 'blank_nickname'    : '                ',
  \ }

function! J6uil#config()
  return s:config
endfunction

function! J6uil#subscribe(room)

  augroup J6uil
    autocmd!
    autocmd! CursorHold * call s:check_connection()
  augroup END

  if !exists('s:lingr')
    if !s:new_lingr()
      return
    endif
  else
    call s:lingr.verify_and_relogin()
  endif

  let room  = a:room
  let rooms = J6uil#get_rooms()
  if room == ''
    let room = rooms[0]
  end

  let status = s:lingr.room_show(room)

  if g:J6uil_multi_window
    call J6uil#buffer#layout(rooms)
  endif
  call J6uil#buffer#switch(room, status)
  call s:observe_start(s:lingr)
endfunction

"
"
function! J6uil#toggle_room(volume)
  let room = J6uil#buffer#current_room()
  let rooms = J6uil#get_rooms()
  let rooms_count = len(rooms)
  let current_index = index(rooms, room)
  let target_index = current_index + a:volume
  if target_index < 0
    let target_index += rooms_count
  elseif target_index >= rooms_count
    let target_index -= rooms_count
  endif
  let target_room = rooms[target_index]
  call J6uil#subscribe(target_room)
endfunction

"
"
function! J6uil#reconnect()
  let room = J6uil#buffer#current_room()
  if room == ''
    echo 'no connection'
    return
  endif
  " todo
  call J6uil#buffer#switch(room, {
        \ 'messages' : [], 
        \ 'roster'   : {'members' : [], 'bots' : []}
        \ })
  set modifiable
  silent %delete _
  call J6uil#subscribe(room)
  echohl Error | echo "reconnected to " . room  | echohl None
endfunction

function! J6uil#disconnect()
  augroup J6uil
    autocmd!
  augroup END
  if exists('b:saved_updatetime')
    let &updatetime = b:saved_updatetime
  endif
  echohl Error | echo '-- disconnected --' | echohl None
endfunction

function! J6uil#load_archives(room, oldest_id)
  let messages = s:lingr.get_archives(a:room, a:oldest_id)
  call J6uil#buffer#load_archives(a:room, messages)
endfunction

function! J6uil#get_rooms()
  if !exists('s:lingr')
    call s:new_lingr()
  endif
  return s:lingr.get_rooms()
endfunction

function! s:observe_start(lingr)
  " めちゃくちゃになってきたな・・・
  let lingr = a:lingr
  call J6uil#thread#release()
  let s:counter = lingr.subscribe()
  call lingr.observe(s:counter, function('J6uil#__update'))
  let s:connect_time = localtime()
endfunction

function! J6uil#__update(res)
  try
    let res = a:res
    let pos = stridx(res, "\r\n\r\n")
    if pos != -1
      let content = strpart(res, pos+4)
    else
      let pos = stridx(res, "\n\n")
      let content = strpart(res, pos+2)
    endif

    let json = s:Web_JSON.decode(content)
  catch
    " normal? error
    if a:res != ''
      call J6uil#buffer#append_message('error. retried oberve lingr ')
      echohl Error | echo 'error. retried oberve lingr ' | echohl None
      call s:lingr.observe(s:counter, function('J6uil#__update'))
      let s:connect_time = localtime()
    endif
    return
  endtry
  
  if J6uil#thread#has_many()
    "echohl Error | echomsg  "thread count is " .  string(J6uil#thread#count()) | echohl None
    return
  endif

  if has_key(json, 'events')
    call J6uil#buffer#update(json)
  endif

  " if over 2 minutes return status ok only ?
  if has_key(json , 'counter')
    let s:counter = json.counter
  endif

  let s:connect_time = localtime()
  call s:lingr.observe(s:counter, function('J6uil#__update'))
endfunction

function! J6uil#say(room, message)
  return s:lingr.say(a:room, a:message)
endfunction

"
"
function! s:new_lingr()
  try
    let user = exists('g:J6uil_user')     ? g:J6uil_user     : exists('g:lingr_vim_user')     ? g:lingr_vim_user     : input('user : ')
    let pass = exists('g:J6uil_password') ? g:J6uil_password : exists('g:lingr_vim_password') ? g:lingr_vim_password : inputsecret('password : ')
  catch
    echohl Error
    echo 'you must define g:J6uil_user or g:lingr_vim_user'
    echo '                g:J6uil_password or g:lingr_vim_password'
    echohl None
    return 0
  endtry
  try
    let s:lingr = J6uil#lingr#new(user, pass)
  catch
    call J6uil#disconnect()
    redraw
    echohl Error | echo "failed to login \n" . v:exception | echohl None
    return 0
  endtry

  return 1
endfunction

function! s:check_connection()
  silent! call feedkeys("g\<Esc>", "n")
  " debug
  if g:J6uil_debug_mode
    echo ' connection ' . (J6uil#thread#is_exists() ? 'ok' : 'ng') . ' : ' .  string(localtime() - s:connect_time)
  endif

  " for : j6uil → unite → j6uil
  if J6uil#buffer#is_current()
    let &updatetime = g:J6uil_updatetime
  endif

  " for reenter to J6uil's buffer
  if J6uil#buffer#has_que()
    call J6uil#buffer#update({'events' : []})
  endif

  " check connection
  if J6uil#thread#is_exists() && (localtime() - s:connect_time) <= 150
    return
  endif

  try
    echohl Error | echo "check connection :  over time. trying to reconnect ..."  | echohl None
    call J6uil#reconnect()
  catch
    redraw
    echohl Error | echo "retried ... "  | echohl None
    call J6uil#buffer#append_message('reconnecting ...')
    sleep 2
    call s:check_connection()
  endtry
endfunction

function! J6uil#action(name)
  let Fn = function('J6uil#action#' . a:name . '#execute')
  call Fn()
endfunction

let &cpo = s:save_cpo
