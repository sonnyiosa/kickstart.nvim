# Reviewer Plugin Implementation Plan

**Goal:** Build the `reviewer` plugin that `docs/specs/2026-11-22-reviewer-plugin-design.md` describes. The user adds, edits, and removes line-range comments in the current file, then submits all comments to an abstract provider.

**Delivery:** One branch, `feat/reviewer`, with five commits in the order below. Each commit is one unit. Each unit starts from green tests and ends with green tests. Do not start a unit until the previous unit is green.

**Tech stack:** Neovim 0.11.4 Lua, lazy.nvim `dir` spec, headless tests with `nvim -l`. No test framework. Live checks use the project `verify` skill (`.claude/skills/verify/`), which drives the real editor in an `hc` terminal.

## Terms

- **Anchor**: the extmark in namespace `reviewer.anchor` that holds a comment range while its buffer is loaded. It is a half-open line range from `(first_row, 0)` to `(last_row + 1, 0)`.
- **Decoration**: the signs and virtual lines in namespace `reviewer.decor`. The plugin clears and draws them again from `comments.list()`.
- **Unit**: one commit with its own checks.

## Dependency Graph

```
Scaffold and test harness
  └─ Add a comment (comments.lua, editor.lua, decoration)
       ├─ Edit and delete a comment
       └─ Providers and submit
            └─ Keymaps and live check   (also needs "Edit and delete")
```

"Edit and delete" and "Providers and submit" do not share a function, but both change `init.lua` and `tests/run.lua`. One worker does all units in sequence. The plugin is about 300 lines, so a split into parallel workers costs more in merges than it saves.

## Global Constraints

- Change only the files that each unit names.
- Tests drive the plugin through its commands, the editor buffer, and `require('reviewer')`. They do not call `comments.lua` functions directly, except `comments.list()` to read the current state.
- Tests derive each expected value from the spec, not from the code under test.
- Run tests with `nvim --headless -u NONE -l plugins/reviewer.nvim/tests/run.lua` from the config root.
- Do not commit until the unit's checks are green.

## Data Shape

```lua
-- comments.lua owns this table. No other module writes to it.
---@class reviewer.Entry
---@field id integer
---@field path string
---@field start_line integer   -- range owner only while no anchor is live
---@field end_line integer
---@field body string
---@field anchor? { buf: integer, id: integer }

-- comments.lua public functions
comments.add(buf, start_line, end_line, body) -> id
comments.update(id, body)
comments.remove(id)
comments.at(buf, lnum) -> reviewer.Comment[]  -- valid comments whose range holds lnum
comments.list() -> (reviewer.Comment & { valid: boolean })[]
comments.forget(ids)                           -- after a successful submit
```

`comments.list()` reads the range from the anchor when the anchor is live, else from the entry. A comment is not valid when its anchor has no lines (start row equals end row).

---

## Unit 1: Scaffold and test harness

- [x] **Depends on:** nothing.
- [x] **Files:** create `plugins/reviewer.nvim/lua/reviewer/init.lua`, `plugins/reviewer.nvim/tests/run.lua`, `lua/custom/plugins/reviewer.lua`.
- [x] **Change:**
  - `init.lua` has `setup(opts)`, which stores `opts` and creates the four user commands with stub bodies that call `vim.notify('not implemented')`.
  - `lua/custom/plugins/reviewer.lua` returns the spec from the design doc, with `keys = {}`.
  - `tests/run.lua` adds `plugins/reviewer.nvim` to the runtimepath, calls `require('reviewer').setup({})`, and runs a list of named test functions. Each test runs in a fresh buffer that has a temp file with lines `l1` to `l9`. The harness prints `ok <name>` or `FAIL <name>: <err>` and exits with `os.exit(1)` on any failure. It has a helper that replaces `vim.ui.select` with a function that picks a given index.
  - One test: each of the four commands exists.
