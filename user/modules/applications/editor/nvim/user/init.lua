return {
	colorscheme = "catppuccin",

	plugins = {
		{
			"catppuccin/nvim",
			name = "catppuccin",
			config = function()
				require("catppuccin").setup({
					flavour = "frappe",
					transparent_background = true,
				})
			end,
		},
		{
			"max397574/better-escape.nvim",
			name = "better-escape.nvim",
			config = function()
				require("better_escape").setup()
			end,
		},
	},
}
