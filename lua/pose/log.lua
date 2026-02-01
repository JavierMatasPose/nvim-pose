local Config = require("pose.config")
local M = {}

local levels = {
    debug = 1,
    info = 2,
    warn = 3,
    error = 4,
}

local notify_levels = {
    debug = vim.log.levels.DEBUG,
    info = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR,
}

local log_file_handle = nil

function M.get_path()
    if Config.options and Config.options.log and Config.options.log.path then
        return Config.options.log.path
    end
    return nil
end

--- @param level string "debug"|"info"|"warn"|"error"
--- @param msg string Mensaje a mostrar
local function log(level, msg)
    local config_level = "info"
    if Config.options and Config.options.log and Config.options.log.level then
        config_level = Config.options.log.level
    end

    if levels[level] < levels[config_level] then
        return
    end

    local prefix = "[Pose] "
    local formatted_msg = string.format("%s%s", prefix, msg)

    vim.schedule(function()
        vim.notify(formatted_msg, notify_levels[level])
    end)

    if log_file_handle then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        local file_msg = string.format("[%s] [%s] %s\n", timestamp, level:upper(), msg)
        log_file_handle:write(file_msg)
        log_file_handle:flush()
    end
end

function M.debug(msg)
    log("debug", msg)
end
function M.info(msg)
    log("info", msg)
end
function M.warn(msg)
    log("warn", msg)
end
function M.error(msg)
    log("error", msg)
end

function M.setup()
    local path = M.get_path()
    if path then
        local dir = vim.fn.fnamemodify(path, ":h")
        vim.fn.mkdir(dir, "p")

        local f, err = io.open(path, "a")
        if f then
            log_file_handle = f
            log_file_handle:write("\n=== Pose Session Start: " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
            log_file_handle:flush()
        else
            vim.notify("[Pose] No se pudo abrir log file: " .. tostring(err), vim.log.levels.WARN)
        end
    end
end

return M
