local M = {}

local Config = require("pose.config")
local Log = require("pose.log")
local Server = require("pose.server")
local Api = require("pose.api")
local Events = require("pose.events")
local Session = require("pose.session")
local UI = require("pose.ui")
local Spinner = require("pose.spinner")
local History = require("pose.history")
local Prompts = require("pose.prompts")

local active_spinners = {}

local function extract_delta_text(data)
    local props = data.properties or data
    -- v2: message.part.delta → properties.delta with properties.field == "text"
    if props.field == "text" and props.delta then
        return props.delta
    end
    -- v1: message.part.updated → properties.delta (optional incremental field)
    if props.delta and type(props.delta) == "string" then
        return props.delta
    end
    return nil
end

local function extract_error_message(data)
    local props = data.properties or data
    local err = props.error
    if not err then
        return "Unknown error"
    end
    if type(err) == "string" then
        return err
    end
    if err.data and err.data.message then
        return err.data.message
    end
    if err.name then
        return err.name
    end
    return vim.inspect(err)
end

--- @param args table|nil
function M.setup(args)
    Config.setup(args)
    Log.setup()

    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            M.server_stop()
        end,
    })

    Server.ensure_running(function(running)
        if running then
            Events.connect()
            Log.debug("nvim-pose initialized with SSE events.")
        else
            Log.debug("nvim-pose initialized (server not running).")
        end
    end)
end

function M.info()
    if not Config.options or not Config.options.server then
        Config.setup()
    end

    local server_status = Server.get_status()
    local config_info = Config.options
    local sse_state = Events.get_state()
    local session_id = Session.current()

    print("=== Pose Status ===")
    print("Server Running: " .. tostring(server_status.running))
    if server_status.pid then
        print("PID: " .. server_status.pid)
    end
    if config_info and config_info.server then
        print("Port: " .. config_info.server.port)
    end
    print("SSE: " .. sse_state)
    print("Session: " .. (session_id or "none"))
end

function M.chat(opts)
    opts = opts or {}
    Server.ensure_running(function(running)
        if not running then
            Log.error("Could not start server. Check logs.")
            return
        end

        if Events.get_state() ~= "connected" then
            Events.connect()
        end

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
                spinner:start("Pose: thinking...")
                active_spinners[spinner_key] = spinner

                local file_path = vim.api.nvim_buf_get_name(current_buf)
                local req_id = History.start_request("chat", file_path, current_line + 1, final_prompt)

                Session.ensure_session(function(session_id)
                    local parts = { { type = "text", text = final_prompt } }
                    local api_opts = { model = Api.parse_model(model) }

                    local result_buf, result_win = UI.open_streaming_result(function()
                        Api.session_abort(session_id, function() end)
                    end)

                    local handler_ids = {}
                    local accumulated_text = {}

                    local function on_streaming_delta(data)
                        local text = extract_delta_text(data)
                        if text then
                            table.insert(accumulated_text, text)
                            UI.append_streaming(result_buf, result_win, text)
                        end
                    end

                    -- v2: separate delta event
                    table.insert(handler_ids, Events.on_session("message.part.delta", session_id, on_streaming_delta))
                    -- v1: delta embedded in part.updated
                    table.insert(handler_ids, Events.on_session("message.part.updated", session_id, on_streaming_delta))

                    table.insert(handler_ids, Events.on_session("session.idle", session_id, function()
                        vim.schedule(function()
                            if active_spinners[spinner_key] then
                                active_spinners[spinner_key]:stop()
                                active_spinners[spinner_key] = nil
                            end

                            UI.finalize_streaming(result_buf, result_win)
                            History.complete_request(req_id, "success", table.concat(accumulated_text, ""))

                            for _, hid in ipairs(handler_ids) do
                                Events.off(hid)
                            end
                        end)
                    end))

                    table.insert(handler_ids, Events.on_session("session.error", session_id, function(data)
                        vim.schedule(function()
                            if active_spinners[spinner_key] then
                                active_spinners[spinner_key]:stop()
                                active_spinners[spinner_key] = nil
                            end

                            local err_msg = extract_error_message(data)
                            History.complete_request(req_id, "error", err_msg)
                            UI.finalize_streaming(result_buf, result_win)

                            for _, hid in ipairs(handler_ids) do
                                Events.off(hid)
                            end
                        end)
                    end))

                    Api.session_prompt_async(session_id, parts, api_opts, function(err)
                        if err then
                            vim.schedule(function()
                                if active_spinners[spinner_key] then
                                    active_spinners[spinner_key]:stop()
                                    active_spinners[spinner_key] = nil
                                end
                                History.complete_request(req_id, "error", err)
                                UI.show_error("Server error:\n" .. err)
                                for _, hid in ipairs(handler_ids) do
                                    Events.off(hid)
                                end
                            end)
                            Log.error("Chat error: " .. err)
                        end
                    end)
                end)
            end,
            on_cancel = function()
                Log.debug("Chat cancelled by user.")
            end,
        })
    end)
