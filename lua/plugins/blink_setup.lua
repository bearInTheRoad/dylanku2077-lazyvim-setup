return {
	"saghen/blink.cmp",
	opts = {
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
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