- [x] **Result you see:** the test run prints `ok commands exist`.
- [x] **Verification:**
  - [x] Unit: `nvim --headless -u NONE -l plugins/reviewer.nvim/tests/run.lua` exits with 0.
  - [x] Unit: make one test fail on purpose. Check that the run exits with 1. Then revert that change.
  - [x] Live: `nvim --headless "+lua if not pcall(function() assert(require('lazy.core.config').plugins.reviewer) assert(vim.fn.exists(':ReviewSubmit') == 2) end) then vim.cmd 'cquit 1' end" +qa` exits with 0. This loads the full config.
  - [x] Perf: not applicable. The plugin loads only on a command or a key.

## Unit 2: Add a comment

- [x] **Depends on:** Unit 1.
- [x] **Files:** create `plugins/reviewer.nvim/lua/reviewer/comments.lua` and `plugins/reviewer.nvim/lua/reviewer/editor.lua`. Change `init.lua` and `tests/run.lua`.
- [x] **Change:**
  - `comments.lua` has the data shape above, the two namespaces, the anchor create code, and the decoration draw code. It also has the `BufUnload` and `BufReadPost` autocmds in a `reviewer` augroup.
    - On `BufUnload`, the plugin writes each live anchor range back to its entry.
    - On `BufReadPost`, the plugin creates an anchor only for an entry with no live anchor in that buffer.
    - On `TextChanged` and `TextChangedI`, it draws the decoration again for that buffer.
  - `editor.lua` has `editor.open({ title, body, on_save })`. It opens a floating window with a `markdown` buffer, `buftype=acwrite`, and the keys from the spec. It calls `on_save(trimmed_body)` once, only when the body is not empty.
  - `:ReviewAdd` reads `<line1>` and `<line2>`, opens the editor, and calls `comments.add` on save. In a buffer with no file path, it shows a warning.
- [x] **Result you see:** select lines in visual mode and run `:'<,'>ReviewAdd`. Type a body and press `:w`. A sign shows on each line of the range, and the body shows below the range.
- [x] **Verification:**
  - [x] Unit: `:3,5ReviewAdd`, then set the editor lines to `fix this` and run `:w`. `comments.list()` gives one valid comment with lines 3 to 5 and body `fix this`.
  - [x] Unit: the add from above, then an insert of two lines above line 1. The range is lines 5 to 7.
  - [x] Unit: an insert of one line directly below the range keeps the range length at 3 lines.
  - [x] Unit: `:3,5delete` makes the comment not valid, and the buffer has no decoration. `normal! u` makes it valid at lines 3 to 5 again.
  - [x] Unit: `:bunload!`, then a reload of the file. The comment is valid at lines 3 to 5, and the buffer has exactly one anchor.
  - [x] Unit: `:edit!` keeps exactly one anchor for the comment.
  - [x] Unit: an editor save with only spaces adds no comment.
  - [x] Unit: the buffer has one sign mark on each of lines 3 to 5 and one `virt_lines` mark on line 5. Read them with `nvim_buf_get_extmarks(buf, decor_ns, 0, -1, { details = true })`.
  - [x] Unit: `:ReviewAdd` in a scratch buffer with no name adds no comment.
  - [x] Live: run the `reviewer-add` and `reviewer-track` journeys in `.claude/skills/verify/features/reviewer.md` with the `:'<,'>ReviewAdd` command entry point. Each step passes, and the screens show the signs and the body.
  - [x] Perf: not applicable.

## Unit 3: Edit and delete a comment

- [x] **Depends on:** Unit 2.
- [x] **Files:** change `init.lua`, `comments.lua`, and `tests/run.lua`.
- [x] **Change:**
  - `comments.at(buf, lnum)` returns the valid comments whose range holds `lnum`.
  - Both commands use one helper in `init.lua` that picks the comment at the cursor. With zero comments, it shows a warning. With one comment, it uses that comment. With more than one, it asks with `vim.ui.select`.
  - `:ReviewEdit` opens the editor with the old body and calls `comments.update` on save.
  - `:ReviewDelete` calls `comments.remove`, which removes the anchor and draws the decoration again.
