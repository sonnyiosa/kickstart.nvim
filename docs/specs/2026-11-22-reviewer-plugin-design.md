# Reviewer Plugin Design

## Goal

Add a local Neovim plugin, `reviewer`, for code review in the editor. The user selects a range of lines in the current file and attaches a comment to it. The user can add, edit, and remove comments. Then the user submits all comments to an external coding agent.

The plugin defines a provider interface for coding agents. This spec defines no concrete provider.

## Terms

- **Comment**: a text body that the user attaches to a range of lines in one file.
- **Review**: the set of all comments that the user did not submit yet. One review exists for each Neovim session.
- **Provider**: a Lua table that sends a payload to one coding agent.
- **Payload**: the data that the plugin gives to a provider at submit time.
- **Anchor**: the extmark that holds the current line range of a comment in a loaded buffer.

## Scope

In scope:

- Add a comment on a visual line selection in the current buffer.
- Edit the body of a comment at the cursor.
- Remove a comment at the cursor.
- Show comments in the buffer.
- Submit the review to one provider.
- Register providers through a public Lua function.

Out of scope:

- Concrete providers (for example, Claude Code or Codex).
- Persistence across Neovim sessions.
- Comment threads, replies, or resolved state.
- Character-level (column) ranges. Ranges are full lines.
- A list or picker of all comments.

## File Layout

The plugin is a self-contained folder in `plugins/` at the config root, so it can move to its own repository later without changes.

```
plugins/reviewer.nvim/
  lua/reviewer/
    init.lua      -- setup(), commands, keymaps, provider registry, submit
    comments.lua  -- review model, anchors, rendering
    editor.lua    -- floating window that edits a comment body and the submit preview
    providers/
      herdr_core.lua  -- sends the review to a coding agent through `hc`
  tests/
    run.lua       -- headless behavior tests
lua/custom/plugins/reviewer.lua  -- lazy.nvim spec with `dir`
```

`lua/custom/plugins/reviewer.lua` returns this spec:

```lua
return {
  dir = vim.fn.stdpath('config') .. '/plugins/reviewer.nvim',
  name = 'reviewer',
  cmd = { 'ReviewAdd', 'ReviewEdit', 'ReviewDelete', 'ReviewSubmit' },
  keys = { --[[ see Keymaps ]] },
  opts = {},
}
```

## Data Model

```lua
---@class reviewer.Comment
---@field id integer            -- unique in the session, never reused
---@field path string           -- absolute file path
---@field start_line integer    -- 1-based, inclusive
---@field end_line integer      -- 1-based, inclusive
---@field body string           -- Markdown text, never empty

---@class reviewer.PayloadComment
---@field path string
---@field start_line integer
---@field end_line integer
---@field filetype string
---@field code string           -- buffer text of the range at submit time
---@field body string

---@class reviewer.Payload
---@field root string           -- current working directory at submit time
---@field comments reviewer.PayloadComment[]  -- sorted by path, then start_line
---@field message string        -- the preview text that the user saved (see Submit)

---@class reviewer.Provider
---@field name string           -- unique key in the registry
---@field submit fun(payload: reviewer.Payload, done: fun(err?: string))
```

The review is a map from `id` to `reviewer.Comment`. `comments.lua` owns this map. No other module writes to it.

### Range ownership

A comment range has exactly one owner at a time:

- **The buffer is loaded.** The anchor owns the range. `start_line` and `end_line` in the map are stale and the plugin does not read them.

The anchor is a half-open line range. It starts at column 0 of the first line and ends at column 0 of the line after the last line, with `end_right_gravity = false` and `undo_restore = true`. With this shape, Neovim moves the anchor on line inserts and line deletes:

- A line that the user inserts above the range moves the range down.
- A line that the user inserts inside the range makes the range longer.
- A line that the user inserts directly below the range stays outside the range.
- A delete of some lines in the range makes the range shorter.
- **The buffer is not loaded.** `start_line` and `end_line` in the map own the range.

The plugin moves ownership at two events:

1. On `BufUnload`, the plugin reads each anchor of the buffer and writes the range to the map.
2. On `BufReadPost`, the plugin creates an anchor for each comment whose `path` matches the buffer and that has no live anchor in it. Neovim keeps extmarks after `:bunload` and `:edit!`, so this check stops duplicate anchors.

