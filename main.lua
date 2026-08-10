--- searchjump.yazi — flash.nvim style label jumping for Yazi.
---
--- Typing narrows the file list; every match grows a one-key label, and
--- pressing that key jumps to it.

-- stylua: ignore
local LABEL_KEYS = {
	"j", "f", "d", "k", "l", "h", "g", "a", "s", "o", "i", "e", "u", "n", "c", "m", "r", "p", "b", "t", "w", "v", "x",
	"y", "q", "z",
	"I", "J", "L", "H", "A", "B", "Y", "D", "E", "F", "G", "Q", "R", "T",
	"U", "V", "W", "X", "Z", "C", "K", "M", "N", "O", "P", "S",
}

-- stylua: ignore
local INPUT_KEYS = {
	"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
	"N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
	"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
	"n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
	"-", "_", ".",
	"<Esc>", "<Space>", "<Enter>", "<Backspace>", "<C-n>", "<C-p>",
}

-- `ya.which()` reports the 1-based index of the candidate that was pressed, so
-- deriving the candidates from `INPUT_KEYS` keeps the two lists in step.
local INPUT_CANDS = {}
for i, key in ipairs(INPUT_KEYS) do
	INPUT_CANDS[i] = { on = key }
end

local DEFAULTS = {
	mapdata = {},
	only_current = false,
	search_patterns = {},
	show_search_in_statusbar = false,
	auto_exit_when_unmatch = true,
	enable_capital_label = false,
}

-- ---------------------------------------------------------------------------
-- Colour
--
-- Colours are measured, not invented: the plugin reads the active theme and
-- only computes the one value a theme can't supply — a label foreground that
-- stays legible on whatever background the theme picked.
-- ---------------------------------------------------------------------------

-- sRGB approximations of the 16 ANSI colours. These are used solely to
-- *measure* luminance; the terminal still renders the theme's own colour.
-- stylua: ignore
local ANSI_RGB = {
	black        = 0x000000, red          = 0x800000,
	green        = 0x008000, yellow       = 0x808000,
	blue         = 0x000080, magenta      = 0x800080,
	cyan         = 0x008080, gray         = 0xc0c0c0,
	darkgray     = 0x808080, lightred     = 0xff0000,
	lightgreen   = 0x00ff00, lightyellow  = 0xffff00,
	lightblue    = 0x0000ff, lightmagenta = 0xff00ff,
	lightcyan    = 0x00ffff, white        = 0xffffff,
}

-- stylua: ignore
local ANSI_ORDER = {
	"black", "red", "green", "yellow", "blue", "magenta", "cyan", "gray",
	"darkgray", "lightred", "lightgreen", "lightyellow", "lightblue", "lightmagenta", "lightcyan", "white",
}

-- The aliases `ratatui` accepts in theme files, normalised to our key names.
local ANSI_ALIASES = { grey = "gray", silver = "gray", lightblack = "darkgray", lightwhite = "white", lightgray = "white" }

-- Intensity levels of the xterm 6x6x6 colour cube.
local CUBE = { 0, 95, 135, 175, 215, 255 }

