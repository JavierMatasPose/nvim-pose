local M = {}
--- @class PoseConfig
local defaults = {
    -- Configuración de conexión con opencode serve
    server = {
        auto_start = true,
        opencode_command = "opencode",
        port = 4096,
        host = "127.0.0.1",
        timeout_ms = 5000,
    },
    -- Opciones de interfaz
    ui = {
        width = 0.6,
        height = 0.2,
        border = "rounded",
    },

    -- Debugging
    log = {
        level = "info", -- "debug", "info", "warn", "error"
        path = vim.fn.stdpath("state") .. "/pose.log",
    },
}
--- @type PoseConfig
M.options = {}
--- @param user_opts table|nil
function M.setup(user_opts)
    user_opts = user_opts or {}

    M.options = vim.tbl_deep_extend("force", defaults, user_opts)

    if M.options.server then
        local cmd = M.options.server.opencode_command
        if cmd and cmd ~= "opencode" then
            vim.notify(
                string.format(
                    "[Pose] WARNING: opencode_command set to '%s'. Only use 'opencode' or an absolute path to a trusted binary.",
                    cmd
                ),
                vim.log.levels.WARN
            )
        end

        local h = M.options.server.host
        if h and h ~= "127.0.0.1" and h ~= "localhost" and h ~= "::1" then
            vim.notify(
                string.format(
                    "[Pose] WARNING: server.host='%s' is not a loopback address. All communication is unencrypted and unauthenticated.",
                    h
                ),
                vim.log.levels.WARN
            )
        end
    end
end
return M