end

function M.edit(opts)
    opts = opts or {}
    Server.ensure_running(function(running)
        if not running then
            Log.error("Could not start server. Check logs.")
            return
        end

        if Events.get_state() ~= "connected" then
            Events.connect()
        end

        local current_buf = vim.api.nvim_get_current_buf()
        local file_path = vim.api.nvim_buf_get_name(current_buf)
        if file_path == "" then
            Log.error("Buffer has no name. Save the file first.")
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
                spinner:start("Pose: editing file...")
                active_spinners[spinner_key] = spinner

                local final_prompt = Prompts.edit_request(
                    file_path,
                    selection_info,
                    context_lines,
                    prompt
                )

                local req_id = History.start_request("edit", file_path, current_line + 1, final_prompt)

                Session.ensure_session(function(session_id)
                    local parts = { { type = "text", text = final_prompt } }
                    local api_opts = { model = Api.parse_model(model) }

                    local handler_ids = {}

                    table.insert(handler_ids, Events.on_session("session.idle", session_id, function()
                        vim.schedule(function()
                            if active_spinners[spinner_key] then
                                active_spinners[spinner_key]:stop()
                                active_spinners[spinner_key] = nil
                            end

                            History.complete_request(req_id, "success", "Edit completed")
                            vim.cmd("checktime " .. current_buf)
                            print("Pose: Edit complete. Buffer reloaded.")

                            for _, hid in ipairs(handler_ids) do
                                Events.off(hid)
                            end
                        end)
                    end))

                    table.insert(handler_ids, Events.on_session("session.error", session_id, function(data)
                        vim.schedule(function()
                            if active_spinners[spinner_key] then
                                active_spinners[spinner_key]:stop()
                                active_spinners[spinner_key] = nil
                            end

                            local err_msg = extract_error_message(data)
                            History.complete_request(req_id, "error", err_msg)
                            UI.show_error("Edit error:\n" .. err_msg)

                            for _, hid in ipairs(handler_ids) do
                                Events.off(hid)
                            end
                        end)
                    end))

                    Api.session_prompt_async(session_id, parts, api_opts, function(err)
                        if err then
                            vim.schedule(function()
                                if active_spinners[spinner_key] then
                                    active_spinners[spinner_key]:stop()
                                    active_spinners[spinner_key] = nil
                                end
                                History.complete_request(req_id, "error", err)
                                UI.show_error("Edit error:\n" .. err)
                                for _, hid in ipairs(handler_ids) do
                                    Events.off(hid)
                                end
                            end)
                            Log.error("Edit error: " .. err)
                        end
                    end)
                end)
            end,
            on_cancel = function()
                Log.debug("Edit cancelled by user.")
            end,
        })
    end)
end



function M.server_stop()
    Events.disconnect()

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
            Events.connect()
            vim.schedule(function()
                print("Pose: Server started/verified.")
            end)
        else
            vim.schedule(function()
                Log.error("Failed to start Pose server.")
            end)
        end
    end)
end

function M.abort()
    local session_id = Session.current()
    if session_id then
        Api.session_abort(session_id, function(err)
            vim.schedule(function()
                if err then
                    Log.error("Failed to abort: " .. err)
                else
                    print("Pose: Session aborted.")
                end
            end)
        end)
    else
        print("Pose: No active session.")
    end
end

function M.new_session()
    Session.new_session(function(id)
        vim.schedule(function()
            print("Pose: New session " .. id)
        end)
    end)
end

function M.sessions()
    Session.list(function(sessions)
        vim.schedule(function()
            if #sessions == 0 then
                print("Pose: No sessions found.")
                return
            end

            local items = {}
            for _, s in ipairs(sessions) do
                local title = s.title or s.id
                table.insert(items, title .. " [" .. s.id .. "]")
            end

            vim.ui.select(items, { prompt = "Select session:" }, function(_, idx)
                if idx then
                    local selected = sessions[idx]
                    Session.clear()
                    require("pose.state").set_session(vim.fn.getcwd(), selected.id)
                    print("Pose: Switched to session " .. selected.id)
                end
            end)
        end)
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
        print("Pose: History empty.")
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
