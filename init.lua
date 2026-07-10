-- bootstrap lazy.nvim, LazyVim and your plugins
-- load local .env into vim.env before anything reads it
require("config.env")
require("config.lazy")

-- load my own plugins
-- can add more
require("floaterminal").setup()
require("present")
require("databricks").setup()
require("cdp").setup()
require("sql_router")

vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
	border = "rounded",
	max_width = 80,
	max_height = 20,
})
