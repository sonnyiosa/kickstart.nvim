local api = vim.api
local M = {}

---@param opts { title: string, body: string, on_save: fun(body: string), on_cancel?: fun(), width?: integer, height?: integer }
function M.open(opts)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(buf, 'reviewer://' .. buf)
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'
  api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.body, '\n'))
  vim.bo[buf].modified = false

  local width = opts.width or math.min(80, math.floor(vim.o.columns * 0.6))
  local height = opts.height or math.min(12, math.floor(vim.o.lines * 0.4))
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    border = 'rounded',
    title = ' ' .. opts.title .. ' ',
    title_pos = 'center',
  })

  local function close()
    if api.nvim_win_is_valid(win) then
      api.nvim_win_close(win, true)
    end
  end

  local saved = false
  api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local body = vim.trim(table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
      vim.bo[buf].modified = false
      saved = body ~= ''
      -- :wq and :x close the current window after the write; close it here and they close the main one.
      -- on_save runs after the close, so a window that on_save opens keeps the focus.
      vim.schedule(function()
        close()
        if saved then
          opts.on_save(body)
        end
      end)
    end,
  })
  api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      if not saved and opts.on_cancel then
        opts.on_cancel()
      end
    end,
  })
  vim.keymap.set('n', '<CR>', '<Cmd>write<CR>', { buffer = buf })
  vim.keymap.set('n', 'q', close, { buffer = buf })
  vim.keymap.set('n', '<Esc>', close, { buffer = buf })
end

return M
