# fff.nvim and Telescope Search Design

## Goal

Replace the three core Telescope search mappings with `dmtrKovalenko/fff.nvim` while preserving Telescope functions that fff.nvim does not provide.

## Scope

The migration changes only these mappings:

- `<leader>ff`: Telescope `find_files` → `require('fff').find_files()`
- `<leader>fg`: Telescope live-grep-args → `require('fff').live_grep()`
- `<leader>fw`: Telescope `grep_string` → `require('fff').live_grep_under_cursor()`

The `<leader>fw` mapping will be available in normal and visual modes, matching fff.nvim's cursor/selection behavior.

All other existing Telescope mappings remain unchanged, including:

- keymaps, Telescope picker selection, diagnostics, resume, old files, and buffers
- current-buffer fuzzy search (`<leader>F`)
- live grep in open files (`<leader>f/`)
- Neovim configuration search (`<leader>fn`)
- git file history

## Architecture

Add fff.nvim as a standalone lazy.nvim plugin entry in `init.lua` alongside the existing Telescope specification:

```lua
{
  'dmtrKovalenko/fff.nvim',
  build = function()
    require('fff.download').download_or_build_binary()
  end,
  lazy = false,
}
```

The existing Telescope plugin, dependencies, setup, extensions, and unsupported picker mappings remain in place. The fff mappings are defined in the existing search keymap block so the keybinding organization remains familiar.

No runtime fallback wrapper is needed. Unsupported behavior is preserved by leaving its Telescope mapping intact, while supported behavior is explicitly assigned to fff.nvim.

## Runtime Behavior

When Neovim starts, lazy.nvim installs or updates fff.nvim and runs its documented binary build/download hook. fff.nvim is loaded non-lazily and self-initializes through its module.

The three migrated mappings use fff.nvim's native picker UI, indexing, and frecency behavior. Telescope's live-grep-args configuration remains available to Telescope callers, but `<leader>fg` no longer invokes the live-grep-args extension.

## NeoTree Integration

Add a custom command to `lua/custom/plugins/neo-tree.lua` under `filesystem.commands` that calls `require('fff').find_files_in_dir(path)` with the selected node's path, guarded so it only activates when the node is a directory. For file nodes the command is a no-op (does nothing).

Map this command to `F` (uppercase) inside `filesystem.window.mappings`, following the same pattern already used for `system_open` and `copy_path`.

```lua
commands = {
  fff_search_in_dir = function(state)
    local node = state.tree:get_node()
    if node.type ~= 'directory' then return end
    require('fff').find_files_in_dir(node:get_id())
  end,
}
-- window.mappings
['F'] = 'fff_search_in_dir',
```

## Validation

1. Parse the edited Lua and inspect the lazy.nvim specification for the exact fff.nvim repository, build hook, and `lazy = false`.
2. Start Neovim headlessly with the configuration to catch startup or plugin-spec errors.
3. Inspect keymaps to verify `<leader>ff`, `<leader>fg`, and `<leader>fw` resolve to fff.nvim, with `<leader>fw` present in normal and visual modes.
4. Confirm unsupported mappings still resolve to Telescope functions.
5. Run `:FFFHealth` when fff.nvim is installed and available.
6. Review the final diff to confirm Telescope-only dependencies and mappings were not removed unintentionally.
7. Open NeoTree, focus a directory node, press `F`, and verify fff's picker opens at that path. Focus a file node and verify `F` does nothing.

## Architectural Decisions

### Use a standalone fff.nvim plugin declaration

Add fff.nvim as its own lazy.nvim entry instead of merging it into the Telescope declaration. This keeps each plugin's lifecycle and configuration independent and avoids coupling fff's build/install requirements to Telescope. A separate custom plugin file was rejected because the current Telescope mappings are centralized in `init.lua`, and moving only part of that block would create unnecessary split ownership.

### Replace only the three core mappings

Move file finding, live grep, and cursor/selection grep because fff.nvim provides direct equivalents. Preserve every other Telescope mapping because fff.nvim does not provide equivalent APIs for buffers, old files, diagnostics, resume, keymaps, current-buffer fuzzy search, or open-file-only grep. Replacing the entire Telescope declaration was rejected because it would risk unrelated extensions and Telescope-only functionality.

### Use direct fff callbacks without a fallback dispatcher

Call fff.nvim APIs directly from the three mappings and leave unsupported mappings on Telescope. A runtime capability check or fallback dispatcher was rejected because plugin availability is controlled by the same lazy.nvim configuration, and structural preservation is simpler and easier to verify.

### NeoTree: directory-only guard and `F` key

The `fff_search_in_dir` command returns early for file nodes rather than falling back to parent-directory search. This is the simplest behavior that avoids surprising side-effects when the user is focused on a file. The `F` key was chosen by the user as the NeoTree-local trigger; it does not conflict with NeoTree's built-in bindings and mirrors the uppercase `<leader>F` pattern already used in the global buffer-search mapping.

### Keep `<leader>fg` on standard fff live grep

Use `require('fff').live_grep()` rather than attempting to reproduce Telescope-live-grep-args's custom prompt actions. The user requested fff for the core grep mapping, while the Telescope extension and its advanced mappings remain available for callers that need those features.
