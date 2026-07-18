# fff.nvim + Telescope Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace three Telescope search mappings (`<leader>ff`, `<leader>fg`, `<leader>fw`) with fff.nvim equivalents and add `F` in NeoTree to search files inside a focused directory.

**Architecture:** Add `dmtrKovalenko/fff.nvim` as a standalone lazy.nvim entry in `init.lua` with its binary download build hook. Replace the three approved mappings inside the existing Telescope config block with fff.nvim callbacks. Add a `fff_search_in_dir` custom command and `F` window mapping to the NeoTree plugin file, directory-nodes only.

**Tech Stack:** Neovim (Lua), lazy.nvim, fff.nvim (`dmtrKovalenko/fff.nvim`), nvim-neo-tree.

## Global Constraints

- Touch only the three approved mappings (`<leader>ff`, `<leader>fg`, `<leader>fw`) in `init.lua` — every other Telescope mapping, the full Telescope plugin spec, its extensions, and `lua/custom/plugins/grep-telescope.lua` remain unchanged.
- fff.nvim must be declared with `lazy = false` and the `build` function `require('fff.download').download_or_build_binary()`.
- `<leader>fw` must be registered for both `'n'` and `'x'` (visual) modes.
- NeoTree's `fff_search_in_dir` command must return immediately for non-directory nodes — no fallback to parent directory.
- No new files. Modify only `init.lua` and `lua/custom/plugins/neo-tree.lua`.

---

## File Map

| File | Change |
|------|--------|
| `init.lua` | Add fff.nvim plugin spec after Telescope block (line ~602); replace 3 mappings at lines 564, 566, 567 |
| `lua/custom/plugins/neo-tree.lua` | Add `fff_search_in_dir` to `filesystem.commands`; add `['F']` to `filesystem.window.mappings` |

---

### Task 1: Add fff.nvim plugin spec and replace three search mappings in `init.lua`

**Files:**
- Modify: `init.lua:564`, `init.lua:566-567`, `init.lua:602` (insertion after)

**Interfaces:**
- Produces: `require('fff').find_files()`, `require('fff').live_grep()`, `require('fff').live_grep_under_cursor()` — callable from Task 2's NeoTree file as well.

- [ ] **Step 1: Insert the fff.nvim plugin spec after the Telescope block**

In `init.lua`, after line 602 (the closing `},` of the Telescope plugin entry, just before the `-- LSP Plugins` comment), insert:

```lua
  { -- Fast file finder and live grep with frecency ranking
    'dmtrKovalenko/fff.nvim',
    build = function()
      require('fff.download').download_or_build_binary()
    end,
    lazy = false,
  },
```

The surrounding context in `init.lua` looks like this so you can find the right spot:

```lua
      vim.keymap.set('n', '<leader>gt', ':Telescope git_file_history<CR>', { desc = '[g]it [t]imeline' })
      vim.keymap.set('n', '<leader>gs', ':codediff<CR>', { desc = '[g]it [s]tatus' })
      vim.keymap.set('n', '<leader>gl', ':codediff file HEAD<CR>', { desc = '[g]it diff [l]ast commit' })
    end,
  },              -- <-- end of Telescope block, insert fff spec AFTER this line

  -- LSP Plugins
```

- [ ] **Step 2: Replace the `<leader>ff` mapping**

Find and replace this exact line in `init.lua`:

```lua
      vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = '[S]earch [F]iles' })
```

Replace with:

```lua
      vim.keymap.set('n', '<leader>ff', function() require('fff').find_files() end, { desc = '[S]earch [F]iles' })
```

- [ ] **Step 3: Replace the `<leader>fw` mapping**

Find and replace this exact line in `init.lua`:

```lua
      vim.keymap.set('n', '<leader>fw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
```

Replace with:

```lua
      vim.keymap.set({ 'n', 'x' }, '<leader>fw', function() require('fff').live_grep_under_cursor() end, { desc = '[S]earch current [W]ord' })
```

- [ ] **Step 4: Replace the `<leader>fg` mapping**

Find and replace this exact line in `init.lua`:

```lua
      vim.keymap.set('n', '<leader>fg', ":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>", { desc = '[S]earch by [G]rep' })
```

Replace with:

```lua
      vim.keymap.set('n', '<leader>fg', function() require('fff').live_grep() end, { desc = '[S]earch by [G]rep' })
```

- [ ] **Step 5: Verify the diff is surgical**

Run:
```bash
git diff init.lua
```

Expected: diff shows exactly 4 hunks — one new plugin spec block (~6 lines added) and three one-line mapping replacements. No Telescope spec lines, no extension lines, no other mappings changed.

