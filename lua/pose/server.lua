local Config = require("pose.config")
local Log = require("pose.log")

local M = {}

local state = {
    pid = nil,
    running = false,
}

local function get_pid_file()
    return vim.fn.stdpath("cache") .. "/pose_server.pid"
end

local function write_pid_file(pid)
    local f = io.open(get_pid_file(), "w")
    if f then
        f:write(tostring(pid))
        f:close()
    end
end

local function read_pid_file()
    local f = io.open(get_pid_file(), "r")
    if f then
        local content = f:read("*a")
        f:close()
        return tonumber(content)
    end
    return nil
end

local function delete_pid_file()
    os.remove(get_pid_file())
end

local function check_port_open(port, host, cb)
    local client = vim.loop.new_tcp()
    if not client then
        cb(false)
        return
    end

    client:connect(host, port, function(err)
        local is_open = not err
        client:shutdown()
        client:close()
        vim.schedule(function()
            cb(is_open)
        end)
    end)
end

function M.get_status()
    return state
end

function M.check_running(cb)
    local conf = Config.options.server
    check_port_open(conf.port, conf.host, function(is_open)
        state.running = is_open
        if is_open and not state.pid then
            state.pid = read_pid_file()
        end
        if cb then
            cb(is_open)
        end
    end)
end

function M.start(cb)
    local conf = Config.options.server

    M.check_running(function(running)
        if running then
            Log.info("Servidor ya está corriendo en puerto " .. conf.port)
            if cb then
                cb(true, "Already running")
            end
            return
        end

        Log.info("Iniciando opencode serve...")

        local cmd = { conf.opencode_command, "serve", "--port", tostring(conf.port), "--hostname", conf.host }

        local handle, pid = vim.loop.spawn(cmd[1], {
            args = { unpack(cmd, 2) },
            detached = true,
        }, function(code, signal)
            state.running = false
            if state.pid == pid then
                state.pid = nil
            end
            delete_pid_file()
            Log.warn("Servidor opencode se detuvo. Code: " .. code .. " Signal: " .. signal)
        end)

        if not handle then
            local err_msg = string.format(
                "[Pose] Failed to start 'opencode serve'\n\n" ..
                "Command: %s\n\n" ..
                "Troubleshooting:\n" ..
                "1. Ensure 'opencode' is installed and in PATH\n" ..
                "2. Run: opencode --version\n" ..
                "3. Check :PoseLogs for details\n" ..
                "4. Try manually: opencode serve --port %d",
                table.concat(cmd, " "),
                conf.port
            )
            Log.error(err_msg)
            vim.notify(err_msg, vim.log.levels.ERROR)
            if cb then
                cb(false, err_msg)
            end
            return
        end

        state.pid = pid
        write_pid_file(pid)

        local retries = 0
        local max_retries = 20
        local timer = vim.loop.new_timer()

        timer:start(250, 250, function()
            check_port_open(conf.port, conf.host, function(is_open)
                if is_open then
                    timer:stop()
                    timer:close()
                    state.running = true
                    Log.info("Servidor iniciado correctamente (PID: " .. pid .. ")")
                    if cb then
                        cb(true, "Started")
                    end
                else
                    retries = retries + 1
                    if retries >= max_retries then
                        timer:stop()
                        timer:close()
                        vim.loop.kill(pid, 15)
                        local err_msg = string.format(
                            "[Pose] OpenCode server failed to start within 5 seconds\n\n" ..
                            "Possible causes:\n" ..
                            "1. Port %d is already in use\n" ..
                            "2. OpenCode API key not configured\n" ..
                            "3. Network/firewall blocking localhost:%d\n\n" ..
                            "Run :checkhealth pose for diagnostics",
                            conf.port,
                            conf.port
                        )
                        Log.error(err_msg)
                        vim.notify(err_msg, vim.log.levels.ERROR)
                        if cb then
                            cb(false, err_msg)
                        end
                    end
                end
            end)
        end)
    end)
end

function M.stop()
    local pid_to_kill = state.pid or read_pid_file()
    
    if pid_to_kill then
        local ret = vim.loop.kill(pid_to_kill, 15) 
        if ret ~= 0 then
            os.execute("kill -9 " .. pid_to_kill .. " > /dev/null 2>&1")
        end
        Log.info("Servidor detenido (PID: " .. pid_to_kill .. ")")
        
        state.pid = nil
        delete_pid_file()
    end

    if vim.fn.executable("lsof") == 1 then
        local conf = Config.options.server or { port = 4096 }
        local cmd = string.format("lsof -t -i :%d", conf.port)
        local output = vim.fn.system(cmd)

        if output and output ~= "" then
            local port_pid = tonumber(vim.trim(output))
            if port_pid and port_pid ~= pid_to_kill then
                vim.loop.kill(port_pid, 9)
                Log.info("Servidor zombie eliminado via lsof (PID: " .. port_pid .. ")")
            end
        end
    end
    
    state.running = false
end

function M.ensure_running(cb)
    M.check_running(function(running)
        if running then
            cb(true)
        elseif Config.options.server.auto_start then
            M.start(function(success)
                cb(success)
            end)
        else
            Log.warn("Servidor no encontrado y auto_start desactivado")
            cb(false)
        end
    end)
end

return M