- [x] **Result you see:** on a line in a comment range, `:ReviewEdit` shows the old body. `:ReviewDelete` removes the sign and the body.
- [x] **Verification:**
  - [x] Unit: the cursor on line 4 of a comment on lines 3 to 5. `:ReviewEdit`, set the body to `new`, and run `:w`. The body is `new`.
  - [x] Unit: `:ReviewEdit` and a save with an empty body keep the old body.
  - [x] Unit: `:ReviewDelete` on line 4. `comments.list()` is empty, and the buffer has no decoration and no anchor.
  - [x] Unit: two comments on lines 3 to 5 and 4 to 6, with the cursor on line 4 and the select stub set to index 2. `:ReviewDelete` removes only the second comment.
  - [x] Unit: `:ReviewEdit` on line 8, with no comment there, changes nothing and does not open a window.
  - [x] Live: run the `reviewer-edit` and `reviewer-delete` journeys with the `:ReviewEdit` and `:ReviewDelete` command entry points. Each step passes.
  - [x] Perf: not applicable.

## Unit 4: Providers and submit

- [x] **Depends on:** Unit 2.
- [x] **Files:** change `init.lua`, `comments.lua`, and `tests/run.lua`.
- [x] **Change:**
  - `register_provider(p)` adds `p` to a registry keyed by `p.name`. It raises an error when the name is already in the registry.
  - `:ReviewSubmit` runs the seven steps of the spec. The submit state is one local variable with the value `'idle'` or `'submitting'`. `done` is wrapped once, so a second call does nothing. The wrapper runs through `vim.schedule`.
  - `code` comes from the loaded buffer, or from `vim.fn.readfile(path)` when the buffer is not loaded.
  - The payload is sorted by `path`, then `start_line`.
  - On success, `comments.forget(ids)` removes only the comments in the payload.
- [x] **Result you see:** with a test provider that prints the payload, `:ReviewSubmit` prints all comments with their code and empties the review.
- [x] **Verification:**
  - [x] Unit: two comments in two files, and one fake provider. The provider gets one payload. The payload has `root = vim.fn.getcwd()`, two comments in path order, and for each comment the exact `code` text and `filetype`. After `done()`, `comments.list()` is empty.
  - [x] Unit: a provider that calls `done('boom')` keeps both comments.
  - [x] Unit: a provider that keeps `done` and does not call it. A second `:ReviewSubmit` does not call the provider again.
  - [x] Unit: a comment that the test adds after the submit starts and before `done()` stays in the review.
  - [x] Unit: a provider that calls `done()` twice does not raise an error and does not change the review on the second call.
  - [x] Unit: no provider registered. Submit keeps the comments and shows an error.
  - [x] Unit: two providers and `opts.provider` not set. The select stub picks index 2, and only the second provider gets the payload.
  - [x] Unit: `setup({ provider = 'b' })` with two providers does not ask with `vim.ui.select`.
  - [x] Unit: a comment whose lines the test deleted is not in the payload.
  - [x] Unit: `register_provider` with a name that is already in the registry raises an error.
  - [x] Unit: a comment in a file whose buffer is unloaded gets `code` from disk.
  - [x] Live: run the `reviewer-submit` journey with the `:ReviewSubmit` command entry point. Each step passes.
  - [x] Perf: not applicable.

## Unit 5: Keymaps and live check

- [x] **Depends on:** Unit 3 and Unit 4.
- [x] **Files:** change `lua/custom/plugins/reviewer.lua`, `init.lua` (which-key spec list), and the Keymaps section of the spec.
- [x] **Change:**
  - `lua/custom/plugins/reviewer.lua` defines one local `prefix = '<leader>a'` and makes the four `keys` entries from it, each with a `desc`: `prefix..'a'` (mode `x`, `:ReviewAdd` on the selected lines), `prefix..'e'` (mode `n`, `:ReviewEdit`), `prefix..'d'` (mode `n`, `:ReviewDelete`), and `prefix..'s'` (mode `n`, `:ReviewSubmit`).
  - The which-key spec list in `init.lua` gets `{ '<leader>a', group = '[a]gent review', mode = { 'n', 'x' } }`, next to the other groups.
  - The Keymaps section of the spec states the single prefix and the which-key group.
