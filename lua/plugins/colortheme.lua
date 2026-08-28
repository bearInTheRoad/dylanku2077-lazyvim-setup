return {
	-- 1. install the colorscheme plugin
	{
		"scottmckendry/cyberdream.nvim",
		lazy = false,
		priority = 1000,
		opts = {
			-- make ignored/hidden entries in the Snacks explorer/picker bright
			overrides = function(c)
				return {
					SnacksPickerPathIgnored = { fg = c.fg },
					SnacksPickerPathHidden = { fg = c.fg },
				}
			end,
		},
	},

	-- 2. tell LazyVim to apply it
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "cyberdream",
		},
	},
}
