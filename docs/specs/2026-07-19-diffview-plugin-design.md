# Diffview.nvim Plugin Design

## Goal

Add `sindrets/diffview.nvim` to the Neovim configuration while keeping the existing `vscode-diff.nvim` plugin available for comparison.

## Configuration

Create `lua/custom/plugins/diffview.lua` containing a lazy.nvim plugin specification for `sindrets/diffview.nvim`.

The plugin will lazy-load through these command and key triggers:

- `<leader>gh` invokes `:DiffviewFileHistory`.
- `<leader>gd` invokes `:DiffviewOpen`.
- `DiffviewFileHistory` and `DiffviewOpen` remain valid manual command triggers.

No startup event or eager setup call will be added. The existing `lua/custom/plugins/code_diff.lua` file will remain unchanged.

## Verification

- Confirm the new spec is imported through the existing `custom.plugins` import.
- Run a headless Neovim startup check to ensure the configuration parses.
- Confirm lazy.nvim recognizes the diffview plugin and both key triggers.

## Architectural Decisions

- **Use a separate `lua/custom/plugins/diffview.lua` spec:** This follows the repository's modular custom-plugin convention and avoids changing the existing comparison plugin.
- **Use lazy.nvim `keys` and `cmd` triggers:** This prevents diffview from loading at startup while supporting both requested mappings and manual command use.
- **Keep `vscode-diff.nvim` installed:** The user explicitly requested coexistence for comparison, so replacing or disabling it is out of scope.
- **Avoid custom diffview options initially:** A minimal default configuration provides a fair comparison and avoids introducing unrelated behavior.
