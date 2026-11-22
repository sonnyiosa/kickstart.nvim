# Diffview.nvim Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `sindrets/diffview.nvim` as a lazily loaded custom plugin while keeping `vscode-diff.nvim` installed for comparison.

**Architecture:** Add one independent lazy.nvim plugin specification under `lua/custom/plugins`. Use `cmd` triggers for manual command invocation and `keys` triggers for the requested mappings, with no startup event or eager configuration. The existing `custom.plugins` import in `init.lua` discovers the new file automatically.

**Tech Stack:** Neovim Lua, lazy.nvim, diffview.nvim.

## Global Constraints

- Keep `lua/custom/plugins/code_diff.lua` unchanged so `vscode-diff.nvim` remains available for comparison.
- Store the new plugin configuration under `lua/custom/plugins`.
- Load diffview only through its commands or requested key mappings; do not add an eager startup event.
- Map `<leader>gh` to `:DiffviewFileHistory`.
- Map `<leader>gd` to `:DiffviewOpen`.
- Do not add diffview options beyond the default configuration.
- Do not create a git commit unless the user explicitly requests one.

---

### Task 1: Add the lazy-loaded diffview plugin specification

**Files:**
- Create: `lua/custom/plugins/diffview.lua`
- Preserve: `lua/custom/plugins/code_diff.lua`

**Interfaces:**
- Consumes: The existing `{ import = 'custom.plugins' }` entry in `init.lua:1179`, which automatically imports Lua plugin specs from this directory.
- Produces: A lazy.nvim plugin spec for `sindrets/diffview.nvim` with command triggers and the two requested normal-mode key mappings.

- [ ] **Step 1: Create the plugin spec**

Write `lua/custom/plugins/diffview.lua` with exactly this configuration:

```lua
return {
  'sindrets/diffview.nvim',
  cmd = { 'DiffviewOpen', 'DiffviewFileHistory' },
  keys = {
    { '<leader>gh', '<cmd>DiffviewFileHistory<cr>', desc = 'Git file history' },
    { '<leader>gd', '<cmd>DiffviewOpen<cr>', desc = 'Git diff view' },
  },
}
```

The `cmd` entries let manually typed commands trigger loading, while the `keys` entries let lazy.nvim install the mappings without loading diffview during startup. Do not add `event`, `config`, or changes to `code_diff.lua`.

- [ ] **Step 2: Check the declarative configuration parses**

Run:

```bash
nvim --headless '+lua assert(loadfile("lua/custom/plugins/diffview.lua"))' +qa
```

Expected: Neovim exits successfully with no Lua syntax error.

- [ ] **Step 3: Install and synchronize the plugin through lazy.nvim**

Run:

```bash
nvim --headless '+Lazy! sync' +qa
```

Expected: lazy.nvim clones or updates `sindrets/diffview.nvim` and exits successfully. The existing `vscode-diff.nvim` installation remains untouched.

- [ ] **Step 4: Verify the plugin spec and command triggers are registered**

Run:

```bash
nvim --headless '+lua local p = require("lazy").plugins()["diffview.nvim"]; assert(p ~= nil, "diffview.nvim spec not registered")' '+lua assert(vim.fn.exists(":DiffviewOpen") == 2, "DiffviewOpen command trigger missing")' '+lua assert(vim.fn.exists(":DiffviewFileHistory") == 2, "DiffviewFileHistory command trigger missing")' +qa
```

Expected: Neovim exits successfully, proving the imported spec is registered and lazy.nvim exposes both command triggers without requiring startup loading.

- [ ] **Step 5: Verify the requested mappings are present**

Run:

```bash
nvim --headless '+lua local gd = vim.fn.maparg(" gd", "n", false, true); local gh = vim.fn.maparg(" gh", "n", false, true); assert(gd.rhs == "<cmd>DiffviewOpen<cr>", "<leader>gd mapping missing"); assert(gh.rhs == "<cmd>DiffviewFileHistory<cr>", "<leader>gh mapping missing")' +qa
```

Expected: Neovim exits successfully using the default `<Space>` leader, confirming `<leader>gd` and `<leader>gh` point to the requested commands. If the configuration changes the leader before plugin setup, substitute the configured leader character in the two `maparg` lookups without changing the plugin spec.

## Self-review

- **Spec coverage:** The plan preserves `vscode-diff.nvim`, creates the requested file under `lua/custom/plugins`, uses lazy command and key triggers, adds both mappings, avoids eager loading and extra options, installs the plugin, and verifies registration and mappings.
- **Placeholder scan:** No TBD, TODO, or unspecified implementation steps remain.
- **Type and name consistency:** The repository key names, command names, plugin name, and file paths are consistent across all steps.