- [x] **Result you see:** the full flow works with keymaps only. `<Space>a` shows the `[a]gent review` group in the which-key popup.
- [x] **Verification:**
  - [x] Unit: the full test suite exits with 0.
  - [x] Live: `nvim --headless "+lua if not pcall(function() for _, k in ipairs({'aa','ae','ad','as'}) do assert(vim.fn.maparg('<leader>'..k, k == 'aa' and 'x' or 'n') ~= '') end end) then vim.cmd 'cquit 1' end" +qa` exits with 0. (A failed `+lua assert` alone still exits with 0, so the check uses `cquit 1`.)
  - [x] Live: which-key knows the group. `require('which-key.config').mappings` has an entry with `group = true` and `desc = '[a]gent review'` for `<leader>a` in modes `n` and `x`, and a screen capture after `<Space>a` shows the group popup with its keys.
  - [x] Live: run all journeys in `.claude/skills/verify/features/reviewer.md` with the keymap entry points. Each step passes, and `$D doctor` shows no new `v:errmsg`.
  - [ ] Live: the operator tries the keymaps in a daily session. (This is the only step that waits for the operator.)
    - Still open: the operator has not tried the keymaps. While the operator was away (autopilot run), the agent ran a substitute check on the merged live config `~/.config/nvim` at `03dfbbd`, through the keymaps only: add, track, edit with `:wq`, delete, add with `<CR>` and `:x`, submit, and the `+[a]gent review` which-key group. All steps passed. Evidence: `~/.cache/nvim-verify/rv-daily/evidence/`.
  - [x] Perf: `nvim --headless --startuptime <file> +qa` shows no `reviewer` module load at startup.

## Unit 6: Conflict-style markers and yellow body

- [x] **Depends on:** Unit 5.
- [x] **Files:** change `comments.lua`, `tests/run.lua`, the Display section of the spec, and `.claude/skills/verify/features/reviewer.md`.
- [x] **Change:**
  - `redraw` adds a `virt_lines_above` mark on the first line of the range with `>>>>>>> review`.
  - The mark on the last line of the range shows `=======`, the body lines, and `<<<<<<<`.
  - All marker and body lines use `ReviewerBody`. `ReviewerBody` links to `DiagnosticWarn` (yellow).
- [x] **Result you see:** each comment shows as a yellow block in the shape of a git conflict around the range.
- [x] **Verification:**
  - [x] Unit: a comment on lines 3 to 5 with a two-line body gives `>>>>>>> review` above line 3, then `=======`, the two body lines, and `<<<<<<<` below line 5. Each virtual line uses `ReviewerBody`.
  - [x] Unit: an edit to the body `new` gives the same markers around `new`.
  - [x] Unit: `ReviewerBody` links to `DiagnosticWarn`.
  - [x] Unit: the full test suite exits with 0.
  - [x] Live: add comments on lines 3 to 4 and on line 1 with the keymap. The screen shows the markers and the body. The resolved `ReviewerBody` color is yellow (`#f9e2af`). Evidence: `~/.cache/nvim-verify/rvmark/evidence/`.
  - [x] Live: on line 1, the `>>>>>>> review` marker shows only after `<C-y>`. The spec records this as a known limit.
  - [x] Perf: not applicable.

## Unit 7: Submit preview with notes

- [x] **Depends on:** Unit 4.
- [x] **Files:** change `init.lua`, `editor.lua`, `tests/run.lua`, and the Submit section of the spec.
- [x] **Change:**
  - `editor.open` takes `on_cancel`, `width`, and `height`. `on_cancel` runs when the window closes with no saved text. `on_save` runs after the window closes, so a window that `on_save` opens keeps the focus.
  - `:ReviewSubmit` opens the preview after the provider choice. A save sets `payload.message` and calls the provider. A cancel sets the state to `idle` and keeps the comments.
