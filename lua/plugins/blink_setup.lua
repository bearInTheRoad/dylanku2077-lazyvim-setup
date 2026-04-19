return {
	"saghen/blink.cmp",
	dependencies = { "olimorris/codecompanion.nvim", "blink.compat" },
	opts = {
		sources = {
			default = { "lsp", "path", "snippets", "buffer", "codecompanion" },
			providers = {
				codecompanion = {
					name = "CodeCompanion",
					module = "blink.compat.source",
					score_offset = 100,
					opts = {},
				},
			},
		},
		completion = {
			-- 开启 Ghost Text 预览 AI 建议
			ghost_text = { enabled = true },
			menu = {
				draw = {
					columns = { { "label", "label_description", gap = 1 }, { "kind_icon", "kind" } },
				},
			},
		},
	},
}
