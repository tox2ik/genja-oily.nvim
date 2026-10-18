-- genja-oily: hide oil.nvim entries listed in a `.oily` file.
--
-- The `.oily` that applies to a directory is the first one found walking up
-- from it (the directory itself, then its parents, up to the filesystem root).
-- Its rules apply to that directory and everything below it:
--   node_modules         a bare name: hidden in every directory below
--   lua/lazyp/unused     a path: relative to the .oily dir (or absolute), hides that entry
--   *.log                a bare glob: matched against names in every directory below
--   lua/**/zold*         a glob with '/': matched against the path relative to the .oily dir
--   # comment
-- Globs use vim.glob syntax (* ? ** [abc] {a,b}) and must match the whole name/path.

local M = {}

---@class genja-oily.Opts
---@field filename? string name of the rules file
---@field hide_dotfiles? boolean also hide names starting with '.' (oil's default rule)

---@type genja-oily.Opts
M.config = {
	filename = '.oily',
	hide_dotfiles = true,
}

---@class genja-oily.Rules
---@field mtime string
---@field base string comparable path of the dir holding the .oily
---@field names table<string, true> exact names, any dir below base
---@field paths table<string, true> exact absolute paths
---@field name_globs vim.lpeg.Pattern[] matched against the name
---@field rel_globs vim.lpeg.Pattern[] matched against the path relative to base
---@field abs_globs vim.lpeg.Pattern[] matched against the absolute path

local rules_cache = {} ---@type table<string, genja-oily.Rules> .oily path -> parsed rules
-- dir -> { file = .oily path or false, at = loop time }. oil asks once per
-- entry while it renders a dir, so the search runs once per render: every
-- folder oil enters (or refreshes) is searched again.
local lookup_cache = {} ---@type table<string, { file: string|false, at: integer }>
local LOOKUP_TTL_MS = 500

---Comparable path: forward slashes, no trailing slash, lowercase on Windows.
---@param path string
---@return string
local function key(path)
	local k = vim.fs.normalize(path)
	if vim.fn.has('win32') == 1 then
		k = k:lower()
	end
	return k
end

---@param line string
---@return boolean
local function has_glob(line)
	return line:find('[%*%?%[{]') ~= nil
end

---First .oily walking up from `dir` (inclusive) to the filesystem root.
---Reused for LOOKUP_TTL_MS, i.e. for the rest of one oil render.
---@param dir string
---@return string|nil file
function M.find(dir)
	local dir_key = key(dir)
	local now = vim.uv.now()
	local cached = lookup_cache[dir_key]
	if not cached or now - cached.at > LOOKUP_TTL_MS then
		-- normalize: oil's dir ends in a backslash on Windows
		local start = vim.fs.normalize(dir)
		local found = vim.fs.find(M.config.filename, { path = start, upward = true, type = 'file', limit = 1 })[1]
		cached = { file = found or false, at = now }
		lookup_cache[dir_key] = cached
	end
	if cached.file == false then
		return nil
	end
	return cached.file
end

---Parsed `file`, re-read when its mtime changes; nil when it is gone.
---@param file string
---@return genja-oily.Rules|nil
local function read_rules(file)
	local stat = vim.uv.fs_stat(file)
	if not stat then
		rules_cache[file] = nil
		return nil
	end
	local mtime = stat.mtime.sec .. '.' .. stat.mtime.nsec
	local cached = rules_cache[file]
	if cached and cached.mtime == mtime then
		return cached
	end

	local base = vim.fs.dirname(file)
	---@type genja-oily.Rules
	local rules = { mtime = mtime, base = key(base), names = {}, paths = {}, name_globs = {}, rel_globs = {}, abs_globs = {} }
	for lnum, line in ipairs(vim.fn.readfile(file)) do
		line = vim.trim(line):gsub('/+$', '')
		if line ~= '' and not vim.startswith(line, '#') then
			local is_absolute = line:match('^%a:') or vim.startswith(line, '/')
			local is_path = line:find('/', 1, true) ~= nil
			if has_glob(line) then
				local ok, glob = pcall(vim.glob.to_lpeg, key(line))
				if not ok then
					vim.notify('genja-oily: bad glob in ' .. file .. ':' .. lnum .. ': ' .. line, vim.log.levels.WARN)
				elseif is_absolute then
					table.insert(rules.abs_globs, glob)
				elseif is_path then
					table.insert(rules.rel_globs, glob)
				else
					table.insert(rules.name_globs, glob)
				end
			elseif is_absolute then
				rules.paths[key(line)] = true
			elseif is_path then
				rules.paths[key(vim.fs.joinpath(base, line))] = true
			else
				rules.names[key(line)] = true
			end
		end
	end
	rules_cache[file] = rules
	return rules
end

---@param globs vim.lpeg.Pattern[]
---@param subject string
---@return boolean
local function any_match(globs, subject)
	for _, glob in ipairs(globs) do
		if glob:match(subject) then
			return true
		end
	end
	return false
end

---For oil's `view_options.is_hidden_file`.
---@param name string entry name
---@param bufnr integer oil buffer
---@return boolean
function M.is_hidden_file(name, bufnr)
	if M.config.hide_dotfiles and vim.startswith(name, '.') then
		return true
	end
	local dir = require('oil').get_current_dir(bufnr)
	if not dir then
		return false
	end
	local file = M.find(dir)
	if not file then
		return false
	end
	local rules = read_rules(file)
	if not rules then
		return false
	end

	local name_key = key(name)
	if rules.names[name_key] or any_match(rules.name_globs, name_key) then
		return true
	end
	local full = key(vim.fs.joinpath(dir, name))
	if rules.paths[full] or any_match(rules.abs_globs, full) then
		return true
	end
	local prefix = rules.base .. '/'
	if vim.startswith(full, prefix) then
		return any_match(rules.rel_globs, full:sub(#prefix + 1))
	end
	return false
end

---Saved entries on the cursor line, or on the visual lines (leaves visual mode).
---@return string[] names
local function entry_names()
	local first = vim.fn.line('.')
	local last = first
	local visual = vim.fn.mode() == 'V'
	if visual then
		first = math.min(vim.fn.line('v'), vim.fn.line('.'))
		last = math.max(vim.fn.line('v'), vim.fn.line('.'))
	end
	local names = {}
	for lnum = first, last do
		local entry = require('oil').get_entry_on_line(0, lnum)
		if entry and entry.id and entry.name ~= '..' then -- id nil: typed, not saved yet
			table.insert(names, entry.name)
		end
	end
	if visual then
		vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'n', false)
	end
	return names
end

---Where a new rule for `dir` goes: the .oily that applies to it; with none,
---`:pwd`'s when `dir` is inside `:pwd`, else `dir`'s own.
---@param dir string
---@return string file
local function target_file(dir)
	local found = M.find(dir)
	if found then
		return found
	end
	local cwd = vim.fn.getcwd()
	if vim.startswith(key(dir) .. '/', key(cwd) .. '/') then
		return vim.fs.joinpath(cwd, M.config.filename)
	end
	return vim.fs.joinpath(dir, M.config.filename)
end

---Hide the entry under the cursor (or the visual lines) by appending its path
---to the .oily that applies; creates the file when there is none.
function M.hide()
	local dir = require('oil').get_current_dir()
	if not dir then
		return
	end
	local names = entry_names()
	if #names == 0 then
		return
	end
	local file = target_file(dir)
	local base = vim.fs.normalize(vim.fs.dirname(file))
	local lines = {}
	for _, name in ipairs(names) do
		local path = vim.fs.normalize(vim.fs.joinpath(dir, name))
		local line = path -- absolute when outside the .oily dir
		if vim.startswith(key(path), key(base) .. '/') then
			line = path:sub(#base + 2)
		end
		table.insert(lines, line)
	end
	vim.fn.writefile(lines, file, 'a') -- creates the file if needed
	lookup_cache = {} -- a new file may apply to dirs searched a moment ago
	vim.notify('genja-oily: hidden via ' .. file .. ': ' .. table.concat(lines, ' '))
	require('oil').set_is_hidden_file(M.is_hidden_file) -- re-render with the new rules
end

---@param opts? genja-oily.Opts
function M.setup(opts)
	M.config = vim.tbl_deep_extend('force', M.config, opts or {})
	lookup_cache = {}
end

return M
