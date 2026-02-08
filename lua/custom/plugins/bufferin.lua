return {
  'wasabeef/bufferin.nvim',
  cmd = { 'Bufferin' },
  config = function()
    require('bufferin').setup()
  end,
  -- Optional dependencies for enhanced experience
  dependencies = {
    'nvim-tree/nvim-web-devicons', -- For file icons
    -- 'willothy/nvim-cokeline',     -- For buffer line integration
    -- 'akinsho/bufferline.nvim',    -- Alternative buffer line
  },
}