`comments.lua` exposes one read function, `comments.list()`. It returns each comment with its current range, whichever owner holds it, and a `valid` flag (see Deleted code). All other code uses this function and never reads anchors directly.

### Deleted code

When the user deletes all lines of a comment range, the anchor start and the anchor end move to the same position. The plugin treats an anchor with no lines as a deleted comment. It hides the comment and leaves it out of the payload. Undo restores the lines and the anchor, so the comment comes back.

The plugin does not use the extmark `invalidate` option. In Neovim 0.11.4, a line delete of exactly the range lines does not set `invalid` on a line-range extmark.

## User Interface

### Commands

| Command | Mode | Action |
| --- | --- | --- |
| `:ReviewAdd` | range | Opens the editor with an empty body. Save adds a comment on the range. |
| `:ReviewEdit` | normal | Opens the editor with the body of the comment at the cursor. |
| `:ReviewDelete` | normal | Removes the comment at the cursor. |
| `:ReviewSubmit` | normal | Sends all comments in the review to a provider. |

"The comment at the cursor" is a comment whose range contains the cursor line. If more than one comment contains the cursor line, the plugin asks the user to pick one with `vim.ui.select`. If no comment contains the cursor line, the plugin shows a warning and does nothing.

`:ReviewAdd` works only in a buffer that has a file path. In other buffers it shows a warning.

### Keymaps

All review keymaps use one prefix, `<leader>a`. The prefix is not in use in this config. `lua/custom/plugins/reviewer.lua` defines the prefix in one local variable, `prefix`, and makes the four `keys` entries from it. Each entry has a `desc`.

The which-key spec list in `init.lua` declares the prefix as the group `[a]gent review` for modes `n` and `x`. When the user types `<leader>a`, the which-key popup shows this group with its four keys.

| Keys | Mode | Command |
| --- | --- | --- |
| `<leader>aa` | visual | `:ReviewAdd` on the selected lines |
| `<leader>ae` | normal | `:ReviewEdit` |
| `<leader>ad` | normal | `:ReviewDelete` |
| `<leader>as` | normal | `:ReviewSubmit` |

### Editor

The editor is a floating window with a buffer of filetype `markdown` and `buftype=acwrite`. A `BufWriteCmd` handler does the save. The window title shows the file name and the line range.

- `<CR>` in normal mode and `:w` save the body and close the window.
- `q` and `<Esc>` in normal mode close the window without a save.
- The plugin trims the body before the save. An empty body on add cancels the add. An empty body on edit keeps the old body.

### Display

For each valid anchor, the plugin shows:

- A sign (`▍`) in the sign column on each line of the range.
- Markers that wrap the range and the body, in the shape of a git conflict block:

  ```
  >>>>>>> review      <- virtual line above the first line of the range
  <lines of the range>
  =======             <- virtual lines below the last line of the range
  <comment body>
  <<<<<<<
  ```

The markers and the body use the `ReviewerBody` highlight group, which shows as yellow text.

The plugin draws these marks in a second namespace that is separate from the anchors. After each comment change and on `TextChanged` and `TextChangedI`, it clears that namespace in the buffer and draws the marks again from `comments.list()`.

The plugin defines its own highlight groups and links them to existing groups, so color schemes can change them:

- `ReviewerSign` links to `DiagnosticInfo`.
- `ReviewerBody` links to `DiagnosticWarn` (yellow).

Known limit: when a range starts on line 1, Neovim shows the `>>>>>>> review` marker only after the user scrolls up (for example with `<C-y>`).

## Submit

`:ReviewSubmit` runs these steps:

1. If a submit is in progress, show a warning and stop.
2. Call `comments.list()` and keep the valid comments. If there are none, show a warning and stop.
3. Build the payload. Read `code` from the loaded buffer, or from the file on disk if the buffer is not loaded.
4. Choose the provider:
   - If `opts.provider` names a registered provider, use it.
   - If exactly one provider is registered, use it.
   - If more than one provider is registered, ask with `vim.ui.select`.
   - If no provider is registered, show an error and stop.
5. Set the submit state to `submitting`. Open the preview (see below).
   - If the user saves the preview, set `payload.message` to the saved text.
   - If the user closes the preview without a save, or saves an empty text, set the state to `idle`, keep all comments, and show `submit cancelled`.
6. After the preview window closes, call `provider.submit(payload, done)`.
7. When the provider calls `done()` with no error, remove the submitted comments from the review and show a success message.
8. When the provider calls `done(err)`, keep all comments and show `err` as an error.

