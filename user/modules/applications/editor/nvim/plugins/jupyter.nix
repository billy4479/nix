{ pkgs, ... }:
{
  # https://github.com/benlubas/molten-nvim/blob/main/docs/NixOS.md#nixos-home-manager-installation
  # https://github.com/benlubas/molten-nvim/blob/main/docs/Notebook-Setup.md
  programs.neovim = {
    plugins = with pkgs.vimPlugins; [
      {
        plugin = otter-nvim;
        type = "lua";
        config = # lua
          ''
            require("otter").setup()
          '';
      }
      {
        plugin = molten-nvim;
        type = "lua";
        config = # lua
          ''
            -- Even if I use wezterm image.nvim is better, see
            -- https://github.com/benlubas/molten-nvim/tree/main?tab=readme-ov-file#images
            vim.g.molten_image_provider = "image.nvim"
          '';
      }
      {
        plugin = quarto-nvim;
        type = "lua";
        config = # lua
          ''
            local quarto = require("quarto")
            quarto.setup({
            	debug = false,
            	closePreviewOnExit = true,
            	lspFeatures = {
            		enabled = true,
            		chunks = "curly",
            		languages = { "python" },
            		diagnostics = {
            			enabled = true,
            			triggers = { "BufWritePost" },
            		},
            		completion = {
            			enabled = true,
            		},
            	},
            	codeRunner = {
            		enabled = true,
            		default_method = "molten", -- "molten", "slime", "iron" or <function>
            		ft_runners = {}, -- filetype to runner, ie. `{ python = "molten" }`.
            		-- Takes precedence over `default_method`
            		never_run = { "yaml" }, -- filetypes which are never sent to a code runner
            	},
            })
            vim.keymap.set("n", "<leader>qp", quarto.quartoPreview, { silent = true, noremap = true })

            -- https://github.com/benlubas/molten-nvim/blob/main/docs/Notebook-Setup.md#lsp-features-with-quarto-nvim
            local runner = require("quarto.runner")
            vim.keymap.set("n", "<leader>rc", runner.run_cell, { desc = "run cell", silent = true })
            vim.keymap.set("n", "<leader>ra", runner.run_above, { desc = "run cell and above", silent = true })
            vim.keymap.set("n", "<leader>rA", runner.run_all, { desc = "run all cells", silent = true })
            vim.keymap.set("n", "<leader>rl", runner.run_line, { desc = "run line", silent = true })
            vim.keymap.set("v", "<leader>r", runner.run_range, { desc = "run visual range", silent = true })
            vim.keymap.set("n", "<leader>RA", function()
            	runner.run_all(true)
            end, { desc = "run all cells of all languages", silent = true })
          '';
      }

      # {
      #   plugin = jupytext-nvim;
      #   type = "lua";
      #   config = # lua
      #     ''
      #       require("jupytext").setup({
      #       	style = "markdown",
      #       	output_extension = "md",
      #       	force_ft = "markdown",
      #       })
      #     '';
      # }
      {
        plugin = image-nvim;
        type = "lua";
        config = # lua
          ''
            require("image").setup({
            	backend = "kitty",

            	-- https://github.com/benlubas/molten-nvim/blob/main/docs/Not-So-Quick-Start-Guide.md#after-imagenvim-is-working
            	max_width = 120, -- tweak to preference
            	max_height = 15, -- ^
            	max_height_window_percentage = math.huge, -- this is necessary for a good experience
            	max_width_window_percentage = math.huge,

            	integrations = {
            		typst = {
            			enabled = false,
            			filetypes = { "typst" },
            		},
            	},
            })
          '';
      }
    ];
    extraPackages = with pkgs; [
      imagemagick # for image rendering

      # python3Packages.jupytext
    ];
    extraLuaPackages =
      ps: with ps; [
        magick # for image rendering
      ];
    extraPython3Packages =
      ps: with ps; [
        pynvim
        jupyter-client
        cairosvg # for image rendering
        pnglatex # for image rendering
        plotly # for image rendering
        pyperclip
      ];
  };
}
