local M = {}

local Config = require("pose.config")
local Log = require("pose.log")
local Server = require("pose.server")
local Client = require("pose.client")
local UI = require("pose.ui")
local Spinner = require("pose.spinner")
local History = require("pose.history")
local Prompts = require("pose.prompts")

-- Registro de peticiones activas para evitar colisiones visuales
-- Key: "buf_id:line_num" -> Value: spinner_instance
local active_spinners = {}

--- @param args table|nil Configuración opcional del usuario
function M.setup(args)
    Config.setup(args)
    Log.setup()

    vim.api.nvim_create_user_command("PoseServerStop", function()
        M.server_stop()
    end, {})

    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            M.server_stop()
        end,
    })

    Log.debug("Plugin nvim-pose inicializado. Esperando primer comando.")
end

function M.info()
    if not Config.options or not Config.options.server then
        Config.setup()
    end

    local server_status = Server.get_status()
    local config_info = Config.options

    print("=== Pose Status ===")
    print("Server Running: " .. tostring(server_status.running))
    if server_status.pid then
        print("PID: " .. server_status.pid)
    end

    if config_info and config_info.server then
        print("Port: " .. config_info.server.port)
    else
        print("Port: Unknown (Config not loaded)")
    end
end

function M.chat(opts)
    opts = opts or {}
    Server.ensure_running(function(running)
        if not running then
            Log.error("No se pudo iniciar el servidor. Revisa los logs.")
            return
        end

        -- Capturamos el buffer/linea ACTUALES antes de abrir la ventana flotante
        local current_buf = vim.api.nvim_get_current_buf()
        local current_line = vim.api.nvim_win_get_cursor(0)[1] - 1
        local spinner_key = string.format("%d:%d", current_buf, current_line)

        local selection_text = nil
        if opts.range and opts.range > 0 then
            local start_line = opts.line1 - 1
            local end_line = opts.line2
            local lines = vim.api.nvim_buf_get_lines(current_buf, start_line, end_line, false)
            if lines and #lines > 0 then
                selection_text = table.concat(lines, "\n")
            end
        end

        UI.prompt_with_model({
            title = " Pose Chat ",
            on_confirm = function(prompt, model)
                if prompt == "" then
                    return
                end

                local final_prompt = prompt
                if selection_text then
                    local filetype = vim.bo[current_buf].filetype or ""
                    final_prompt = Prompts.chat_context(prompt, filetype, selection_text)
                end

                if active_spinners[spinner_key] then
                    active_spinners[spinner_key]:stop()
                    active_spinners[spinner_key] = nil
                end

                local spinner = Spinner.new(current_buf, current_line)
                spinner:start("Pose: Pensando...")
                active_spinners[spinner_key] = spinner
                
                local file_path = vim.api.nvim_buf_get_name(current_buf)
                local req_id = History.start_request("chat", file_path, current_line + 1, final_prompt)

                Client.run(final_prompt, model, function(err, response)
                    vim.schedule(function()
                        if active_spinners[spinner_key] then
                            active_spinners[spinner_key]:stop()
                            active_spinners[spinner_key] = nil
                        end
                    end)

                    if err then
                        History.complete_request(req_id, "error", err)
                        vim.schedule(function()
                            UI.show_error("Error del servidor:\n" .. err)
                        end)
                        Log.error("Error en chat: " .. err)
                    else
                        History.complete_request(req_id, "success", response)
                        vim.schedule(function()
                            UI.show_result(response)
                        end)
                    end
                end)
            end,
            on_cancel = function()
                Log.debug("Chat cancelado por usuario.")
            end,
        })
    end)
end

