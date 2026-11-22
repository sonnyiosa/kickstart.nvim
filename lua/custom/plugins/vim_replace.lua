return {
  'chrisgrieser/nvim-rip-substitute',
  cmd = 'RipSubstitute',
  opts = {},
  keys = {
    {
      '<leader>rs',
      function()
        require('rip-substitute').sub()
      end,
      mode = { 'n', 'x' },
      desc = ' rip substitute',
    },
    {
      '<leader>rl',
      function()
        vim.cmd '.,$RipSubstitute'
      end,
      mode = 'n',
      desc = ' rip substitute from cursor line to EOF',
    },
  },
}
