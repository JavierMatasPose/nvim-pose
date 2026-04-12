local Config = require("pose.config")
local Log = require("pose.log")

local M = {}

--- @type table<number, {event_type: string, callback: fun(data: table), session_id: string|nil}>
local handlers = {}
local next_handler_id = 1
local job = nil
local buffer = ""
local state = "disconnected" --- @type "connected"|"disconnected"|"reconnecting"
local reconnect_timer = nil
local reconnect_delay = 1000 -- ms, doubles on failure, max 30000

--- Parse SSE frames from accumulated buffer
--- @param raw string
--- @return table[] frames, string remainder
local function parse_sse_frames(raw)
    local frames = {}
    local remainder = raw

    while true do
        local frame_end = remainder:find("\n\n")
        if not frame_end then
            break
        end

        local frame_str = remainder:sub(1, frame_end - 1)
        remainder = remainder:sub(frame_end + 2)

        local event_type = nil
        local data_str = nil

        for line in frame_str:gmatch("[^\n]+") do
            local key, value = line:match("^(%w+):%s*(.*)")
            if key == "event" then
                event_type = value
            elseif key == "data" then
                data_str = value
            end
        end

        if data_str then
            local ok, data = pcall(vim.json.decode, data_str)
            if ok then
                -- OpenCode server doesn't always send 'event:' lines.
                -- The event type is embedded in the JSON data.type field.
                local final_event_type = event_type or data.type or "unknown"
                table.insert(frames, { event_type = final_event_type, data = data })
            else
                Log.debug("SSE: failed to parse JSON data: " .. data_str)
            end
        end
    end

    return frames, remainder
end

--- Dispatch event to registered handlers
--- @param event_type string
--- @param data table
local function dispatch(event_type, data)
    Log.debug("SSE event: " .. event_type)
    local matched = false
    for _, handler in pairs(handlers) do
        if handler.event_type == event_type then
            matched = true
            local ok, err = pcall(handler.callback, data)
            if not ok then
                Log.error("SSE handler error for " .. event_type .. ": " .. tostring(err))
            end
        end
    end
    if not matched then
        Log.debug("SSE event unhandled: " .. event_type)
    end
end

--- Schedule reconnect with exponential backoff
local function schedule_reconnect()
    if state == "disconnected" then
        return
    end

    state = "reconnecting"
    Log.debug(string.format("SSE: reconnecting in %dms", reconnect_delay))

    reconnect_timer = vim.loop.new_timer()
    reconnect_timer:start(
        reconnect_delay,
        0,
        vim.schedule_wrap(function()
            if reconnect_timer then
                reconnect_timer:stop()
                reconnect_timer:close()
                reconnect_timer = nil
            end
            M.connect()
        end)
    )

    reconnect_delay = math.min(reconnect_delay * 2, 30000)
end

--- Start SSE connection to GET /event
function M.connect()
    if job then
        return
    end

    local conf = Config.options.server
    local url = string.format("http://%s:%d/event", conf.host, conf.port)

    Log.debug("SSE: connecting to " .. url)
    buffer = ""

    job = vim.system(
        { "curl", "-s", "-N", url },
        {
            text = true,
            stdout = function(_, data)
                if not data then
                    return
                end

                buffer = buffer .. data
                local frames, remainder = parse_sse_frames(buffer)
                buffer = remainder

                for _, frame in ipairs(frames) do
                    vim.schedule(function()
                        if frame.event_type == "server.connected" then
                            state = "connected"
                            reconnect_delay = 1000
                            Log.info("SSE: connected")
                        end
                        dispatch(frame.event_type, frame.data)
                    end)
                end
            end,
        },
        function(obj)
            -- Process exited (connection lost)
            vim.schedule(function()
                job = nil
                buffer = ""
                local was_connected = state == "connected"
                if state ~= "disconnected" then
                    if was_connected then
                        Log.warn("SSE: connection lost (exit " .. obj.code .. ")")
                    end
                    schedule_reconnect()
                end
            end)
        end
    )
end

--- Stop SSE connection and cancel any pending reconnect
function M.disconnect()
    state = "disconnected"

    if reconnect_timer then
        reconnect_timer:stop()
        reconnect_timer:close()
        reconnect_timer = nil
    end

    if job then
        job:kill("sigterm")
        job = nil
    end

    buffer = ""
    reconnect_delay = 1000
    Log.debug("SSE: disconnected")
end

--- Register handler for an event type
--- @param event_type string e.g. "session.idle", "message.part.updated"
--- @param callback fun(data: table)
--- @return number handler_id
function M.on(event_type, callback)
    local id = next_handler_id
    next_handler_id = next_handler_id + 1
    handlers[id] = {
        event_type = event_type,
        callback = callback,
        session_id = nil,
    }
    return id
end

--- Register handler scoped to a specific session
--- Events without matching sessionID are silently ignored.
--- @param event_type string
--- @param session_id string
--- @param callback fun(data: table)
--- @return number handler_id
function M.on_session(event_type, session_id, callback)
    local id = next_handler_id
    next_handler_id = next_handler_id + 1
    handlers[id] = {
        event_type = event_type,
        callback = function(data)
            local props = data.properties or data
            local sid = props.sessionID
                or (props.part and props.part.sessionID)
                or props.session_id
                or props.id
            if sid == session_id then
                callback(data)
            end
        end,
        session_id = session_id,
    }
    return id
end

--- Remove a specific handler by id
--- @param handler_id number
function M.off(handler_id)
    handlers[handler_id] = nil
end

--- Remove all handlers registered for a specific session
--- @param session_id string
function M.off_session(session_id)
    for id, handler in pairs(handlers) do
        if handler.session_id == session_id then
            handlers[id] = nil
        end
    end
end

--- Get current connection state
--- @return string "connected"|"disconnected"|"reconnecting"
function M.get_state()
    return state
end

return M
