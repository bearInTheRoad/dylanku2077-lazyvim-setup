return {
	-- 1. install the colorscheme plugin (merges opts with LazyVim's bundled spec)
	{
		"folke/tokyonight.nvim",
		opts = {
			on_highlights = function(hl, c)
				-- make ignored/hidden entries in the Snacks explorer/picker brighter
				hl.SnacksPickerPathIgnored = { fg = c.fg_dark }
				hl.SnacksPickerPathHidden = { fg = c.fg_dark }
			end,
		},
	},

	-- 2. tell LazyVim to apply it
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "tokyonight",
		},
	},
}
