-- Headless driver for the `fmt` CLI: formats files with the exact same
-- conform.nvim setup the interactive Neovim config uses (see
-- plugins/format.nix), including treesitter-injected code blocks.
--
-- Invoked by the `fmt` wrapper as:
--   nvim --headless -l fmt.lua <file>...
-- The wrapper expands directories (git-aware); this script receives files.

local function eprint(msg)
	io.stderr:write(msg .. "\n")
end

-- Batch mode stays conform-only: never let LSP servers spawn per buffer.
-- Interactive formatting falls back to LSP only when a conform formatter is
-- missing, which here means the project didn't provide its tools anyway.
vim.lsp.enable = function() end
vim.lsp.start = function() return nil end

-- `nvim -l` neither loads plugins nor sources the user config, so do all
-- three startup steps explicitly: plugins, user init.lua, and filetype
-- detection (without it every buffer opens with an empty filetype).
vim.cmd("silent! packloadall")
if not vim.env.MYVIMRC or vim.env.MYVIMRC == "" then
	local init = vim.fs.joinpath(vim.fn.stdpath("config"), "init.lua")
	if vim.uv.fs_stat(init) then
		vim.cmd("silent! source " .. vim.fn.fnameescape(init))
	end
end
vim.cmd("silent! filetype on")

local conform = require("conform")

-- Surface a misconfigured runtime instead of silently skipping everything.
if vim.tbl_isempty(conform.formatters_by_ft) then
	eprint("fmt: warning: no formatters configured in the nvim config (formatters_by_ft is empty)")
end

-- conform's own "no formatters found" notify is noisy in a batch run; the
-- missing-formatter warning below replaces it.
conform.notify_no_formatters = false

local stats = {
	formatted = 0,
	unchanged = 0,
	skipped = 0,
	no_formatters = 0,
	errors = 0,
}

-- Cheap check before opening a buffer, so we don't load binaries and other
-- files that can't possibly have formatters. The authoritative check
-- (conform.list_formatters_for_buffer) happens after opening.
local function looks_supported(path)
	local ft = vim.filetype.match({ filename = path })
	if not ft then
		local ok, head = pcall(vim.fn.readblob, path, 0, 4096)
		if ok then
			ft = vim.filetype.match({ filename = path, contents = vim.split(tostring(head), "\n") })
		end
	end
	return ft ~= nil
end

local function format_file(path)
	if not looks_supported(path) then
		stats.skipped = stats.skipped + 1
		return
	end

	local ok, err = pcall(vim.cmd, "silent edit! " .. vim.fn.fnameescape(path))
	if not ok then
		stats.errors = stats.errors + 1
		eprint("fmt: cannot open " .. path .. ": " .. tostring(err))
		return
	end
	local bufnr = vim.api.nvim_get_current_buf()

	local configured = conform.list_formatters_for_buffer(bufnr)
	if #configured == 0 then
		stats.skipped = stats.skipped + 1
		vim.api.nvim_buf_delete(bufnr, { force = true })
		return
	end

	local available = conform.list_formatters(bufnr)
	if #available < #configured then
		stats.no_formatters = stats.no_formatters + 1
		local names = {}
		for _, info in ipairs(available) do
			table.insert(names, info.name)
		end
		eprint(
			"fmt: formatters not found for "
				.. path
				.. " (configured: "
				.. table.concat(configured, ", ")
				.. ", available: "
				.. table.concat(names, ", ")
				.. "); projects should provide them in their flake devShell"
		)
		vim.api.nvim_buf_delete(bufnr, { force = true })
		return
	end

	local format_opts = {
		bufnr = bufnr,
		async = false,
		lsp_format = "never",
		-- we surface formatter errors ourselves, with the file name attached
		quiet = true,
	}
	local cb_err = nil
	local ran, run_err = pcall(conform.format, format_opts, function(err, _did_edit)
		cb_err = err
	end)
	if not ran then
		stats.errors = stats.errors + 1
		eprint("fmt: formatting failed for " .. path .. ": " .. tostring(run_err))
		vim.api.nvim_buf_delete(bufnr, { force = true })
		return
	end
	if cb_err then
		stats.errors = stats.errors + 1
		local msg = cb_err
		if type(msg) == "table" then
			msg = msg.message or vim.inspect(msg)
		end
		msg = tostring(msg):gsub("\27%[[%d;]*m", "")
		eprint("fmt: formatter error in " .. path .. ": " .. msg)
		vim.api.nvim_buf_delete(bufnr, { force = true })
		return
	end

	if vim.bo[bufnr].modified then
		-- noautocmd: skip BufWritePre (the interactive autoformat hook) and
		-- BufWritePost (linters) that fire on a regular :write. :write still
		-- applies the usual fileformat/fileencoding conversions.
		local wrote, write_err = pcall(vim.cmd, "silent noautocmd write")
		if wrote and not vim.bo[bufnr].modified then
			stats.formatted = stats.formatted + 1
			eprint("fmt: formatted " .. path)
		else
			stats.errors = stats.errors + 1
			eprint("fmt: cannot write " .. path .. ": " .. tostring(write_err))
		end
	else
		stats.unchanged = stats.unchanged + 1
	end

	vim.api.nvim_buf_delete(bufnr, { force = true })
end

local paths = _G.arg or {}
for i = 1, #paths do
	format_file(paths[i])
end

eprint(
	("fmt: %d formatted, %d unchanged, %d skipped, %d missing formatters, %d errors"):format(
		stats.formatted,
		stats.unchanged,
		stats.skipped,
		stats.no_formatters,
		stats.errors
	)
)

io.stderr:flush()
os.exit(stats.errors == 0 and 0 or 1)