- [x] **Result you see:** `:ReviewSubmit` shows the full message with an empty `## Notes` section. `:w` sends it. `q` cancels.
- [x] **Verification:**
  - [x] Unit: the preview text for one comment is the exact text that the spec gives, and the provider is not called before the save.
  - [x] Unit: the payload `message` for two files is the spec text without the empty Notes heading.
  - [x] Unit: notes that the user types under `## Notes` are in `message`.
  - [x] Unit: a change to a comment body in the preview is in `message`, and `payload.comments` keeps the old body.
  - [x] Unit: `q` in the preview keeps the comments, does not call the provider, and a second submit works.
  - [x] Unit: when the provider runs, no float is open and the source buffer is current. This test fails on the old editor, which called `on_save` before the close.
  - [x] Perf: not applicable.

## Unit 8: herdr-core provider

- [x] **Depends on:** Unit 7.
- [x] **Files:** create `plugins/reviewer.nvim/lua/reviewer/providers/herdr_core.lua`. Change `lua/custom/plugins/reviewer.lua`, `tests/run.lua`, the spec, and `.claude/skills/verify/features/reviewer.md`.
- [x] **Change:** the provider that the herdr-core section of the spec gives. The lazy spec `config` registers it when `hc` is executable.
- [x] **Result you see:** `<Space>as`, then `:w` in the preview, shows `Send review to` with the active agent first. `<CR>` sends the message to that agent.
- [x] **Verification:**
  - [x] Unit (fake `hc` and `herdr-app` on `PATH`): the picker shows `t4` (active), `t3` (same space), `t2`, and hides the shell. The labels are `fixer (active)  fix login bug  pi  /x  idle` (title from `hc get`), `t3  codex  app / 1  working` (no `hc get` answer), and `t2  claude-code  /x  idle` (empty title). `hc send` gets `t4` and the exact message. The review is empty after.
  - [x] Live (verify run `rvtitle`): the picker shows `t1kv (active)  herdr-core provider implementation  claude-code  nvim / 1  working`. The run cancelled the picker, so it sent nothing.
  - [x] Unit: with no `herdr-app`, the order is by address.
  - [x] Unit: a failed `hc send` keeps the comments and shows `terminal is blocked`.
  - [x] Unit: with no coding agent, the plugin does not ask and keeps the comments.
  - [x] Unit: with no agent picked, the plugin keeps the comments.
  - [x] Unit: a reversed sort makes the order test fail.
  - [x] Live: the full config registers `herdr-core`.
  - [x] Live (verify run `rvhc2`, `HC_SOCKET` set to the real core): add with `<Space>aa`, `<Space>as`, a note in the preview, `:w`. The Telescope picker has the focus and shows `t1kv  claude-code  nvim / 1  working  (active)`. `<CR>` gives `reviewer: sent 1 comments to herdr-core`, and the agent got the exact message.
  - [x] Perf: not applicable. The provider module loads only when the plugin loads.

## Unit 9: Move the plugin to `plugins/`

- [x] **Depends on:** Unit 8.
- [x] **Files:** move `reviewer.nvim/` to `plugins/reviewer.nvim/` with `git mv`. Change `lua/custom/plugins/reviewer.lua` (`dir`), the header of `tests/run.lua`, the spec, this plan, and `.claude/skills/verify/features/reviewer.md`.
- [x] **Change:** only paths. The test harness finds its root from its own path, so its code does not change.
- [x] **Verification:**
  - [x] Unit: `nvim --headless -u NONE -l plugins/reviewer.nvim/tests/run.lua` exits with 0.
  - [x] Unit: no file outside `.git` names the old path `reviewer.nvim/` at the config root.
  - [x] Live: the full config loads `reviewer` from `plugins/reviewer.nvim`, and `herdr-core` is registered.
  - [x] Live: the `<Space>aa` add journey shows the markers and the body.

## Unproven

- The `verify` skill sends keys through the Neovim input queue, not through terminal key codes. A key that the terminal encodes wrong is out of its reach.
- The plan does not test a provider that runs an external process. No concrete provider is in scope.
