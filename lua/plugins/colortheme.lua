return {
	-- 1. install the colorscheme plugin
	{ "scottmckendry/cyberdream.nvim" },

	-- 2. tell LazyVim to apply it
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "cyberdream",
		},
	},
}
