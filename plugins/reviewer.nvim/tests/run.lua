-- Run from the config root: nvim --headless -u NONE -l plugins/reviewer.nvim/tests/run.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
vim.cmd 'filetype on'

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function eq(want, got)
  if not vim.deep_equal(want, got) then
    error(('\n want: %s\n  got: %s'):format(vim.inspect(want), vim.inspect(got)), 2)
  end
end

local notes = {}

local function pick(index)
  local calls = { n = 0 }
  vim.ui.select = function(items, _, on_choice)
    calls.n = calls.n + 1
    on_choice(items[index], index)
  end
  return calls
end

local function file(lines, ext)
  local path = vim.fn.tempname() .. (ext or '.txt')
  vim.fn.writefile(lines or { 'l1', 'l2', 'l3', 'l4', 'l5', 'l6', 'l7', 'l8', 'l9' }, path)
  vim.cmd.edit(path)
  return vim.api.nvim_get_current_buf(), path
end

-- `nvim -l` has no main loop, so fire TextChanged as the loop does after typed keys.
local function keys(k)
  vim.api.nvim_feedkeys(vim.keycode(k), 'xt', false)
  vim.api.nvim_exec_autocmds('TextChanged', { buffer = 0 })
end

local function settle()
  vim.wait(20, function()
    return false
  end)
end

local function save(lines)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.cmd.write()
  settle()
end

local function add(range, body)
  vim.cmd(range .. 'ReviewAdd')
  save(vim.split(body, '\n'))
end

local function state()
  return vim.tbl_map(function(c)
    return { c.start_line, c.end_line, c.body, c.valid }
  end, require('reviewer.comments').list())
end

local function marks(buf, ns)
  return vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_get_namespaces()['reviewer.' .. ns], 0, -1, { details = true })
end

