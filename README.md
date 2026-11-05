# genja-oily.nvim

Hide [oil.nvim](https://github.com/stevearc/oil.nvim) entries listed in a
`.oily` file, on top of oil's dotfile rule. oil's `g.` still shows everything.

## Which .oily applies

Each time oil shows a directory, genja-oily looks for `.oily` in that
directory, then in its parents, up to the filesystem root. The first one found
applies; the search stops there. Its rules cover the directory it sits in and
everything below it, so entering a child folder keeps the same rules until a
closer `.oily` is found.

## Rules

One per line; blank lines and `#` comments are ignored, a trailing `/` is
dropped:

```
node_modules         bare name: hidden in every directory below the .oily
lua/lazyp/unused     path, relative to the .oily dir: hides that entry
C:/tmp/scratch       absolute path: hides that entry
*.log                bare glob: matched against names in every directory below
lua/**/zold*         glob with '/': matched against the path relative to the .oily dir
C:/tmp/*.bak         absolute glob: matched against the absolute path
```

- Globs use `vim.glob` syntax (`*`, `?`, `**`, `[abc]`, `{a,b}`) and must
  match the whole name or path.
- Matching ignores case on Windows.
- A `.oily` is re-read when its mtime changes; a broken glob warns with its
  line number and is skipped.
- Rules don't stack: a closer `.oily` replaces the one further up.

## Install and setup

```lua
{
	'tox2ik/genja-oily.nvim',
	dependencies = { 'stevearc/oil.nvim' },
	opts = {
		filename = '.oily',   -- name of the rules file
		hide_dotfiles = true, -- keep oil's rule: names starting with '.'
	},
}
```

Hook it into oil and map the hide action:

```lua
require('oil').setup({
	view_options = {
		is_hidden_file = function(name, bufnr) return require('genja-oily').is_hidden_file(name, bufnr) end,
	},
	keymaps = {
		['<LocalLeader>M'] = { desc = 'Oil: hide entry via .oily', callback = function() require('genja-oily').hide() end },
	},
})
```

## API

- `is_hidden_file(name, bufnr)`: for oil's `view_options.is_hidden_file`.
- `hide()`: append the entry under the cursor (or the `V`-selected lines) to
  the `.oily` that applies, as a path relative to it (absolute when outside).
  With no `.oily` up the tree, it creates one in `:pwd` when oil's directory is
  inside `:pwd`, else in oil's directory. Re-renders oil.
- `find(dir)`: path of the `.oily` that applies to `dir`, or nil.

## License

MIT
