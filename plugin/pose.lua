if vim.g.loaded_pose then
    return
end
vim.g.loaded_pose = true

vim.api.nvim_create_user_command("PoseChat", function(opts)
    require("pose").chat(opts)
end, { range = true })

vim.api.nvim_create_user_command("PoseEdit", function(opts)
    require("pose").edit(opts)
end, { range = true })

vim.api.nvim_create_user_command("PoseLogs", function()
    require("pose").logs()
end, {})

vim.api.nvim_create_user_command("PoseToQf", function()
    require("pose").to_qf()
end, {})

vim.api.nvim_create_user_command("PoseHistory", function()
    require("pose").history()
end, {})

vim.api.nvim_create_user_command("PoseInfo", function()
    require("pose").info()
end, {})

vim.api.nvim_create_user_command("PoseServerStart", function()
    require("pose").server_start()
end, {})

vim.api.nvim_create_user_command("PoseServerStop", function()
    require("pose").server_stop()
end, {})

vim.api.nvim_create_user_command("PoseTestRequest", function()
    require("pose").test_request()
end, {})
