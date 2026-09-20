return {
  'sindrets/diffview.nvim',
  cmd = { 'DiffviewOpen', 'DiffviewFileHistory' },
  keys = {
    { '<leader>gh', '<cmd>DiffviewFileHistory<cr>', desc = 'Git file history' },
    { '<leader>gd', '<cmd>DiffviewOpen<cr>', desc = 'Git diff view' },
  },
}