local function decoration(buf)
  local signs, bodies = {}, {}
  for _, m in ipairs(marks(buf, 'decor')) do
    if m[4].sign_text then
      signs[#signs + 1] = { m[2] + 1, vim.trim(m[4].sign_text) }
    end
    for _, vl in ipairs(m[4].virt_lines or {}) do
      eq('ReviewerBody', vl[1][2])
      bodies[#bodies + 1] = { m[2] + 1, vl[1][1], m[4].virt_lines_above or nil }
    end
  end
  return { signs = signs, bodies = bodies }
end

-- The virtual lines that the spec gives for one comment: an open marker above
-- the first line, then a separator, the body, and a close marker below the last line.
local function zone(first, last, ...)
  local out = { { first, '>>>>>>> review', true }, { last, '=======' } }
  for _, line in ipairs { ... } do
    out[#out + 1] = { last, line }
  end
  out[#out + 1] = { last, '<<<<<<<' }
  return out
end

local function floats()
  return #vim.tbl_filter(function(w)
    return vim.api.nvim_win_get_config(w).relative ~= ''
  end, vim.api.nvim_list_wins())
end

test('commands exist', function()
  for _, cmd in ipairs { 'ReviewAdd', 'ReviewEdit', 'ReviewDelete', 'ReviewSubmit' } do
    eq(2, vim.fn.exists(':' .. cmd))
  end
end)

test('add on lines 3 to 5', function(buf, path)
  local disk = vim.fn.readfile(path)
  add('3,5', 'fix this')
  eq({ { 3, 5, 'fix this', true } }, state())
  eq(vim.uv.fs_realpath(path), require('reviewer.comments').list()[1].path)
  eq(buf, vim.api.nvim_get_current_buf())
  eq(0, floats())
  eq(disk, vim.fn.readfile(path))
end)

test('decoration shows a sign on each line and wraps the range in markers', function(buf)
  add('3,5', 'fix this\nand that')
  eq({
    signs = { { 3, '▍' }, { 4, '▍' }, { 5, '▍' } },
    bodies = zone(3, 5, 'fix this', 'and that'),
  }, decoration(buf))
end)

test('the body and markers use the warning (yellow) highlight', function()
  eq('DiagnosticWarn', vim.api.nvim_get_hl(0, { name = 'ReviewerBody' }).link)
end)

test('insert of two lines above moves the range', function()
  add('3,5', 'fix this')
  keys 'ggOa<CR>b<Esc>'
  eq({ { 5, 7, 'fix this', true } }, state())
end)

test('insert inside the range makes it longer', function(buf)
  add('3,5', 'fix this')
  keys '4Gox<Esc>'
  eq({ { 3, 6, 'fix this', true } }, state())
  eq(4, #decoration(buf).signs)
end)

test('insert directly below the range stays outside', function()
  add('3,5', 'fix this')
  keys '5Gox<Esc>'
  eq({ { 3, 5, 'fix this', true } }, state())
end)

test('delete of all range lines hides the comment, undo brings it back', function(buf)
  add('3,5', 'fix this')
  keys ':3,5delete<CR>'
  eq(false, state()[1][4])
  eq({ signs = {}, bodies = {} }, decoration(buf))
  keys 'u'
  eq({ { 3, 5, 'fix this', true } }, state())
  eq(3, #decoration(buf).signs)
end)

test('unload and reload keep the comment and one anchor', function(buf, path)
  add('3,5', 'fix this')
  vim.cmd.enew()
  vim.cmd('bunload! ' .. buf)
  eq({ { 3, 5, 'fix this', true } }, state())
  vim.cmd.edit(path)
  eq({ { 3, 5, 'fix this', true } }, state())
  eq(1, #marks(vim.api.nvim_get_current_buf(), 'anchor'))
  eq(3, #decoration(vim.api.nvim_get_current_buf()).signs)
end)

test('edit! keeps one anchor', function(buf)
  add('3,5', 'fix this')
  vim.cmd 'edit!'
  eq({ { 3, 5, 'fix this', true } }, state())
  eq(1, #marks(buf, 'anchor'))
end)

test('a repeated BufReadPost keeps one anchor', function(buf)
  add('3,5', 'fix this')
  vim.api.nvim_exec_autocmds('BufReadPost', { buffer = buf })
  eq(1, #marks(buf, 'anchor'))
end)

test('a body of only spaces adds no comment', function()
  vim.cmd '3,5ReviewAdd'
  save { '   ', '' }
  eq({}, state())
  eq(0, floats())
end)

local function cursor(lnum)
  vim.api.nvim_win_set_cursor(0, { lnum, 0 })
end

test('edit at the cursor changes the body', function(buf)
  add('3,5', 'fix this')
  cursor(4)
  vim.cmd 'ReviewEdit'
  eq({ 'fix this' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  save { 'new' }
  eq({ { 3, 5, 'new', true } }, state())
  eq(zone(3, 5, 'new'), decoration(buf).bodies)
end)

test('edit with an empty body keeps the old body', function()
  add('3,5', 'fix this')
  cursor(4)
  vim.cmd 'ReviewEdit'
  save { '  ' }
  eq({ { 3, 5, 'fix this', true } }, state())
  eq(0, floats())
end)

test('delete at the cursor removes the comment, its marks, and its anchor', function(buf)
  add('3,5', 'fix this')
  cursor(4)
  vim.cmd 'ReviewDelete'
  eq({}, state())
  eq({ signs = {}, bodies = {} }, decoration(buf))
  eq(0, #marks(buf, 'anchor'))
end)

test('delete with two comments at the cursor removes the picked one', function()
  add('3,5', 'first')
  add('4,6', 'second')
  cursor(4)
  local calls = pick(2)
  vim.cmd 'ReviewDelete'
  eq(1, calls.n)
  eq({ { 3, 5, 'first', true } }, state())
end)

test('edit with no comment at the cursor does nothing', function()
  add('3,5', 'fix this')
  cursor(8)
  vim.cmd 'ReviewEdit'
  eq(0, floats())
  eq({ { 3, 5, 'fix this', true } }, state())
  eq(vim.log.levels.WARN, notes[1].level)
end)

local function provider(name, on_submit)
  local p = { name = name, got = {} }
  function p.submit(payload, done)
    p.got[#p.got + 1] = payload
    p.done = done
    if on_submit then
      on_submit(done)
    end
  end
  require('reviewer').register_provider(p)
  return p
end

local function ok_now(done)
  done()
end

local function errors()
  return #vim.tbl_filter(function(n)
    return n.level == vim.log.levels.ERROR
  end, notes)
end

-- Run :ReviewSubmit. When it opens the preview, add `notes` under `## Notes` and send it.
local function submit(notes_lines)
  local before = floats()
  vim.cmd 'ReviewSubmit'
  if floats() > before then
    if notes_lines then
      local row = vim.fn.search('^## Notes$', 'n')
      vim.api.nvim_buf_set_lines(0, row + 1, row + 1, false, notes_lines)
    end
    vim.cmd.write()
    settle()
  end
end

-- The message text that the spec gives for a payload, with no notes.
local function message(root, items)
  local out = { ('Review comments for %s. Address each one.'):format(root), '' }
  for _, c in ipairs(items) do
    vim.list_extend(out, { ('## %s:%d-%d'):format(c[1], c[2], c[3]), '', '```' .. c[4], c[5], '```', '', c[6], '' })
  end
  return vim.trim(table.concat(out, '\n'))
end

test('submit sends a payload in path order, then empties the review', function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir)
  local function open(name)
    vim.fn.writefile({ 'l1', 'l2', 'l3', 'l4', 'l5', 'l6', 'l7', 'l8', 'l9' }, dir .. '/' .. name)
    vim.cmd.edit(dir .. '/' .. name)
    return vim.uv.fs_realpath(dir .. '/' .. name)
  end
  local b = open 'b.txt'
  add('7,8', 'second')
  local a = open 'a.lua'
  add('2,3', 'first')
  local p = provider('fake', ok_now)
  submit()
  settle()
  eq({
    {
      root = vim.fn.getcwd(),
      comments = {
        { path = a, start_line = 2, end_line = 3, filetype = 'lua', code = 'l2\nl3', body = 'first' },
        { path = b, start_line = 7, end_line = 8, filetype = 'text', code = 'l7\nl8', body = 'second' },
      },
      message = message(vim.fn.getcwd(), {
        { a, 2, 3, 'lua', 'l2\nl3', 'first' },
        { b, 7, 8, 'text', 'l7\nl8', 'second' },
      }),
    },
  }, p.got)
  eq({}, state())
  eq(0, errors())
end)

test('submit opens a preview with an empty Notes section before the provider runs', function(_, path)
  add('3,4', 'fix this')
  local p = provider('fake', ok_now)
  vim.cmd 'ReviewSubmit'
  eq(1, floats())
  eq({}, p.got)
  eq({
    ('Review comments for %s. Address each one.'):format(vim.fn.getcwd()),
    '',
    '## Notes',
    '',
    '',
    ('## %s:3-4'):format(vim.uv.fs_realpath(path)),
    '',
    '```text',
    'l3',
    'l4',
    '```',
    '',
    'fix this',
    '',
  }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
end)

test('notes in the preview go to the provider', function(_, path)
  add('3,4', 'fix this')
  local p = provider('fake', ok_now)
  submit { 'keep the API', 'run the tests' }
  local want = message(vim.fn.getcwd(), { { vim.uv.fs_realpath(path), 3, 4, 'text', 'l3\nl4', 'fix this' } })
  want = want:gsub('\n\n', '\n\n## Notes\n\nkeep the API\nrun the tests\n\n', 1)
  eq(want, p.got[1].message)
  eq({}, state())
end)

test('an edit of a comment in the preview goes to the provider', function()
  add('3,4', 'fix this')
  local p = provider('fake', ok_now)
  vim.cmd 'ReviewSubmit'
  vim.cmd 'silent %s/fix this/fix that/'
  vim.cmd.write()
  settle()
  eq(true, p.got[1].message:find('fix that', 1, true) ~= nil)
  eq('fix this', p.got[1].comments[1].body)
end)

test('the preview is closed when the provider runs, so a provider window keeps the focus', function(buf)
  add('3,4', 'fix this')
  local seen
  provider('fake', function()
    seen = { floats = floats(), buf = vim.api.nvim_get_current_buf() }
  end)
  submit()
  eq({ floats = 0, buf = buf }, seen)
end)

test('a cancel of the preview keeps the comments and does not call the provider', function()
  add('3,4', 'fix this')
  local p = provider('fake', ok_now)
  vim.cmd 'ReviewSubmit'
  keys 'q'
  settle()
  eq(0, floats())
  eq({}, p.got)
  eq({ { 3, 4, 'fix this', true } }, state())
  eq(0, errors())
  submit()
  eq(1, #p.got)
  eq({}, state())
end)

test('a provider error keeps all comments', function()
  add('3,5', 'one')
  add('7,8', 'two')
  provider('fake', function(done)
    done 'boom'
  end)
  submit()
  settle()
  eq({ { 3, 5, 'one', true }, { 7, 8, 'two', true } }, state())
  eq(1, errors())
end)

test('a second submit during a pending submit does not call the provider', function()
  add('3,5', 'one')
  local p = provider 'fake'
  submit()
  submit()
  settle()
  eq(1, #p.got)
  eq({ { 3, 5, 'one', true } }, state())
end)

test('a comment added during a submit stays after success', function()
  add('3,5', 'one')
  local p = provider 'fake'
  submit()
  add('7,8', 'later')
  p.done()
  settle()
  eq({ { 7, 8, 'later', true } }, state())
end)

test('a second done call is ignored', function()
  add('3,5', 'one')
  local p = provider 'fake'
  submit()
  add('7,8', 'later')
  p.done()
  p.done 'boom'
  settle()
  eq({ { 7, 8, 'later', true } }, state())
  eq(0, errors())
end)

test('submit with no provider keeps the comments and shows an error', function()
  add('3,5', 'one')
  submit()
  settle()
  eq({ { 3, 5, 'one', true } }, state())
  eq(1, errors())
end)

test('submit with no comments does not call the provider', function()
  local p = provider('fake', ok_now)
  submit()
  settle()
  eq(0, #p.got)
  eq(vim.log.levels.WARN, notes[1].level)
end)

test('two providers and no opts.provider ask with select', function()
  add('3,5', 'one')
  local a, b = provider('a', ok_now), provider('b', ok_now)
  local calls = pick(2)
  submit()
  settle()
  eq(1, calls.n)
  eq({ 0, 1 }, { #a.got, #b.got })
end)

test('opts.provider picks the provider without select', function()
  require('reviewer').setup { provider = 'b' }
  add('3,5', 'one')
  local a, b = provider('a', ok_now), provider('b', ok_now)
  local calls = pick(1)
  submit()
  settle()
  eq(0, calls.n)
  eq({ 0, 1 }, { #a.got, #b.got })
end)

test('a comment whose lines are deleted is not in the payload', function()
  add('3,5', 'gone')
  add('7,8', 'kept')
  keys ':3,5delete<CR>'
  local p = provider('fake', ok_now)
  submit()
  settle()
  eq({ { 4, 5, 'l7\nl8', 'kept' } }, vim.tbl_map(function(c)
    return { c.start_line, c.end_line, c.code, c.body }
  end, p.got[1].comments))
end)

test('register_provider with a used name raises an error', function()
  provider 'fake'
  eq(false, pcall(provider, 'fake'))
end)

test('a comment in an unloaded buffer gets code from disk', function(buf, path)
  add('3,5', 'one')
  vim.cmd.enew()
  vim.cmd('bunload! ' .. buf)
  local p = provider('fake', ok_now)
  submit()
  settle()
  eq({ { vim.uv.fs_realpath(path), 'l3\nl4\nl5', 'text' } }, vim.tbl_map(function(c)
    return { c.path, c.code, c.filetype }
  end, p.got[1].comments))
end)

for _, cmd in ipairs { 'wq', 'x' } do
  test(':' .. cmd .. ' in the editor saves once and keeps the main window', function()
    -- With one window, a :wq that closes the main window quits this test process.
    vim.cmd.split()
    local win = vim.api.nvim_get_current_win()
    vim.cmd '3,5ReviewAdd'
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'fix this' })
    vim.cmd(cmd)
    settle()
    eq({ { 3, 5, 'fix this', true } }, state())
    eq(0, floats())
    eq(true, vim.api.nvim_win_is_valid(win))
    eq(win, vim.api.nvim_get_current_win())
  end)
end

test('a save after a submit removed the comment does nothing', function()
  add('3,5', 'fix this')
  cursor(4)
  vim.cmd 'ReviewEdit'
  provider('fake', ok_now)
  submit()
  settle()
  eq({}, state())
  save { 'new' }
  eq({}, state())
  eq(0, floats())
end)

test('ReviewAdd in a buffer with no name adds no comment', function()
  vim.cmd.enew()
  vim.cmd 'ReviewAdd'
  eq({}, state())
  eq(0, floats())
  eq(vim.log.levels.WARN, notes[1].level)
end)

-- Put fake `hc` and `herdr-app` programs first on PATH. `hc send` writes its
-- target and text to files; `send_fail` makes it fail as a blocked terminal.
local function fake_herdr(o)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir)
  vim.fn.writefile({ vim.json.encode { terminals = o.terminals } }, dir .. '/hc-ls.json')
  if o.status then
    vim.fn.writefile({ vim.json.encode(o.status) }, dir .. '/app-status.json')
    vim.fn.writefile({ vim.json.encode { spaces = o.spaces } }, dir .. '/app-ls.json')
  end
  if o.send_fail then
    vim.fn.writefile({}, dir .. '/send-fail')
  end
  for address, title in pairs(o.titles or {}) do
    vim.fn.writefile({ vim.json.encode { address = address, title = title } }, dir .. '/get-' .. address .. '.json')
  end
  vim.fn.writefile({
    '#!/bin/sh',
    'd=$(dirname "$0")',
    'case "$1" in',
    '  ls) cat "$d/hc-ls.json" ;;',
    '  get) [ -f "$d/get-$2.json" ] || exit 3; cat "$d/get-$2.json" ;;',
    '  send)',
    '    if [ -f "$d/send-fail" ]; then',
    '      echo \'{"error":{"kind":"blocked","message":"terminal is blocked"}}\' >&2; exit 9',
    '    fi',
    '    printf "%s" "$2" > "$d/sent-to"; printf "%s" "$3" > "$d/sent" ;;',
    'esac',
  }, dir .. '/hc')
  vim.fn.writefile({ '#!/bin/sh', 'd=$(dirname "$0")', '[ -f "$d/app-$1.json" ] || exit 1', 'cat "$d/app-$1.json"' }, dir .. '/herdr-app')
  vim.fn.setfperm(dir .. '/hc', 'rwxr-xr-x')
  vim.fn.setfperm(dir .. '/herdr-app', 'rwxr-xr-x')
  vim.env.PATH = dir .. ':' .. vim.env.PATH
  require('reviewer').register_provider(require 'reviewer.providers.herdr_core')
  return dir
end

local agents = {
  { address = 't1', agent = 'zsh', cwd = '/x', state = 'live', turn = 0 },
  { address = 't2', agent = 'claude-code', cwd = '/x', state = 'live', status = 'idle', turn = 1 },
  { address = 't3', agent = 'codex', cwd = '/x', state = 'live', status = 'working', turn = 1, where = 'app / 1' },
  { address = 't4', agent = 'pi', cwd = '/x', name = 'fixer', state = 'live', status = 'idle', turn = 1 },
}

-- Replace vim.ui.select. It records the item labels and picks `index`.
local function pick_agent(index)
  local seen = {}
  vim.ui.select = function(items, o, on_choice)
    seen.prompt = o.prompt
    seen.labels = vim.tbl_map(o.format_item, items)
    seen.addresses = vim.tbl_map(function(t)
      return t.address
    end, items)
    on_choice(items[index], index)
  end
  return seen
end

local function wait_for(fn)
  vim.wait(3000, fn, 10)
end

test('herdr-core shows the active agent first, then its space, and sends the preview text', function(_, path)
  local dir = fake_herdr {
    terminals = agents,
    titles = { t4 = 'fix login bug', t2 = '' },
    status = { space = 'sp1', agent = 't4' },
    spaces = {
      { id = 'sp1', tabs = { { terminals = { { terminal = 't3' }, { terminal = 't4' }, { terminal = 't1' } } } } },
      { id = 'sp2', tabs = { { terminals = { { terminal = 't2' } } } } },
    },
  }
  add('3,4', 'fix this')
  local seen = pick_agent(1)
  submit()
  wait_for(function()
    return #state() == 0
  end)
  eq({ 't4', 't3', 't2' }, seen.addresses)
  -- t4 has a title; t3 has no `hc get` answer; t2 has an empty title.
  eq('fixer (active)  fix login bug  pi  /x  idle', seen.labels[1])
  eq('t3  codex  app / 1  working', seen.labels[2])
  eq('t2  claude-code  /x  idle', seen.labels[3])
  eq('t4', vim.fn.readfile(dir .. '/sent-to')[1])
  eq(message(vim.fn.getcwd(), { { vim.uv.fs_realpath(path), 3, 4, 'text', 'l3\nl4', 'fix this' } }), table.concat(vim.fn.readfile(dir .. '/sent'), '\n'))
  eq({}, state())
  eq(0, errors())
end)

test('herdr-core without herdr-app lists the agents in address order', function()
  fake_herdr { terminals = agents }
  add('3,4', 'fix this')
  local seen = pick_agent(2)
  submit()
  wait_for(function()
    return #state() == 0
  end)
  eq({ 't2', 't3', 't4' }, seen.addresses)
  eq({}, state())
end)

test('herdr-core keeps the comments and shows the hc error when the send fails', function()
  fake_herdr { terminals = agents, send_fail = true }
  add('3,4', 'fix this')
  pick_agent(1)
  submit()
  wait_for(function()
    return errors() > 0
  end)
  eq({ { 3, 4, 'fix this', true } }, state())
  eq(true, notes[#notes].msg:find('terminal is blocked', 1, true) ~= nil)
end)

test('herdr-core with no coding agent keeps the comments and does not ask', function()
  fake_herdr { terminals = { agents[1] } }
  add('3,4', 'fix this')
  local calls = pick(1)
  submit()
  settle()
  eq(0, calls.n)
  eq({ { 3, 4, 'fix this', true } }, state())
  eq(1, errors())
end)

test('herdr-core with no agent picked keeps the comments', function()
  fake_herdr { terminals = agents }
  add('3,4', 'fix this')
  vim.ui.select = function(_, _, on_choice)
    on_choice(nil)
  end
  submit()
  settle()
  eq({ { 3, 4, 'fix this', true } }, state())
  eq(1, errors())
end)

local select, notify, env_path = vim.ui.select, vim.notify, vim.env.PATH
local failed = 0
for _, t in ipairs(tests) do
  for name in pairs(package.loaded) do
    if name:match '^reviewer' then
      package.loaded[name] = nil
    end
  end
  require('reviewer').setup {}
  notes = {}
  vim.notify = function(msg, level)
    notes[#notes + 1] = { msg = msg, level = level }
  end
  local ok, err = pcall(t.fn, file())
  vim.ui.select, vim.notify, vim.env.PATH = select, notify, env_path
  vim.cmd 'silent! %bwipeout!'
  io.write(ok and ('ok ' .. t.name) or ('FAIL %s: %s'):format(t.name, err), '\n')
  failed = failed + (ok and 0 or 1)
end
os.exit(failed > 0 and 1 or 0)
