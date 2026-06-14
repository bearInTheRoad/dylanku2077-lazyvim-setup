return {
	"timseriakov/spamguard.nvim",
	event = "VeryLazy",
	config = function()
		local spamguard = require("spamguard")
		spamguard.setup({
			keys = {
				j = { threshold = 9, suggestion = "use s / f instead of spamming jjjj 😎" },
				k = { threshold = 9, suggestion = "try { of ( instead of spamming kkkk 😎" },
				h = { threshold = 9, suggestion = "use b / 0 / ^ instead of spamming hhhh  😎" },
				l = { threshold = 9, suggestion = "try w / e / f — it's faster! 😎" },
				w = { threshold = 8, suggestion = "use s / f — more precise and quicker! 😎" },
			},
		})
		vim.schedule(function()
			spamguard.enable()
		end)
	end,
}
