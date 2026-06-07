local M = {}

M.state = {
	floating = {
		buf = -1,
		win = -1,
	},
}

local function create_float_window(opts)
	opts = opts or {}

	local width = opts.width or math.floor(vim.o.columns * 0.85)
	local height = opts.height or math.floor(vim.o.lines * 0.8)

	-- calculate the position to center the window
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	local buf = nil
	if vim.api.nvim_buf_is_valid(opts.buf) then
		buf = opts.buf
	else
		buf = vim.api.nvim_create_buf(false, true) -- No file. scratch buffer
	end

	-- define window configuration
	local win_config = {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal", --no boarder or extra UI elements
		border = "rounded",
		title = opts.title or "FloatTerminal",
		title_pos = "center",
	}

	-- create the floating window
	local win = vim.api.nvim_open_win(buf, true, win_config)

	return { buf = buf, win = win }
end

function M.toggle_terminal()
	if not vim.api.nvim_win_is_valid(M.state.floating.win) then
		M.state.floating = create_float_window({ buf = M.state.floating.buf })
		vim.api.nvim_set_current_win(M.state.floating.win)
		if vim.bo[M.state.floating.buf].buftype ~= "terminal" then
			vim.cmd("terminal")
		end
		vim.cmd("startinsert")
	else
		vim.api.nvim_win_hide(M.state.floating.win)
	end
end

function M.setup()
	vim.api.nvim_create_user_command("FloatTerminal", M.toggle_terminal, {})
	vim.keymap.set({ "n", "t", "v" }, "<leader>qt", M.toggle_terminal)
end

return M
