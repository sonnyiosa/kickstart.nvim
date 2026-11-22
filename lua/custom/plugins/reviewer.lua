local prefix = '<leader>a'

return {
  dir = vim.fn.stdpath 'config' .. '/plugins/reviewer.nvim',
  name = 'reviewer',
  cmd = { 'ReviewAdd', 'ReviewEdit', 'ReviewDelete', 'ReviewSubmit' },
  keys = {
    { prefix .. 'a', ':ReviewAdd<CR>', mode = 'x', desc = 'Review: [a]dd comment on selection' },
    { prefix .. 'e', '<Cmd>ReviewEdit<CR>', mode = 'n', desc = 'Review: [e]dit comment' },
    { prefix .. 'd', '<Cmd>ReviewDelete<CR>', mode = 'n', desc = 'Review: [d]elete comment' },
    { prefix .. 's', '<Cmd>ReviewSubmit<CR>', mode = 'n', desc = 'Review: [s]ubmit comments' },
  },
  opts = {},
  config = function(_, opts)
    local reviewer = require 'reviewer'
    reviewer.setup(opts)
    if vim.fn.executable 'hc' == 1 then
      reviewer.register_provider(require 'reviewer.providers.herdr_core')
    end
  end,
}
