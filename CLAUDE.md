# genja-oily.nvim

Hides oil.nvim entries listed in a `.oily` file. Loaded from disk by the
config's `../../lua/lazyp/new/genja-oily.lua` (`dir =` spec, no trigger: it
loads on the first `require('genja-oily')` from oil's `is_hidden_file` and
`<LocalLeader>M` in `lua/lazyp/explorer/oil.lua`). Read README.md and
`doc/genja-oily.txt`.

How this file is kept: one heading per feature, one bullet per decision.
Unmarked bullets were stated by jaro. `(inferred)` marks Claude's reading of the
code or history: confirm or delete. `Hint:` is a working note for Claude.

## Layout

- `lua/genja-oily/init.lua`: `setup(opts)`, `is_hidden_file()`, `hide()`, `find()`.
- Option or behaviour changes go into README.md and `doc/genja-oily.txt` too.

## Decisions

- Moved out of the config's `lua/genja/fn-oil.lua` (idea #15) into its own plugin.
- Each folder oil shows is searched for `.oily`, then its parents up to the filesystem root; the first one found applies, and its rules cover child folders too.
- Rules don't stack: a closer `.oily` replaces one further up. (inferred: follows from "stop at the first one found")
- The lookup is cached for 500 ms, so one oil render searches once and every navigation searches again. (inferred: implementation choice)
- `hide()` with no `.oily` up the tree creates one in `:pwd` if oil's dir is inside it, else in oil's dir. (inferred: keeps the old `:pwd` behaviour)
- Mappings stay in the config. The plugin must not require `genja.*`.