--- Turn a colour as written in a theme (or a user option) into an RGB integer.
--- Returns nil for `reset` and anything else that has no measurable value.
---@param color string|nil
---@return integer|nil
local function resolve_rgb(color)
	if type(color) ~= "string" then
		return nil
	end

	local hex = color:match("^#(%x%x%x%x%x%x)$")
	if hex then
		return tonumber(hex, 16)
	end

	local idx = tonumber(color)
	if idx and idx == math.floor(idx) and idx >= 0 and idx <= 255 then
		if idx < 16 then
			return ANSI_RGB[ANSI_ORDER[idx + 1]]
		elseif idx < 232 then
			local n = idx - 16
			return CUBE[n // 36 + 1] * 0x10000 + CUBE[n % 36 // 6 + 1] * 0x100 + CUBE[n % 6 + 1]
		else
			local v = 8 + (idx - 232) * 10
			return v * 0x10101
		end
	end

	local name = color:lower():gsub("[%s%-_]", "")
	name = name:gsub("^bright", "light")
	return ANSI_RGB[ANSI_ALIASES[name] or name]
end

--- WCAG relative luminance, 0 (black) to 1 (white).
---@param rgb integer
---@return number
local function luminance(rgb)
	local function linear(c)
		c = c / 255
		return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * linear(rgb >> 16 & 0xff) + 0.7152 * linear(rgb >> 8 & 0xff) + 0.0722 * linear(rgb & 0xff)
end

--- Pick whichever of black/white contrasts better with `rgb`. 0.179 is the
--- luminance at which the two contrast ratios cross over, so this is the
--- highest contrast a single foreground can reach against that background.
---@param rgb integer
---@return string
local function readable_fg(rgb) return luminance(rgb) > 0.179 and "#000000" or "#ffffff" end

--- Reduce a theme style to a solid, legible badge: its colour becomes the
--- background, and the foreground is computed for maximum contrast.
---@param style ui.Style
---@return ui.Style
local function badge(style)
	local raw = style:raw()
	local rgb = resolve_rgb(raw.bg) or resolve_rgb(raw.fg)
	if not rgb then
		-- The theme colour is `reset` (or something we can't measure), so its
		-- luminance is unknown. Reversing it still guarantees the label's
		-- foreground and background differ.
		return ui.Style():patch(style):reverse(true):bold(true)
	end

	local bg = string.format("#%06x", rgb)
	return ui.Style():bg(bg):fg(readable_fg(rgb)):bold(true)
end

--- Apply a user's fg/bg override, deriving whichever half they left out.
---@param style ui.Style
---@param fg string|nil
---@param bg string|nil
---@return ui.Style
local function override(style, fg, bg)
	if bg then
		style = style:bg(bg)
		if not fg then
			local rgb = resolve_rgb(bg)
			fg = rgb and readable_fg(rgb) or nil
		end
	end
	return fg and style:fg(fg) or style
end

--- Resolve every style the overlay draws with, once per searchjump session so
--- that a flavour switch is picked up the next time it is opened.
---@param opts table
---@return table
local function build_styles(opts)
	local styles = {
		-- Everything that didn't match recedes. `dim` needs no colour of its
		-- own, so it reads correctly against any flavour, light or dark.
		unmatch = ui.Style():dim(true),
		-- `mgr.find_keyword` is, by definition, "the highlighted portion of a
		-- filename" — the same job the matched substring does here.
		match = ui.Style():patch(th.mgr.find_keyword),
		-- The match `<Enter>` would take, promoted to a solid badge.
		first_match = badge(ui.Style():patch(th.mgr.find_keyword)),
		-- `which.cand` is the accent a flavour reserves for "press this key",
		-- which is exactly what a jump label is.
		label = badge(ui.Style():patch(th.which.cand)),
	}

	if opts.unmatch_fg then
		styles.unmatch = ui.Style():fg(opts.unmatch_fg)
	end
	styles.match = override(styles.match, opts.match_str_fg, opts.match_str_bg)
	styles.first_match = override(styles.first_match, opts.first_match_str_fg, opts.first_match_str_bg)
	styles.label = override(styles.label, opts.label_fg, opts.label_bg)
	return styles
end

-- ---------------------------------------------------------------------------
-- Matching
--
-- Everything below runs inside a `ya.sync` block already, so these are plain
-- functions — wrapping them in `ya.sync` too would only add nested hops.
-- ---------------------------------------------------------------------------

--- Split a string into UTF-8 characters, recording the byte offset each one
--- starts at so matches can be reported as byte ranges into the original.
---@param s string
---@return string[] chars, integer[] offsets, integer count
local function utf8_chars(s)
	local chars, offsets, n, pos = {}, {}, 0, 1
	for char in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		n = n + 1
		chars[n], offsets[n] = char, pos
		pos = pos + #char
	end
	return chars, offsets, n
end

--- `mapdata` maps a non-ASCII character to the latin letters that should match
--- it. Flip each list into a set once so matching is a lookup, not a scan.
---@return table|nil
local function extend_set(st, char)
	local cached = st.extend_cache[char]
	if cached ~= nil then
		return cached or nil
	end

	local list = st.opts.mapdata[char]
	if not list then
		st.extend_cache[char] = false
		return nil
	end

	local set = {}
	for i = 1, #list do
		set[list[i]] = true
	end
	st.extend_cache[char] = set
	return set
end

local function matches_input(st, char, want)
	local set = extend_set(st, char)
	return set and set[want] == true or (not set and want == char)
end

--- The character right after a match is what the user would type next, so it
--- must not double as a label key.
local function reserve_next_char(st, char)
	if not char then
		return
	elseif #char == 1 then
		st.next_char[char] = true
		return
	end

	local list = st.opts.mapdata[char]
	for i = 1, list and #list or 0 do
		st.next_char[list[i]] = true
	end
end

local function reserve_continuations(st, name, needle)
	local chars, _, n = utf8_chars(name)
	local needle_length = #needle
	for start = 1, n - needle_length do
		local matched = true
		for i = 1, needle_length do
			if not matches_input(st, chars[start + i - 1], needle:sub(i, i)) then
				matched = false
				break
			end
		end
		if matched then
			reserve_next_char(st, chars[start + needle_length])
		end
	end
end

--- Literal (as-typed) matching, honouring `mapdata` so that e.g. a Chinese
--- character can be reached by its pinyin initial.
---@return integer[] starts, integer[] ends
local function match_literal(st, name, needle)
	local chars, offsets, n = utf8_chars(name)
	local starts, ends = {}, {}
	local i, j, begin_at = 1, 1, 0 -- i: index into `needle`, j: into `chars`
	reserve_continuations(st, name, needle)

	while j <= n do
		local char = chars[j]
		local want = needle:sub(i, i)
		local hit = matches_input(st, char, want)

		if hit then
			if begin_at == 0 then
				begin_at = j
			end
			if i == #needle then
				starts[#starts + 1] = offsets[begin_at]
				ends[#ends + 1] = offsets[j] + #char - 1
				i, begin_at = 1, 0
			else
				i = i + 1
			end
			j = j + 1
		elseif begin_at ~= 0 then
			-- The run died partway; retry from the character after the one
			-- that started it, in case a shorter run begins there.
			j, i, begin_at = begin_at + 1, 1, 0
		else
			j = j + 1
		end
	end

	return starts, ends
end

--- Lua-pattern matching, used for the presets bound to `<Space>`.
---@return integer[] starts, integer[] ends
local function match_pattern(name, pattern)
	local starts, ends, from = {}, {}, 1
	while true do
		local s, e = name:find(pattern, from)
		if not s then
			return starts, ends
		end
		starts[#starts + 1], ends[#ends + 1] = s, e
		from = e >= s and e + 1 or s + 1 -- a zero-width match must still advance
	end
end

--- Record every file in one pane that matches any of `patterns`.
local function scan_pane(st, pane, folder, patterns)
	if not folder then
		return
	end

	for cursor, file in ipairs(folder.window) do
		local name = tostring(ui.printable(file.name)):lower()
		for _, pattern in ipairs(patterns) do
			if pattern ~= "" then
				local starts, ends
				if st.re_match then
					starts, ends = match_pattern(name, pattern)
				else
					starts, ends = match_literal(st, name, pattern)
				end

				if #starts > 0 then
					local url = tostring(file.url)
					st.match[url] = {
						url = url,
						keys = {},
						starts = starts,
						ends = ends,
						is_dir = file.cha.is_dir,
						pane = pane,
						cursor = cursor,
					}
					-- `pairs()` order is arbitrary, so the visual order the
					-- labels are handed out in is tracked separately.
					st.order[#st.order + 1] = url
					if pane == "current" then
						st.current_order[#st.current_order + 1] = url
					end
					break -- first pattern to hit wins
				end
			end
		end
	end
end

--- Recompute the whole overlay for the current input.
---@return boolean matched
local function rebuild(st, patterns)
	st.match, st.order, st.current_order, st.labels, st.next_char = {}, {}, {}, {}, {}
	st.active, st.active_idx = nil, nil

	-- Current pane first so the earliest, easiest labels land where the user is
	-- already looking.
	scan_pane(st, "current", cx.active.current, patterns)
	if not st.opts.only_current then
		scan_pane(st, "parent", cx.active.parent, patterns)
		scan_pane(st, "preview", cx.active.preview.folder, patterns)
	end

	if #st.order == 0 then
		return false
	end
	if #st.current_order > 0 then
		st.active_idx = 1
		st.active = st.match[st.current_order[1]]
	else
		st.active = st.match[st.order[1]]
	end

	-- Label keys the user hasn't already ruled out by typing towards them.
	local free = {}
	for _, key in ipairs(LABEL_KEYS) do
		if st.opts.enable_capital_label or not key:match("%u") then
			if not st.next_char[key:lower()] then
				free[#free + 1] = key
			end
		end
	end

	local n = 0
	for _, url in ipairs(st.order) do
		local m = st.match[url]
		for k = 1, #m.starts do
			n = n + 1
			local key = free[n]
			if not key then
				return true -- ran out of labels; the rest stay unlabelled
			end
			m.keys[k] = key
			st.labels[key] = m
		end
	end

	return true
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

--- Build the filename line for one file, with matches highlighted, labels
--- appended, and everything else pushed into the background.
---@return ui.Line
local function render_name(st, file)
	local name = tostring(ui.printable(file.name))
	local m = st.match and st.match[tostring(file.url)]

	-- The hovered row already carries the indicator style; dimming it on top
	-- would fight that, so it is left alone.
	local function plain(text)
		return file.is_hovered and ui.Span(text) or ui.Span(text):style(st.styles.unmatch)
	end

	if not m then
		return ui.Line { plain(name) }
	end

	local spans, last = {}, 0
	for k = 1, #m.starts do
		local s, e = m.starts[k], m.ends[k]
		if s > last + 1 then
			spans[#spans + 1] = plain(name:sub(last + 1, s - 1))
		end

		local active = m == st.active and k == 1
		spans[#spans + 1] = ui.Span(name:sub(s, e)):style(active and st.styles.first_match or st.styles.match)
		if m.keys[k] then
			spans[#spans + 1] = ui.Span(m.keys[k]):style(st.styles.label)
		end
		last = e
	end
	if last < #name then
		spans[#spans + 1] = plain(name:sub(last + 1))
	end

	return ui.Line(spans)
end

local function render_position(st, file)
	if not file.is_hovered or not st.active_idx or not st.current_order then
		return ""
	end

	local m = st.match and st.match[tostring(file.url)]
	if m ~= st.active or st.active_idx > 99 then
		return ""
	end

	local total = #st.current_order >= 100 and "99+" or #st.current_order
	return ui.Line { "  ", ui.Span(string.format("[%d/%s]", st.active_idx, total)):style(th.mgr.find_position) }
end

--- Repaint. The preview pane only picks up new styles when it is re-peeked.
local function flush()
	if cx.active.preview.folder then
		ya.emit("peek", { force = true })
	end
	ui.render()
end

local enter_ui = ya.sync(function(st, args)
	st.opts = st.opts or {}
	for k, v in pairs(DEFAULTS) do
		if st.opts[k] == nil then
			st.opts[k] = v
		end
	end

	st.autocd = args[1] == "autocd"
	st.styles = build_styles(st.opts)
	st.extend_cache = {}
	st.re_match = false

	st.saved_highlights = Entity.highlights
	Entity.highlights = function(self) return render_name(st, self._file) end
	st.position_id = Entity:children_add(function(self)
		return render_position(st, self._file)
	end, 5001)

	st.status_id = Status:children_add(function(self)
		local shown = st.opts.show_search_in_statusbar and st.match_pattern
		return ui.Line { ui.Span("[SJ]" .. (shown and ":" .. shown or "") .. " "):style(self:style().main) }
	end, 1001, Status.LEFT)

	flush()
	return st.opts.search_patterns
end)

local leave_ui = ya.sync(function(st)
	Entity.highlights = st.saved_highlights
	Entity:children_remove(st.position_id)
	Status:children_remove(st.status_id, Status.LEFT)

	st.saved_highlights, st.position_id, st.status_id = nil, nil, nil
	st.match, st.order, st.current_order, st.labels, st.next_char = nil, nil, nil, nil, nil
	st.active, st.active_idx, st.match_pattern = nil, nil, nil

	flush()
end)

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------

local function jump(st, m)
	if not st.autocd and m.pane == "current" then
		-- `arrow` keeps visual-mode selection alive, which `reveal` would drop.
		local folder = cx.active.current
		ya.emit("arrow", { m.cursor - folder.cursor - 1 + folder.offset })
	elseif st.autocd and m.is_dir then
		ya.emit("cd", { m.url })
	else
		ya.emit("reveal", { m.url })
	end
end

local function navigate(st, previous)
	local total = st.current_order and #st.current_order or 0
	if total == 0 then
		return
	end

	local folder = cx.active.current
	local hovered = folder.cursor + 1 - folder.offset
	local target_idx = previous and total or 1
	if previous then
		for i = total, 1, -1 do
			if st.match[st.current_order[i]].cursor < hovered then
				target_idx = i
				break
			end
		end
	else
		for i = 1, total do
			if st.match[st.current_order[i]].cursor > hovered then
				target_idx = i
				break
			end
		end
	end

	st.active_idx = target_idx
	st.active = st.match[st.current_order[st.active_idx]]
	local offset = st.active.cursor - folder.cursor - 1 + folder.offset
	if offset ~= 0 then
		ya.emit("arrow", { offset })
	end
end

--- Handle one keystroke: jump if it named a label, otherwise re-search.
---
--- This is the only sync hop per keypress, so the whole state update — label
--- lookup, rematch, status bar, repaint — happens in one crossing.
---@return boolean want_exit, boolean matched
local commit = ya.sync(function(st, patterns, key, input, re, backout)
	if key == "<Enter>" then
		if st.active then
			jump(st, st.active)
			return true, true
		end
		return true, false
	end

	if key == "<C-n>" or key == "<C-p>" then
		navigate(st, key == "<C-p>")
		flush()
		return false, st.order and #st.order > 0 or false
	end

	-- After a backspace the "last key" is the character just deleted; it must
	-- not be read as a label press.
	if not backout and st.labels then
		local target = st.labels[key]
		if target then
			jump(st, target)
			return true, true
		end
	end

	st.re_match = re
	st.match_pattern = re and "[~]" or input

	local matched = rebuild(st, patterns)
	flush()

	if not matched and (re or input ~= "") and st.opts.auto_exit_when_unmatch then
		return true, false
	end
	return false, matched
end)

return {
	setup = function(state, opts) state.opts = opts or {} end,

	entry = function(_, job)
		local presets = enter_ui(job.args)

		local input, key, patterns, re, backout = "", "", {}, false, false
		while true do
			local cand = ya.which { cands = INPUT_CANDS, silent = true }
			local pressed = cand and INPUT_KEYS[cand]

			if pressed == "<Esc>" then
				break
			elseif pressed == nil then
				goto continue
			elseif pressed == "<Enter>" then
				key, patterns, backout = "<Enter>", {}, false
			elseif pressed == "<Space>" then
				key, input, patterns, re, backout = "", "", presets, true, false
			elseif pressed == "<Backspace>" then
				key, input = input:sub(-1), input:sub(1, -2)
				patterns, re, backout = { input }, false, true
			elseif pressed == "<C-n>" or pressed == "<C-p>" then
				key, backout = pressed, false
			else
				key = pressed
				input = input .. pressed:lower()
				patterns, re, backout = { input }, false, false
			end

			::retry::
			local want_exit, matched = commit(patterns, key, input, re, backout)
			if want_exit then
				break
			elseif matched then
				goto continue
			elseif re then
				break -- a preset that matches nothing has nothing to fall back to
			elseif input == "" then
				goto continue
			end

			-- Nothing matched: drop the character that broke the search and
			-- fall back to the previous, still-matching state.
			key, input = input:sub(-1), input:sub(1, -2)
			patterns, backout = { input }, true
			goto retry

			::continue::
		end

		leave_ui()
	end,
}
