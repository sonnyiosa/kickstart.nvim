local api = vim.api
local M = {}

local anchor_ns = api.nvim_create_namespace 'reviewer.anchor'
local decor_ns = api.nvim_create_namespace 'reviewer.decor'

---@type table<integer, reviewer.Entry>
local entries = {}
local next_id = 1

local function anchor(e, buf)
  local id = api.nvim_buf_set_extmark(buf, anchor_ns, e.start_line - 1, 0, {
    end_row = e.end_line,
    end_col = 0,
    end_right_gravity = false,
    undo_restore = true,
    strict = false,
  })
  e.anchor = { buf = buf, id = id }
end

local function range(e)
  if not e.anchor then
    return e.start_line, e.end_line
  end
  local m = api.nvim_buf_get_extmark_by_id(e.anchor.buf, anchor_ns, e.anchor.id, { details = true })
  return m[1] + 1, m[3].end_row
end

function M.list()
  local out = {}
  for _, e in pairs(entries) do
    local s, last = range(e)
    out[#out + 1] = { id = e.id, path = e.path, start_line = s, end_line = last, body = e.body, valid = last >= s }
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  return out
end

local function virt(lines)
  return vim.tbl_map(function(line)
    return { { line, 'ReviewerBody' } }
  end, lines)
end

local function redraw(buf)
  if not api.nvim_buf_is_loaded(buf) then
    return
  end
  api.nvim_buf_clear_namespace(buf, decor_ns, 0, -1)
  local path = api.nvim_buf_get_name(buf)
  for _, c in ipairs(M.list()) do
    if c.valid and c.path == path then
      for lnum = c.start_line, c.end_line do
        api.nvim_buf_set_extmark(buf, decor_ns, lnum - 1, 0, { sign_text = '▍', sign_hl_group = 'ReviewerSign' })
      end
      api.nvim_buf_set_extmark(buf, decor_ns, c.start_line - 1, 0, { virt_lines = virt { '>>>>>>> review' }, virt_lines_above = true })
      local below = vim.list_extend({ '=======' }, vim.split(c.body, '\n'))
      below[#below + 1] = '<<<<<<<'
      api.nvim_buf_set_extmark(buf, decor_ns, c.end_line - 1, 0, { virt_lines = virt(below) })
    end
  end
end

function M.add(buf, start_line, end_line, body)
  local e = { id = next_id, path = api.nvim_buf_get_name(buf), start_line = start_line, end_line = end_line, body = body }
  next_id = next_id + 1
  entries[e.id] = e
  anchor(e, buf)
  redraw(buf)
  return e.id
end

function M.at(buf, lnum)
  local path = api.nvim_buf_get_name(buf)
  return vim.tbl_filter(function(c)
    return c.valid and c.path == path and c.start_line <= lnum and lnum <= c.end_line
  end, M.list())
end

function M.update(id, body)
  local e = entries[id]
  if not e then
    return
  end
  e.body = body
  if e.anchor then
    redraw(e.anchor.buf)
  end
end

function M.remove(id)
  local e = entries[id]
  if not e then
    return
  end
  entries[id] = nil
  if e.anchor then
    api.nvim_buf_del_extmark(e.anchor.buf, anchor_ns, e.anchor.id)
    redraw(e.anchor.buf)
  end
end

local function highlights()
  api.nvim_set_hl(0, 'ReviewerSign', { link = 'DiagnosticInfo', default = true })
  api.nvim_set_hl(0, 'ReviewerBody', { link = 'DiagnosticWarn', default = true })
end
highlights()

local group = api.nvim_create_augroup('reviewer', { clear = true })
api.nvim_create_autocmd('ColorScheme', { group = group, callback = highlights })
api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
  group = group,
  callback = function(ev)
    redraw(ev.buf)
  end,
})
api.nvim_create_autocmd('BufUnload', {
  group = group,
  callback = function(ev)
    for _, e in pairs(entries) do
      if e.anchor and e.anchor.buf == ev.buf then
        e.start_line, e.end_line = range(e)
        api.nvim_buf_del_extmark(ev.buf, anchor_ns, e.anchor.id)
        e.anchor = nil
      end
    end
  end,
})
api.nvim_create_autocmd('BufReadPost', {
  group = group,
  callback = function(ev)
    local path = api.nvim_buf_get_name(ev.buf)
    for _, e in pairs(entries) do
      if not e.anchor and e.path == path then
        anchor(e, ev.buf)
      end
    end
    redraw(ev.buf)
  end,
})

return M