- [ ] **Step 6: Check Lua syntax**

Run:
```bash
nvim --headless -c "lua print('ok')" -c "qa!" 2>&1
```

Expected: either no output (clean) or only `ok` — no Lua errors, no `E5108`, no plugin-spec warnings.

- [ ] **Step 7: Commit**

```bash
git add init.lua
git commit -m "feat: add fff.nvim and replace ff/fg/fw telescope mappings"
```

---

### Task 2: Add `fff_search_in_dir` command and `F` mapping to NeoTree

**Files:**
- Modify: `lua/custom/plugins/neo-tree.lua:60-79`

**Interfaces:**
- Consumes: `require('fff').find_files_in_dir(path: string)` — introduced by Task 1's fff.nvim installation.
- Produces: NeoTree command `fff_search_in_dir` bound to `F` in the filesystem window.

- [ ] **Step 1: Add `['F'] = 'fff_search_in_dir'` to the window mappings table**

In `lua/custom/plugins/neo-tree.lua`, find the `mappings` table inside `filesystem.window`:

```lua
        mappings = {
          ['\\'] = 'close_window',
          ['Y'] = copy_path,
          ['O'] = 'system_open',
        },
```

Add the new mapping so it becomes:

```lua
        mappings = {
          ['\\'] = 'close_window',
          ['Y'] = copy_path,
          ['O'] = 'system_open',
          ['F'] = 'fff_search_in_dir',
        },
```

- [ ] **Step 2: Add the `fff_search_in_dir` command under `filesystem.commands`**

In the same file, find the `commands` table inside `filesystem`:

```lua
      commands = {
        system_open = function(state)
          local node = state.tree:get_node()
          local path = node:get_id()

          -- vim.ui.open works natively on Neovim 0.10+ for Windows, macOS, and Linux
          vim.ui.open(path)
        end,
      },
```

Add the new command so it becomes:

```lua
      commands = {
        system_open = function(state)
          local node = state.tree:get_node()
          local path = node:get_id()

          -- vim.ui.open works natively on Neovim 0.10+ for Windows, macOS, and Linux
          vim.ui.open(path)
        end,
        fff_search_in_dir = function(state)
          local node = state.tree:get_node()
          if node.type ~= 'directory' then return end
          require('fff').find_files_in_dir(node:get_id())
        end,
      },
```

- [ ] **Step 3: Verify the diff is surgical**

Run:
```bash
git diff lua/custom/plugins/neo-tree.lua
```

Expected: diff shows exactly 2 hunks — one line added to `mappings` and one new function added to `commands`. No other lines in the file changed.

- [ ] **Step 4: Check Lua syntax**

Run:
```bash
nvim --headless -c "lua print('ok')" -c "qa!" 2>&1
```

Expected: clean output with no errors.

- [ ] **Step 5: Commit**

```bash
git add lua/custom/plugins/neo-tree.lua
git commit -m "feat(neotree): add F mapping to search files in directory with fff"
```

---

## Post-Implementation Verification Checklist

Run these after both commits to confirm the full spec is met:

- [ ] `git log --oneline -3` shows both commits with correct messages.
- [ ] `git diff HEAD~2` shows only the changes described in this plan — no Telescope spec lines removed, no other mappings touched.
- [ ] Start Neovim normally: confirm no startup errors in the messages area.
- [ ] Press `<leader>ff` — fff.nvim file picker opens (not Telescope).
- [ ] Press `<leader>fg` — fff.nvim live grep opens (not Telescope's live-grep-args popup).
- [ ] Press `<leader>fw` in normal mode over a word — fff.nvim live grep under cursor opens.
- [ ] Select text in visual mode, press `<leader>fw` — fff.nvim grep under selection opens.
- [ ] Press `<leader>fk` — Telescope keymaps picker opens (unchanged).
- [ ] Press `<leader>fd` — Telescope diagnostics picker opens (unchanged).
- [ ] Press `<leader>fr` — Telescope resume works (unchanged).
- [ ] Press `<leader>f.` — Telescope oldfiles opens (unchanged).
- [ ] Press `<leader>fe` — Telescope buffers opens (unchanged).
- [ ] Press `<leader>F` — Telescope current-buffer fuzzy find opens (unchanged).
- [ ] Press `<leader>fn` — Telescope Neovim config search opens (unchanged).
- [ ] Run `:FFFHealth` — reports healthy (once fff.nvim binary is downloaded).
- [ ] Open NeoTree (`\`), focus a **directory** node, press `F` — fff.nvim picker opens at that directory's path.
- [ ] In NeoTree, focus a **file** node, press `F` — nothing happens (silent no-op).
