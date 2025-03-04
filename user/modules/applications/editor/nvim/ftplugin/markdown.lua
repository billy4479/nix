require("quarto").activate()

local kernel_path = vim.env.HOME .. "/.local/share/jupyter/runtime/"
local find_kernels = function()
	local kernels = {}
	for name, type in vim.fs.dir(kernel_path, {}) do
		if type == "file" and name:match("kernel-[%w%d-]+.json") then
			print("Found " .. name)
			table.insert(kernels, name)
		end
	end
	return kernels
end

vim.api.nvim_create_user_command("JupyterFindKernels", function()
	local kernels = find_kernels()
	if #kernels == 0 then
		print("No kernel found")
	end
end, {})

vim.api.nvim_create_user_command("JupyterKillAllKernels", function()
	vim.system({ "pkill", "jupyter-kernel" }, {}, nil):wait()
	print("Done")
end, {})

vim.api.nvim_create_user_command("JupyterStartKernel", function()
	local kernels = find_kernels()
	if #kernels == 1 then
		vim.cmd.MoltenInit(kernel_path .. kernels[1])
		print("Connected to " .. kernel_path .. kernels[1])
	elseif #kernels == 0 then
		vim.system({ "jupyter", "kernel", "--kernel=python3" }, {}, function(result)
			print("Jupyter kernel died??")
			print(result)
		end)
		print("Python kernel is starting")

		local connect_to_kernel
		connect_to_kernel = function()
			kernels = find_kernels()
			print(table.concat(kernels, "\n"))
			if #kernels == 1 then
				vim.cmd.MoltenInit(kernel_path .. kernels[1])
				print("Connected to " .. kernel_path .. kernels[1])
			else
				print("No kernels available yet, retrying in 100ms")
				vim.defer_fn(connect_to_kernel, 100)
			end
		end

		vim.defer_fn(connect_to_kernel, 100)
	else
		print("More than one kernel!")
	end
end, {})