function M.edit(opts)
    opts = opts or {}
    Server.ensure_running(function(running)
        if not running then
            Log.error("No se pudo iniciar el servidor. Revisa los logs.")
            return
        end

        local current_buf = vim.api.nvim_get_current_buf()
        local file_path = vim.api.nvim_buf_get_name(current_buf)
        if file_path == "" then
            Log.error("El buffer no tiene nombre. Guarda el archivo primero.")
            return
        end

        local current_line = vim.api.nvim_win_get_cursor(0)[1] - 1
        local spinner_key = string.format("edit:%d:%d", current_buf, current_line)

        local selection_info = ""
        local context_lines = ""

        if opts.range and opts.range > 0 then
            local start_line = opts.line1
            local end_line = opts.line2
            selection_info = string.format("Lines %d-%d", start_line, end_line)
            local lines = vim.api.nvim_buf_get_lines(current_buf, start_line - 1, end_line, false)
            if lines and #lines > 0 then
                context_lines = table.concat(lines, "\n")
            end
        else
            selection_info = string.format("Cursor at line %d", current_line + 1)
        end

        UI.prompt_with_model({
            title = " Pose Edit ",
            on_confirm = function(prompt, model)
                if prompt == "" then
                    return
                end

                if active_spinners[spinner_key] then
                    active_spinners[spinner_key]:stop()
                    active_spinners[spinner_key] = nil
                end

                local spinner = Spinner.new(current_buf, current_line)
                spinner:start("Pose: Editando archivo...")
                active_spinners[spinner_key] = spinner

                local final_prompt = Prompts.edit_request(
                    file_path,
                    selection_info,
                    context_lines,
                    prompt
                )

                local req_id = History.start_request("edit", file_path, current_line + 1, final_prompt)

                Client.run(final_prompt, model, function(err, response)
                    vim.schedule(function()
                        if active_spinners[spinner_key] then
                            active_spinners[spinner_key]:stop()
                            active_spinners[spinner_key] = nil
                        end

                        if err then
                            History.complete_request(req_id, "error", err)
                            UI.show_error("Error en edición:\n" .. err)
                        else
                            History.complete_request(req_id, "success", response)
                            vim.cmd("checktime " .. current_buf)
                            print("Pose: Edición completada. Buffer recargado.")
                        end
                    end)
                end)
            end,
            on_cancel = function()
                Log.debug("Edición cancelada por usuario.")
            end,
        })
    end)
end

function M.server_stop()
    for key, spinner in pairs(active_spinners) do
        if spinner then
            spinner:stop()
        end
        active_spinners[key] = nil
    end

    Server.stop()
end

function M.server_start()
    Server.ensure_running(function(running)
        if running then
            vim.schedule(function()
                print("Servidor Pose iniciado/verificado correctamente.")
            end)
        else
            vim.schedule(function()
                Log.error("Fallo al iniciar el servidor Pose.")
            end)
        end
    end)
end

function M.logs()
    local log_file = require("pose.log").get_path()
    if not log_file then
        print("Pose: No log file configured.")
        return
    end

    if vim.fn.filereadable(log_file) == 0 then
        print("Pose: Log file does not exist yet: " .. log_file)
        return
    end

    vim.cmd("tabnew " .. log_file)
    vim.cmd("normal! G")
end

function M.to_qf()
    local entries = History.get_all()
    if #entries == 0 then
        print("Pose: Historial vacío.")
        return
    end

    local items = {}
    for _, entry in ipairs(entries) do
        local type_char = (entry.status == "error") and "E" or "I"
        
        local summary = entry.prompt
        if entry.type == "edit" then
            local user_instr = entry.prompt:match("USER INSTRUCTION:\n(.-)\n\nSYSTEM DIRECTIVE")
            if user_instr then
                summary = user_instr
            end
        end
        
        summary = summary:gsub("\n", " "):sub(1, 100)

        table.insert(items, {
            filename = entry.file,
            lnum = entry.line,
            text = string.format("[%s] %s", entry.type:upper(), summary),
            type = type_char
        })
    end

    vim.fn.setqflist({}, "r", { title = "Pose Request History", items = items })
    vim.cmd("copen")
end

function M.history()
    local entry = History.get_latest()
    if entry then
        UI.show_history_entry(entry)
    else
        print("Pose: No history available.")
    end
end

return M

