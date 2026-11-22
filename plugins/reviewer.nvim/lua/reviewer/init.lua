local comments = require 'reviewer.comments'
local editor = require 'reviewer.editor'

local M = {}

local opts = {}

local function warn(msg)
  vim.notify('reviewer: ' .. msg, vim.log.levels.WARN)
end

local function title(path, start_line, end_line)
  return ('%s:%d-%d'):format(vim.fn.fnamemodify(path, ':t'), start_line, end_line)
end

local function add(cmd)
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == '' or vim.bo[buf].buftype ~= '' then
    return warn 'this buffer has no file'
  end
  editor.open {
    title = title(path, cmd.line1, cmd.line2),
    body = '',
    on_save = function(body)
      comments.add(buf, cmd.line1, cmd.line2, body)
    end,
  }
end

local function at_cursor(fn)
  local found = comments.at(0, vim.fn.line '.')
  if #found == 0 then
    return warn 'no comment at the cursor'
  elseif #found == 1 then
    return fn(found[1])
  end
  vim.ui.select(found, {
    prompt = 'Comment',
    format_item = function(c)
      return ('%d-%d: %s'):format(c.start_line, c.end_line, c.body:match '[^\n]*')
    end,
  }, function(c)
    if c then
      fn(c)
    end
  end)
end

local function edit()
  at_cursor(function(c)
    editor.open {
      title = title(c.path, c.start_line, c.end_line),
      body = c.body,
      on_save = function(body)
        comments.update(c.id, body)
      end,
    }
  end)
end

local function delete()
  at_cursor(function(c)
    comments.remove(c.id)
  end)
end

---@type reviewer.Provider[]
local providers = {}
---@type 'idle'|'submitting'
local state = 'idle'

local function provider_named(name)
  return vim.iter(providers):find(function(p)
    return p.name == name
  end)
end

function M.register_provider(provider)
  if provider_named(provider.name) then
    error(('reviewer: provider %q is already registered'):format(provider.name), 2)
  end
  providers[#providers + 1] = provider
end

local function choose_provider(fn)
  local chosen = provider_named(opts.provider)
  if chosen or #providers == 1 then
    return fn(chosen or providers[1])
  elseif #providers == 0 then
    return vim.notify('reviewer: no provider is registered', vim.log.levels.ERROR)
  end
  vim.ui.select(providers, {
    prompt = 'Provider',
    format_item = function(p)
      return p.name
    end,
  }, function(p)
    if p then
      fn(p)
    end
  end)
end

local function payload_comment(c)
  local buf = vim.iter(vim.api.nvim_list_bufs()):find(function(b)
    return vim.api.nvim_buf_get_name(b) == c.path
  end)
  local lines = buf and vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_lines(buf, c.start_line - 1, c.end_line, false)
    or vim.list_slice(vim.fn.readfile(c.path), c.start_line, c.end_line)
  return {
    path = c.path,
    start_line = c.start_line,
    end_line = c.end_line,
    filetype = buf and vim.bo[buf].filetype or vim.filetype.match { filename = c.path } or '',
    code = table.concat(lines, '\n'),
    body = c.body,
  }
end

local function render(payload)
  local out = { ('Review comments for %s. Address each one.'):format(payload.root), '', '## Notes', '', '' }
  for _, c in ipairs(payload.comments) do
    vim.list_extend(out, {
      ('## %s:%d-%d'):format(vim.fs.relpath(payload.root, c.path) or c.path, c.start_line, c.end_line),
      '',
      '```' .. c.filetype,
      c.code,
      '```',
      '',
      c.body,
      '',
    })
  end
  return table.concat(out, '\n')
end

local function send(provider, payload, valid)
  local called = false
  local function done(err)
    if called then
      return
    end
    called = true
    vim.schedule(function()
      state = 'idle'
      if err then
        return vim.notify(('reviewer: %s failed: %s'):format(provider.name, err), vim.log.levels.ERROR)
      end
      for _, c in ipairs(valid) do
        comments.remove(c.id)
      end
      vim.notify(('reviewer: sent %d comments to %s'):format(#valid, provider.name))
    end)
  end
  local ok, err = pcall(provider.submit, payload, done)
  if not ok then
    done(tostring(err))
  end
end

local function submit()
  if state == 'submitting' then
    return warn 'a submit is in progress'
  end
  local valid = vim.tbl_filter(function(c)
    return c.valid
  end, comments.list())
  if #valid == 0 then
    return warn 'no comments to submit'
  end
  local payload = { root = vim.fn.getcwd(), comments = vim.tbl_map(payload_comment, valid) }
  table.sort(payload.comments, function(a, b)
    return a.path < b.path or (a.path == b.path and a.start_line < b.start_line)
  end)

  choose_provider(function(provider)
    state = 'submitting'
    editor.open {
      title = 'Review → ' .. provider.name,
      body = render(payload),
      width = math.min(100, math.floor(vim.o.columns * 0.9)),
      height = math.floor(vim.o.lines * 0.8),
      on_save = function(message)
        -- An empty Notes section is noise for the agent.
        payload.message = message:gsub('\n## Notes%s*\n## ', '\n## ', 1)
        send(provider, payload, valid)
      end,
      on_cancel = function()
        state = 'idle'
        vim.notify 'reviewer: submit cancelled'
      end,
    }
  end)
end

function M.setup(user_opts)
  opts = user_opts or {}
  vim.api.nvim_create_user_command('ReviewAdd', add, { range = true })
  vim.api.nvim_create_user_command('ReviewEdit', edit, {})
  vim.api.nvim_create_user_command('ReviewDelete', delete, {})
  vim.api.nvim_create_user_command('ReviewSubmit', submit, {})
end

return M
