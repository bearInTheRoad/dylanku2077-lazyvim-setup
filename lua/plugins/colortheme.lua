return {
	-- 1. install the colorscheme plugin
	{
		"scottmckendry/cyberdream.nvim",
		opts = {
			overrides = function(colors)
				return {
					Visual = { bg = "#81a1c1", fg = "NONE", bold = true },
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
