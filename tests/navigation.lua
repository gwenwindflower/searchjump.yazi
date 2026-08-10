local function equal(actual, expected, message)
	if actual == expected then
		return
	end
	error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
end

local function sequence(actual, expected, message)
	equal(#actual, #expected, message .. " length")
	for i = 1, #expected do
		equal(actual[i], expected[i], string.format("%s at %d", message, i))
	end
end

local function run(keys, current_names, parent_names)
	local state, arrows, positions = {}, {}, {}
	local entity_children = {}
	local next_child_id = 1000

	local function style()
		return setmetatable({ _raw = {} }, {
			__index = function(self, key)
				if key == "raw" then
					return function()
						return self._raw
					end
				end
				return function()
					return self
				end
			end,
		})
	end

	local function span(text)
		return setmetatable({ text = text }, {
			__index = {
				style = function(self)
					return self
				end,
			},
		})
	end

	local function line(items)
		return setmetatable({ items = items }, {
			__index = {
				style = function(self)
					return self
				end,
			},
		})
	end

	local function text(value)
		if type(value) == "string" then
			return value
		elseif value.text then
			return value.text
		end
		local parts = {}
		for _, item in ipairs(value.items or {}) do
			parts[#parts + 1] = text(item)
		end
		return table.concat(parts)
	end

	ui = {
		Style = style,
		Span = span,
		Line = line,
		printable = function(value)
			return value
		end,
	}
	th = { mgr = { find_keyword = style(), find_position = style() }, which = { cand = style() } }

	local function url(value)
		return setmetatable({}, {
			__tostring = function()
				return value
			end,
		})
	end

	local function folder(names, prefix)
		local files = {}
		for i, name in ipairs(names or {}) do
			files[i] = {
				name = name,
				url = url(string.format("/%s/%s", prefix, name)),
				cha = { is_dir = false },
				is_hovered = i == 1,
			}
		end
		return { window = files, cursor = 0, offset = 0 }
	end

	local current = folder(current_names, "current")
	cx = {
		active = {
			current = current,
			parent = folder(parent_names, "parent"),
			preview = { folder = nil },
		},
	}

	Entity = {
		highlights = function()
			return line({})
		end,
		children_add = function(_, fn)
			next_child_id = next_child_id + 1
			entity_children[next_child_id] = fn
			return next_child_id
		end,
		children_remove = function(_, id)
			entity_children[id] = nil
		end,
	}
	Status = {
		LEFT = "left",
		children_add = function()
			return 1
		end,
		children_remove = function() end,
	}

	local key_index = 0
	ya = {
		sync = function(fn)
			return function(...)
				return fn(state, ...)
			end
		end,
		which = function(opts)
			key_index = key_index + 1
			local wanted = keys[key_index]
			for i, cand in ipairs(opts.cands) do
				if cand.on == wanted then
					return i
				end
			end
		end,
		emit = function(name, args)
			if name ~= "arrow" then
				return
			end
			current.cursor = current.cursor + args[1]
			for i, file in ipairs(current.window) do
				file.is_hovered = i - 1 == current.cursor
			end
			arrows[#arrows + 1] = current.cursor + 1
		end,
	}
	ui.render = function()
		for _, child in pairs(entity_children) do
			for _, file in ipairs(current.window) do
				local rendered = text(child({ _file = file }))
				if rendered ~= "" then
					positions[#positions + 1] = rendered
				end
			end
		end
	end

	local plugin = dofile("main.lua")
	plugin.setup(state, { only_current = false })
	plugin.entry(nil, { args = {} })
	return arrows, positions
end

local arrows, positions = run(
	{ "a", "<C-n>", "<C-n>", "<C-n>", "<C-p>", "<Esc>" },
	{ "alpha", "beta", "gamma" },
	{ "parent-alpha" }
)

sequence(arrows, { 2, 3, 1, 3 }, "navigation targets")
sequence(positions, { "  [1/3]", "  [2/3]", "  [3/3]", "  [1/3]", "  [3/3]" }, "match positions")

local single_arrows, single_positions = run(
	{ "b", "<C-n>", "<C-p>", "<Esc>" },
	{ "alpha", "beta", "gamma" },
	{ "parent-beta" }
)

sequence(single_arrows, { 2 }, "single-match navigation targets")
sequence(single_positions, { "  [1/1]", "  [1/1]" }, "single-match positions")

local overlapping_arrows = run({ "a", "b", "a", "j", "<Esc>" }, { "aBaBaJ" }, {})

sequence(overlapping_arrows, {}, "case-insensitive overlapping continuations remain searchable")

local label_arrows = run({ "a", "j" }, { "alpha" }, {})

sequence(label_arrows, { 1 }, "safe labels remain selectable")

print("navigation tests passed")
