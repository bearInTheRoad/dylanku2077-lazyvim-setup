local function load_env()
	local env = {}
	local path = vim.fn.stdpath("config") .. "/.env"
	local f = io.open(path, "r")
	if not f then
		return env
	end
	for line in f:lines() do
		local key, val = line:match("^%s*([%w_]+)%s*=%s*(.+)%s*$")
		if key and val then
			env[key] = val
		end
	end
	f:close()
	return env
end

local env = load_env()

local think_stripped_inline = {
	inline_output = function(self, data, context, model)
		if not data or data == "" then
			return { status = "error", output = "Empty response" }
		end
		local body = data.body or data
		if type(body) == "string" then
			if body:match("^%s*%[") then
				body = body:match("^%s*(%[.+%])%s*$")
			end
			local ok, json = pcall(vim.json.decode, body, { luanil = { object = true } })
			if not ok or not json then
				return { status = "error", output = "Invalid JSON: " .. tostring(body):sub(1, 200) }
			end
			data = json
		end
		local choices = data.choices or data
		if not choices or not choices[1] then
			return { status = "error", output = "No choices in response" }
		end
		local msg = choices[1].message or choices[1].delta or {}
		local content = msg.content or msg.reasoning_content or ""
		if content == "" and msg.reasoning_content then
			content = msg.reasoning_content
		end
		if model == "glm" then
			content = content:gsub("^%s*<think[\r\n].-[\r\n]</think[%s]*", "")
			content = content:gsub("^%s*<think.-</think[%s]*", "")
			return { status = "success", output = content }
		else
			local new_content = content:gsub(".-</think>%s*", "")
			local f = io.open("debug.txt", "a")
			-- if f then
			-- 	f:write(vim.inspect(content), "\n")
			-- 	f:write("=====================")
			-- 	f:write(vim.inspect(new_content), "\n")
			-- 	f:close()
			-- end
			return { status = "success", output = new_content }
		end
	end,
}

return {
	"olimorris/codecompanion.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-treesitter/nvim-treesitter",
		"stevearc/dressing.nvim",
		"nvim-telescope/telescope.nvim",
	},
	opts = {
		strategies = {
			chat = { adapter = "ollama" },
			inline = { adapter = "ollama" },
		},
		adapters = {
			http = {
				ollama = function()
					return require("codecompanion.adapters").extend("ollama", {
						env = { url = "http://127.0.0.1:11434" },
						schema = {
							model = { default = "qwen2.5-coder:7b" },
						},
					})
				end,
				glm = function()
					return require("codecompanion.adapters").extend("openai_compatible", {
						env = {
							url = "https://api.z.ai/api/coding/paas/v4/",
							chat_url = "chat/completions",
							api_key = env.GLM_API_KEY,
						},
						schema = {
							model = { default = "glm-5-turbo" },
						},
						handlers = think_stripped_inline,
					})
				end,
				minimax = function()
					return require("codecompanion.adapters").extend("openai_compatible", {
						env = {
							url = "https://api.minimaxi.com/v1/",
							chat_url = "chat/completions",
							api_key = env.MINIMAX_API_KEY,
						},
						schema = {
							model = { default = "MiniMax-M2.7-highspeed" },
						},
						handlers = think_stripped_inline,
					})
				end,
				opts = {
					show_presets = false,
				},
			},
			acp = {
				opencode = function()
					return require("codecompanion.adapters").extend("opencode", {})
				end,
			},
		},
		display = {
			chat = {
				window = {
					layout = "vertical",
					border = "rounded",
					width = 0.35,
				},
			},
		},
	},
}
