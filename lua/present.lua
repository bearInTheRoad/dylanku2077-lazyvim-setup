local M = {}

M.run = function()
	vim.notify("Hello present.nvim")
end

vim.api.nvim_create_user_command("Present", function()
	M.start_presentation({ bufnr = 0 })
end, {})

local create_floating_window = function(win_config)
	local buf = vim.api.nvim_create_buf(false, true)

	local win = vim.api.nvim_open_win(buf, true, win_config)

	return { buf = buf, win = win }
end

local create_window_configurations = function()
	local width = vim.o.columns
	local height = vim.o.lines

	return {
		bg_win_config = {
			relative = "editor",
			width = width,
			height = height,
			col = 0,
			row = 0,
			zindex = 1,
			style = "minimal",
		},

		title_win_config = {
			relative = "editor",
			width = width,
			height = 1,
			col = 0,
			row = 0,
			zindex = 2,
			border = "rounded",
			style = "minimal",
		},

		body_win_config = {
			relative = "editor",
			width = width - 8,
			height = height - 5,
			col = 1,
			row = 3,
			zindex = 2,
			style = "minimal",
		},
	}
end

---@class present.slide
---@field title string;
---@field body string[];
--
---@class present.slides
---@field slides present.slide[] the slides of the file

---@param lines string[]: the lines in the buffer
---@return present.slides
local parse_slides = function(lines)
	local slides = { slides = {} }
	local current_slide = {
		title = "",
		body = {},
	}

	local separator = "^#"

	for _, line in ipairs(lines) do
		if line:find(separator) then
			if #current_slide.title > 0 then
				table.insert(slides.slides, current_slide)
			end

			current_slide = {
				title = line,
				body = {},
			}
		else
			table.insert(current_slide.body, line)
		end
	end

	table.insert(slides.slides, current_slide)

	return slides
end

M.start_presentation = function(opts)
	opts = opts or {}
	opts.bufnr = opts.bufnr or 0

	local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
	local parsed = parse_slides(lines)

	local windows = create_window_configurations()

	local bg_float = create_floating_window(windows.bg_win_config)
	local title_float = create_floating_window(windows.title_win_config)
	local body_float = create_floating_window(windows.body_win_config)

	vim.bo[title_float.buf].filetype = "markdown"
	vim.bo[body_float.buf].filetype = "markdown"

	local set_slide_content = function(index)
		local slide = parsed.slides[index]

		local width = vim.o.columns

		local padding = string.rep(" ", (width - #slide.title) / 2)
		local title = padding .. slide.title
		vim.api.nvim_buf_set_lines(title_float.buf, 0, -1, false, { title })
		vim.api.nvim_buf_set_lines(body_float.buf, 0, -1, false, parsed.slides[index].body)
	end

	local current_index = 1

	vim.keymap.set("n", "n", function()
		current_index = math.min(current_index + 1, #parsed.slides)
		set_slide_content(current_index)
	end, {
		buffer = body_float.buf,
	})

	vim.keymap.set("n", "p", function()
		current_index = math.max(1, current_index - 1)
		set_slide_content(current_index)
	end, {
		buffer = body_float.buf,
	})

	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(title_float.win, true)
		vim.api.nvim_win_close(body_float.win, true)
	end, {
		buffer = body_float.buf,
	})

	local restore = {
		cmdheight = {
			original = vim.o.cmdheight,
			present = 0,
		},
	}

	-- set the options to presentation friendly
	for option, config in pairs(restore) do
		vim.opt[option] = config.present
	end

	vim.api.nvim_create_autocmd("bufleave", {
		buffer = body_float.buf,
		callback = function()
			-- reset values when we are done with presentation
			for option, config in pairs(restore) do
				vim.opt[option] = config.original
			end

			pcall(vim.api.nvim_win_close, bg_float.win, true)
			pcall(vim.api.nvim_win_close, title_float.win, true)
		end,
	})

	vim.api.nvim_create_autocmd("VimResized", {
		group = vim.api.nvim_create_augroup("present-resized", {}),

		callback = function()
			if not vim.api.nvim_win_is_valid(body_float.win) or body_float.win == nil then
				return
			end

			local updated = create_window_configurations()
			vim.api.nvim_win_set_config(title_float.win, updated.title_win_config)
			vim.api.nvim_win_set_config(body_float.win, updated.body_win_config)
			vim.api.nvim_win_set_config(bg_float.win, updated.bg_win_config)

			-- Recalculate the current slide
			set_slide_content(current_index)
		end,
	})

	set_slide_content(current_index)
end

return M
