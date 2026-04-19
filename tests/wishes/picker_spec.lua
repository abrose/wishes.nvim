local picker = require("wishes.picker")
local core = require("wishes.core")

describe("wishes.picker.build_entries", function()
	it("builds one entry per wish", function()
		local entries = picker.build_entries({
			{ category = "fix", path = "a.lua", line_start = 1, line_end = 1, text = "first" },
			{ category = "note", path = "b.lua", line_start = 10, line_end = 20, text = "range" },
		}, "/root")
		assert.equals(2, #entries)
	end)

	it("formats display with single-line range", function()
		local entries = picker.build_entries({
			{ category = "fix", path = "a.lua", line_start = 5, line_end = 5, text = "text" },
		}, "/root")
		assert.equals("[fix] a.lua:5 — text", entries[1].display)
	end)

	it("formats display with multi-line range", function()
		local entries = picker.build_entries({
			{ category = "refactor", path = "a.lua", line_start = 10, line_end = 20, text = "range" },
		}, "/root")
		assert.equals("[refactor] a.lua:10-20 — range", entries[1].display)
	end)

	it("computes an absolute path by joining root + wish.path", function()
		local entries = picker.build_entries({
			{ category = "fix", path = "src/a.lua", line_start = 42, line_end = 42, text = "t" },
		}, "/proj")
		assert.equals("/proj/src/a.lua", entries[1].abs_path)
	end)

	it("carries the original wish on entry.wish", function()
		local wish = { category = "fix", path = "a.lua", line_start = 1, line_end = 1, text = "t" }
		local entries = picker.build_entries({ wish }, "/root")
		assert.same(wish, entries[1].wish)
	end)
end)

describe("wishes.picker.build_quickfix_items", function()
	it("maps entries to quickfix-shaped items", function()
		local entries = picker.build_entries({
			{ category = "fix", path = "a.lua", line_start = 5, line_end = 5, text = "x" },
			{ category = "note", path = "b.lua", line_start = 10, line_end = 20, text = "y" },
		}, "/root")
		local items = picker.build_quickfix_items(entries)

		assert.equals(2, #items)
		assert.equals("/root/a.lua", items[1].filename)
		assert.equals(5, items[1].lnum)
		assert.equals(5, items[1].end_lnum)
		assert.equals("[fix] a.lua:5 — x", items[1].text)
		assert.equals(20, items[2].end_lnum)
	end)
end)

describe("wishes.picker.show", function()
	local tmp

	before_each(function()
		tmp = vim.fn.tempname()
		vim.fn.mkdir(tmp, "p")
	end)

	after_each(function()
		vim.fn.delete(tmp, "rf")
		vim.fn.setqflist({}, "r")
		pcall(vim.cmd, "cclose")
	end)

	it("notifies and returns true when there are no wishes", function()
		local notified
		local original = vim.notify
		vim.notify = function(msg)
			notified = msg
		end
		local ok = picker.show({ wishes_file = ".wishes.md" }, tmp)
		vim.notify = original

		assert.is_true(ok)
		assert.truthy(notified and notified:find("no wishes"))
	end)

	it("populates the quickfix list when neither snacks nor telescope is available", function()
		core.write_file(tmp .. "/.wishes.md", {
			{ category = "fix", path = "a.lua", line_start = 1, line_end = 1, text = "qf test" },
		})
		assert.is_true(picker.show({ wishes_file = ".wishes.md" }, tmp))

		local qf = vim.fn.getqflist({ title = 0, items = 0 })
		assert.equals("Wishes", qf.title)
		assert.equals(1, #qf.items)
		assert.truthy(qf.items[1].text:find("qf test"))
	end)
end)
