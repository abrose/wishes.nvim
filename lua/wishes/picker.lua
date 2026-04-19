local core = require("wishes.core")

local M = {}

local function has_snacks()
	return _G.Snacks ~= nil and _G.Snacks.picker ~= nil
end

local function has_telescope()
	return pcall(require, "telescope")
end

function M.build_entries(wishes, root)
	local entries = {}
	for _, wish in ipairs(wishes) do
		local range = wish.line_start == wish.line_end
				and tostring(wish.line_start)
			or (wish.line_start .. "-" .. wish.line_end)
		table.insert(entries, {
			wish = wish,
			abs_path = root .. "/" .. wish.path,
			display = string.format("[%s] %s:%s — %s", wish.category, wish.path, range, wish.text),
		})
	end
	return entries
end

local function resolve_preview_buf(ctx)
	if ctx.buf and vim.api.nvim_buf_is_valid(ctx.buf) then
		return ctx.buf
	end
	if ctx.preview and ctx.preview.buf and vim.api.nvim_buf_is_valid(ctx.preview.buf) then
		return ctx.preview.buf
	end
	if ctx.win then
		local ok, buf = pcall(vim.api.nvim_win_get_buf, ctx.win)
		if ok and vim.api.nvim_buf_is_valid(buf) then
			return buf
		end
	end
	return nil
end

local function make_preview(user_config, root)
	return function(ctx)
		local preview_mod = _G.Snacks and _G.Snacks.picker and _G.Snacks.picker.preview
		local result
		if preview_mod and preview_mod.file then
			result = preview_mod.file(ctx)
		end

		local buf = resolve_preview_buf(ctx)
		local item = ctx.item
		if not buf or not item or not item.wish then
			return result
		end

		local wishes_path = root .. "/" .. user_config.wishes_file
		local all_wishes = core.read_file_or_empty(wishes_path) or {}
		local for_file = {}
		for _, w in ipairs(all_wishes) do
			if w.path == item.wish.path then
				table.insert(for_file, w)
			end
		end

		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(buf) then
				require("wishes.display").render(buf, for_file, user_config)
			end
		end)

		return result
	end
end

local function show_snacks(user_config, root, entries)
	local items = {}
	for _, e in ipairs(entries) do
		table.insert(items, {
			wish = e.wish,
			file = e.abs_path,
			pos = { e.wish.line_start, 0 },
			text = e.display,
		})
	end

	_G.Snacks.picker.pick({
		source = "wishes",
		items = items,
		title = "Wishes",
		preview = make_preview(user_config, root),
		win = {
			input = {
				keys = {
					["<c-e>"] = { "wishes_edit", mode = { "n", "i" } },
					["<c-d>"] = { "wishes_delete", mode = { "n", "i" } },
				},
			},
		},
		actions = {
			wishes_edit = function(picker, item)
				picker:close()
				if item and item.wish then
					require("wishes").edit_wish(user_config, root, item.wish)
				end
			end,
			wishes_delete = function(picker, item)
				picker:close()
				if item and item.wish then
					require("wishes").delete_wish(user_config, root, item.wish)
				end
			end,
		},
	})
	return true
end

local function show_telescope(user_config, root, entries)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	pickers
		.new({}, {
			prompt_title = "Wishes",
			finder = finders.new_table({
				results = entries,
				entry_maker = function(e)
					return {
						value = e.wish,
						ordinal = e.wish.category .. " " .. e.wish.path .. " " .. e.wish.text,
						display = e.display,
						filename = e.abs_path,
						lnum = e.wish.line_start,
						col = 0,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = conf.grep_previewer({}),
			attach_mappings = function(prompt_bufnr, map)
				map({ "i", "n" }, "<C-e>", function()
					local selection = action_state.get_selected_entry()
					if not selection then
						return
					end
					actions.close(prompt_bufnr)
					require("wishes").edit_wish(user_config, root, selection.value)
				end)
				map({ "i", "n" }, "<C-d>", function()
					local selection = action_state.get_selected_entry()
					if not selection then
						return
					end
					actions.close(prompt_bufnr)
					require("wishes").delete_wish(user_config, root, selection.value)
				end)
				return true
			end,
		})
		:find()
	return true
end

function M.build_quickfix_items(entries)
	local items = {}
	for _, e in ipairs(entries) do
		table.insert(items, {
			filename = e.abs_path,
			lnum = e.wish.line_start,
			end_lnum = e.wish.line_end,
			text = e.display,
		})
	end
	return items
end

local function show_quickfix(entries)
	vim.fn.setqflist({}, "r", {
		title = "Wishes",
		items = M.build_quickfix_items(entries),
	})
	vim.cmd("copen")
	return true
end

function M.show(user_config, root)
	local wishes_path = root .. "/" .. user_config.wishes_file
	local wishes, err = core.read_file_or_empty(wishes_path)
	if not wishes then
		return nil, err
	end

	if #wishes == 0 then
		vim.notify("wishes: no wishes yet")
		return true
	end

	local entries = M.build_entries(wishes, root)

	if has_snacks() then
		return show_snacks(user_config, root, entries)
	end
	if has_telescope() then
		return show_telescope(user_config, root, entries)
	end
	return show_quickfix(entries)
end

return M
