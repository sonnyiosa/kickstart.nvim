-- Sends the review to a running coding agent through herdr-core (`hc`).
local M = { name = 'herdr-core' }

local function decode(text)
  local ok, value = pcall(vim.json.decode, text or '', { luanil = { object = true, array = true } })
  return ok and value or nil
end

local function read_json(cmd)
  local ok, r = pcall(function()
    return vim.system(cmd, { text = true }):wait(3000)
  end)
  return ok and r.code == 0 and decode(r.stdout) or nil
end

-- Agents are the live terminals that report a status. The active agent of the
-- current herdr-app space comes first, then the other agents of that space.
local function agents()
  local ls = read_json { 'hc', 'ls', '--json' }
  if not ls then
    return nil
  end
  local list = vim.tbl_filter(function(t)
    return t.status ~= nil
  end, ls.terminals or {})

  -- `hc ls` has no title; `hc get` has it. Run them all at once, then collect.
  local gets = vim.tbl_map(function(t)
    local ok, job = pcall(vim.system, { 'hc', 'get', t.address, '--json' }, { text = true })
    return ok and job or nil
  end, list)
  for i, t in ipairs(list) do
    local r = gets[i] and gets[i]:wait(3000)
    local info = r and r.code == 0 and decode(r.stdout) or {}
    t.title = info.title ~= '' and info.title or nil
  end

  local status = read_json { 'herdr-app', 'status' } or {}
  local in_space = {}
  for _, space in ipairs(status.space and (read_json { 'herdr-app', 'ls' } or {}).spaces or {}) do
    if space.id == status.space then
      for _, tab in ipairs(space.tabs or {}) do
        for _, t in ipairs(tab.terminals or {}) do
          in_space[t.terminal] = true
        end
      end
    end
  end
  local function rank(t)
    return t.address == status.agent and 0 or in_space[t.address] and 1 or 2
  end
  for _, t in ipairs(list) do
    t.active = rank(t) == 0
  end
  table.sort(list, function(a, b)
    local ra, rb = rank(a), rank(b)
    return ra < rb or (ra == rb and a.address < b.address)
  end)
  return list
end

local function label(t)
  local title = t.title and ('  ' .. t.title) or ''
  return ('%s%s%s  %s  %s  %s'):format(t.name or t.address, t.active and ' (active)' or '', title, t.agent or '?', t.where or t.cwd or '', t.status)
end

function M.submit(payload, done)
  local list = agents()
  if not list then
    return done 'hc ls failed'
  elseif #list == 0 then
    return done 'no running coding agent'
  end
  vim.ui.select(list, { prompt = 'Send review to', format_item = label }, function(t)
    if not t then
      return done 'no agent selected'
    end
    vim.system({ 'hc', 'send', t.address, payload.message }, { text = true }, function(r)
      if r.code == 0 then
        return done()
      end
      local err = decode(r.stderr)
      done(('hc send %s: %s'):format(t.address, err and err.error and err.error.message or vim.trim(r.stderr or '')))
    end)
  end)
end

return M