The submit state is `idle` or `submitting`. A provider may call `done` synchronously or later. The plugin wraps `done` with `vim.schedule` and ignores a second call.

### Preview

The preview is the same floating editor as the comment editor, with the title `Review → <provider name>` and a larger size. All providers get it. It shows the full message that the plugin sends:

````
Review comments for <root>. Address each one.

## Notes

<empty line for the user's notes>

## <path relative to root>:<start_line>-<end_line>

```<filetype>
<code>
```

<body>
````

- The user can change any part of the text. The saved text is `payload.message`. `payload.comments` does not change.
- If the Notes section is empty at the save, the plugin removes its heading from the message.
- The path is relative to `root` when the file is under `root`. Else it is the absolute path.

## Providers

### herdr-core

`reviewer/providers/herdr_core.lua` sends the review to a running coding agent through the herdr-core CLI, `hc`. `lua/custom/plugins/reviewer.lua` registers it when the `hc` executable is on `PATH`.

`submit(payload, done)` runs these steps:

1. Read `hc ls --json`. Keep the live terminals that report an agent status (the `status` field). Shells and plain programs have no status, so the list does not show them. If `hc ls` fails, call `done('hc ls failed')`. If the list is empty, call `done('no running coding agent')`.
2. Sort the agents:
   1. The active agent of the current herdr-app space (`agent` in `herdr-app status`), marked `(active)`.
   2. The other agents in that space (from `herdr-app ls`).
   3. All other agents.

   In each group, the order is by address. If `herdr-app` is not available, the order is by address only.
3. Read the title of each agent with `hc get <address> --json` (`title` field). `hc ls` does not give the title. The plugin runs these calls at the same time. An agent with no title or a failed call shows no title.
4. Ask with `vim.ui.select` (prompt `Send review to`). Each item shows the name or address, `(active)` for the active agent, the title, the agent, the `where` label or the folder, and the status. Example: `t1kv (active)  herdr-core provider implementation  claude-code  nvim / 1  working`. If the user picks no agent, call `done('no agent selected')`.
5. Run `hc send <address> <payload.message>` without a block of the editor. On exit code 0, call `done()`. Else call `done` with the `error.message` from the JSON on stderr.

Comments that the user adds while a submit is in progress stay in the review after success, because step 6 removes only the comments in the payload.

## Public API

```lua
local reviewer = require('reviewer')

reviewer.setup(opts)                 -- opts.provider?: string
reviewer.register_provider(provider) -- error if provider.name is already registered
```

## Verification

`plugins/reviewer.nvim/tests/run.lua` runs with `nvim --headless -l plugins/reviewer.nvim/tests/run.lua` and exits with a non-zero code on a failure. It checks these behaviors through the commands and the public API:

- An add on lines 3 to 5 gives a comment with that range and body.
- An insert of two lines above the comment moves the range to lines 5 to 7.
- A delete of all lines in the range leaves the comment out of the payload. Undo brings it back.
- An unload and a reload of the buffer keep the comment and its range.
- An edit changes the body. An empty body on edit keeps the old body.
- A delete removes the comment and its signs.
- A submit to a fake provider gives the expected payload, then empties the review.
- A provider that calls `done('boom')` keeps all comments.
- A second submit during a pending submit does not call the provider.

Also run a headless startup check of the full config and check that lazy.nvim registers `reviewer` with its commands and keys.

## Architectural Decisions

- **Ship as a local plugin folder loaded with lazy.nvim `dir`.** The plugin follows the `lua/custom/plugins` convention of this config and can move to its own repository with no code change.
- **Use extmarks as the range owner while the buffer is loaded.** Neovim moves extmarks on each edit, so the plugin needs no `TextChanged` handler to keep ranges correct.
- **Move range ownership at `BufUnload` and `BufReadPost`.** Comments survive when the user closes and opens a file, and each range has one owner at a time.
- **Keep one review for all files.** Commands act on the current buffer, and submit sends every comment, so one submit covers a review that spans several files.
- **Put `code` in each payload comment.** The buffer can have unsaved changes, so line numbers alone can point to the wrong text on disk.
- **Use an asynchronous provider contract with one `done` callback.** Agents run as external processes or network calls. A single callback serves both sync and async providers.
- **Remove comments only after a successful submit.** A failed submit must not lose the user's work.
- **Keep the review in memory only.** Persistence across sessions is out of scope.
