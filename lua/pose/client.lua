local Config = require("pose.config")
local Log = require("pose.log")

local M = {}

function M.run(prompt, model, cb)
    local conf = Config.options.server
    local url = "http://" .. conf.host .. ":" .. conf.port

    local cmd = {
        conf.opencode_command,
        "run",
        "--attach",
        url,
    }
    
    if model then
        table.insert(cmd, "--model")
        table.insert(cmd, model)
    end
    
    table.insert(cmd, prompt)

    Log.debug("Ejecutando cliente: " .. table.concat(cmd, " "))

    local stdout_data = {}
    local stderr_data = {}

    local job = vim.system(cmd, {
        text = true,
        stdout = function(err, data)
            if data then
                table.insert(stdout_data, data)
            end
        end,
        stderr = function(err, data)
            if data then
                table.insert(stderr_data, data)
            end
        end,
    }, function(obj)
        vim.schedule(function()
            local output = table.concat(stdout_data, "")
            local error_output = table.concat(stderr_data, "")

            if obj.code ~= 0 then
                local err_msg = string.format(
                    "[Pose] OpenCode CLI failed (exit code %d)\n" ..
                    "Command: %s\n" ..
                    "Error: %s\n\n" ..
                    "Troubleshooting:\n" ..
                    "1. Ensure 'opencode serve' is running (:PoseServerStart)\n" ..
                    "2. Check permissions in opencode.json\n" ..
                    "3. Run :checkhealth pose",
                    obj.code,
                    table.concat(cmd, " "),
                    error_output
                )
                Log.error(err_msg)
                vim.notify(err_msg, vim.log.levels.ERROR)
                if cb then
                    cb(err_msg, nil)
                end
            else
                Log.debug("Respuesta recibida (" .. #output .. " bytes)")
                if cb then
                    cb(nil, output)
                end
            end
        end)
    end)
end

return M
