return {
    {
        "stevearc/conform.nvim",
        opts = {
            formatters_by_ft = {
                javascript = { "prettier" },
                typescript = { "prettier" },
                javascriptreact = { "prettier" },
                typescriptreact = { "prettier" },
                json = { "prettier" },
                html = { "prettier" },
                css = { "prettier" },
                -- golines wraps lines longer than --max-len; gofumpt finalizes
                go = { "goimports", "golines", "gofumpt" },
            },
            formatters = {
                golines = {
                    args = { "--max-len=120" },
                },
            },
        },
    },
    -- ensure golines binary is installed via Mason (opts_extend concatenates)
    {
        "mason-org/mason.nvim",
        opts = { ensure_installed = { "golines" } },
    },
}
