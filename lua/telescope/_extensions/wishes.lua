local ok, telescope = pcall(require, "telescope")
if not ok then
	return {}
end

return telescope.register_extension({
	exports = {
		wishes = function(_)
			require("wishes").list()
		end,
	},
})
