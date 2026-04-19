-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
	border = "rounded",
	max_width = 80,
	max_height = 20,
})
