--[[ NOTHING INSIDE THIS FILE NEEDS TO BE EDITED BY THE USER. ]]

--- @class Highlite.Definition
--- @field bg? string|table the background color
--- @field blend? number the transparency value
--- @field dark? Highlite.Definition special highlight definition for when `&bg` is 'dark'
--- @field fg? string|table the foreground color
--- @field light? Highlite.Definition special highlight definition for when `&bg` is 'light'
--- @field style? Highlite.Style special appearance alterations

--- @class Highlite.Style
--- @field color string|table color of underline or undercurl

--[[/* Vars */]]

--- Which set of colors to use.
local _USE_256 = tonumber(vim.go.t_Co) > 255 or string.find(vim.env.TERM, '256')

--- Which index to use for `cterm` highlights.
local _PALETTE_CTERM = _USE_256 and 2 or 3

--- Which index to use for `gui` highlights.
local _PALETTE_HEX  = 1

--- The `string` type.
local _TYPE_STRING = type ''

--- The `table` type.
local _TYPE_TABLE  = type {}

--[[/* Helper Functions */]]

--- @param color? string|table the color name or definition
--- @param index number
--- @return nil|number|string color_value a hex, 16-bit, or ANSI color. "NONE" by default
local function get(color, index) -- {{{ †
	if color and color[index] then
		return color[index]
	elseif type(color) == _TYPE_STRING then
		--- @diagnostic disable-next-line:return-type-mismatch (we test for `color == string`, which is a subtype of `(number|string)?`
		return color
	end
end --}}} ‡

--- @param rgb string some string of RGB colors.
--- @return string hex
local function tohex(rgb) return string.format('#%06x', rgb) end

--- Create a metatable which prioritizes entries in the `&bg` index of `definition`
--- @param definition Highlite.Definition the definition of the highlight group
--- @return table
local function use_background_with(definition)
	return setmetatable(definition[vim.go.background], {__index = definition})
end

--[[/* Module */]]

--- A Neovim plugin to create more straightforward syntax for Lua `:map`ping and `:unmap`ping.
--- @class Highlite
local highlite = {}

--- @param name string the name of the highlight group
--- @return Highlite.Definition definition an nvim-highlite compliant table describing the highlight group `name`
function highlite.group(name)
	local no_errors, definition = pcall(vim.api.nvim_get_hl_by_name, name, vim.go.termguicolors)

	if not no_errors then definition = {} end

	-- the style of the highlight group
	local style = {}
	for k, v in pairs(definition) do
		if k == 'special' then
			style.color = tohex(v)
		elseif k ~= 'background' and k ~= 'blend' and k ~= 'foreground' then
			style[#style+1] = k
		end
	end

	return
	{
		fg = definition.foreground and tohex(definition.foreground),
		bg = definition.background and tohex(definition.background),
		blend = definition.blend,
		style = style,
	}
end

-- Generate a `:highlight` command from a group and some definition.

--- Generate and execute `:highlight` command from a group and some definition.
--- @param group_name string the `{group-name}` argument for `:highlight`
--- @param definition Highlite.Definition|string a link or an attribute map
function highlite.highlight(group_name, definition) -- {{{ †
	local highlight = {}
	if type(definition) == _TYPE_STRING then -- `highlight_group` is a link to another group.
		highlight.link = definition
	else
		-- Take care of special instructions for certain background colors.
		if definition[vim.go.background] then
			--- @diagnostic disable-next-line: param-type-mismatch (`str.dark` and `str.light` are `nil`)
			definition = use_background_with(definition)
		end

		highlight.bg = get(definition.bg, _PALETTE_HEX)
		highlight.fg = get(definition.fg, _PALETTE_HEX)

		highlight.ctermbg = get(definition.bg, _PALETTE_CTERM)
		highlight.ctermfg = get(definition.fg, _PALETTE_CTERM)

		highlight.blend = definition.blend

		local style = definition.style
		if type(style) == _TYPE_TABLE then
			--- @diagnostic disable-next-line:param-type-mismatch (we check `type(style) == 'table'` right above this)
			for _, option in ipairs(style) do highlight[option] = true end
			--- @diagnostic disable-next-line:need-check-nil (we check `type(style) == 'table'` right above this)
			highlight.special = get(style.color, _PALETTE_HEX)
		elseif style then
			highlight[style] = true
		end

		highlight.reverse = highlight.inverse
		highlight.inverse = nil
	end

	vim.api.nvim_set_hl(0, group_name, highlight)
end --}}} ‡

--- Set `g:terminal_color_`s based on `terminal_colors`.
--- @param terminal_colors table a list 1..16 of colors to use in the terminal
function highlite:highlight_terminal(terminal_colors)
	for index, color in ipairs(terminal_colors) do vim.g['terminal_color_'..(index-1)] =
		vim.go.termguicolors and color[_PALETTE_HEX] or color[_PALETTE_CTERM]
	end
end

return setmetatable(highlite, {__call = function(self, normal, highlights, terminal_colors)
	--- resolve highlight groups being defined by function calls.
	--- @param tbl table the current table being indexed.
	--- @param key string the key to resolve the value for.
	--- @param resolve_links boolean whether to translate highlight links into full values
	--- @returns the value at `tbl[key]`, when highlight links and embedded functions have been accounted for.
	local function resolve(tbl, key, resolve_links)
		local original_value = tbl[key]
		local original_value_type = type(original_value)

		if original_value_type == 'function' then -- call and cache the result; next time, if it isn't a function this step will be skipped
			tbl[key] = original_value(setmetatable({},
			{
				__index = function(_, inner_key) return resolve(tbl, inner_key, true) end
			}))
		elseif resolve_links and original_value_type == _TYPE_STRING and not string.find(original_value, '^#') then
			return resolve(tbl, original_value, resolve_links)
		end

		return tbl[key]
	end

	-- save the colors_name before syntax reset
	local color_name = vim.g.colors_name

	-- If the syntax has been enabled, reset it.
	if vim.fn.exists 'syntax_on' then vim.api.nvim_command 'syntax reset' end

	-- replace the colors_name
	vim.g.colors_name = color_name
	color_name = nil

	-- If we aren't using hex nor 256 colorsets.
	if not (vim.go.termguicolors or _USE_256) then vim.go.t_Co = '16' end

	-- Highlight the baseline.
	self.highlight('Normal', normal)

	-- Highlight everything else.
	for group_name, _ in pairs(highlights) do
		self.highlight(group_name, resolve(highlights, group_name, false))
	end

	-- Set the terminal highlight colors.
	self:highlight_terminal(terminal_colors)
end})
