# searchjump.yazi

A Yazi plugin whose behavior is consistent with flash.nvim in Neovim: from a search string it generates labels to jump to.

> [!NOTE]
> This is a continuation of [DreamMaoMao/searchjump.yazi](https://github.com/DreamMaoMao/searchjump.yazi),
> which is no longer maintained as a standalone repository. Maintenance
> happens here now — issues and pull requests welcome. See [Credits](#credits).

https://github.com/DreamMaoMao/searchjump.yazi/assets/30348075/4a00eb39-211b-47c5-8e22-644a7d7bc6b1

## Requirements

The latest main branch of Yazi. The plugin uses `ya.emit`, `ui.printable` and
the `th` theme API, none of which exist in older releases.

## Install

With Yazi's package manager:

```sh
ya pkg add gwenwindflower/searchjump
```

Or manually — Linux and macOS:

```bash
git clone https://github.com/gwenwindflower/searchjump.yazi.git ~/.config/yazi/plugins/searchjump.yazi
```

Windows, with `Powershell`:

```powershell
if (!(Test-Path $env:APPDATA\yazi\config\plugins\)) {mkdir $env:APPDATA\yazi\config\plugins\}
git clone https://github.com/gwenwindflower/searchjump.yazi.git $env:APPDATA\yazi\config\plugins\searchjump.yazi
```

## Usage

Set shortcut key to toggle searchjump mode in `~/.config/yazi/keymap.toml`. For example, set `i` like this:

```toml
[[mgr.prepend_keymap]]
on   = [ "i" ]
run = "plugin searchjump"
desc = "searchjump mode"
```

Or enter directory automatically when jumping onto it:

```toml
[[mgr.prepend_keymap]]
on   = [ "i" ]
run = "plugin searchjump -- autocd"
desc = "searchjump mode"
```

- When you see the single character label at the right of an entry, press the corresponding key to jump to the entry.
- you can use `backspace` to delete a input character.
- you can use `enter` to jump to the first match — the topmost one in the current pane.
- you can use `Space` to match the search_patterns you preset in config.

## Colors

Out of the box the overlay takes its colors from whatever theme or flavor you
have active, so it stays coherent when you switch:

| part | derived from |
| --- | --- |
| matched substring | `mgr.find_keyword` — the theme's own "highlighted part of a filename" style |
| the match `enter` will take | `mgr.find_keyword`, promoted to a solid badge |
| jump label | `which.cand` — the accent your flavor reserves for "press this key" |
| everything unmatched | dimmed, so it needs no color of its own and works on light and dark alike |

Labels are drawn as a badge: the theme color becomes the background, and the
foreground is computed from that background's relative luminance. Picking the
better of black/white gives at least a 4.58:1 contrast ratio for any color in
the sRGB gamut, which clears WCAG AA. Where a theme color can't be measured
(`reset`, for instance) the label falls back to reverse video, which guarantees
contrast structurally.

## Setting options (in `~/.config/yazi/init.lua`)

Every option is optional. Colors you don't set are derived from the theme as
described above; set one to pin it instead.

```lua
require("searchjump"):setup({
	only_current = false,
	show_search_in_statusbar = false,
	auto_exit_when_unmatch = false,
	enable_capital_label = true,
	-- mapdata = require("sjch").data,
	search_patterns = ({"hell[dk]d","%d+.1080p","第%d+集","第%d+话","%.E%d+","S%d+E%d+",})

	-- Optional color overrides:
	-- unmatch_fg = "#b2a496",          -- replaces the default dimming
	-- match_str_fg = "#000000",
	-- match_str_bg = "#73AC3A",
	-- first_match_str_fg = "#000000",
	-- first_match_str_bg = "#73AC3A",
	-- label_fg = "#EADFC8",
	-- label_bg = "#BA603D",
})
```

If you set only a `*_bg`, the matching foreground is computed for you at the
same contrast guarantee. Set both and they are used verbatim. Colors accept
anything Yazi's theme files do: `#RRGGBB`, an ANSI name like `lightcyan`, or a
256-color index.

you can extend map data from external data to map other languages to English letters for matching, such as Chinese data mapping tables:[sjch.yazi](https://github.com/DreamMaoMao/sjch.yazi).

## Credits

Originally written by [DreamMaoMao](https://github.com/DreamMaoMao), who wrote
the great majority of this code and whose commits make up most of the history
here. Thanks also to the contributors to the original repository: TD-Sky,
Milan Raicevic, and Aurélien Berra.

MIT licensed — see [LICENSE](LICENSE), which retains the original copyright
notice alongside the current one.
