local Config = require("pose.config")
local Log = require("pose.log")

local M = {}

--- Build base URL from config
--- @return string
local function base_url()
    local conf = Config.options.server
    return string.format("http://%s:%d", conf.host, conf.port)
end

--- Execute an async HTTP request via curl
--- @param method string "GET"|"POST"|"DELETE"|"PATCH"
--- @param path string e.g. "/session"
--- @param body table|nil JSON body for POST/PATCH
--- @param cb fun(err: string|nil, data: table|nil)
function M.request(method, path, body, cb)
    local url = base_url() .. path

    local cmd = {
        "curl",
        "-s",
        "-X",
        method,
        "-H",
        "Content-Type: application/json",
        "-w",
        "\n__HTTP_STATUS__%{http_code}",
    }

    if body then
        local ok, json = pcall(vim.json.encode, body)
        if not ok then
            vim.schedule(function()
                cb("Failed to encode JSON: " .. tostring(json), nil)
            end)
            return
        end
        table.insert(cmd, "-d")
        table.insert(cmd, json)
    end

    table.insert(cmd, url)

    Log.debug(string.format("API %s %s", method, path))

    vim.system(cmd, { text = true }, function(obj)
        vim.schedule(function()
            local stdout = obj.stdout or ""

            -- Extract HTTP status code from the marker we appended
            local raw_body, status_str = stdout:match("^(.-)__HTTP_STATUS__(%d+)%s*$")
            if not raw_body then
                raw_body = stdout
                status_str = nil
            end

            local status = tonumber(status_str) or 0

            if obj.code ~= 0 and status == 0 then
                local err_msg = string.format("curl failed (exit %d): %s", obj.code, obj.stderr or "")
                Log.error(err_msg)
                cb(err_msg, nil)
                return
            end

            -- 204 No Content
            if status == 204 then
                cb(nil, nil)
                return
            end

            if status >= 400 then
                local err_msg = string.format("HTTP %d: %s", status, raw_body)
                Log.error(err_msg)
                cb(err_msg, nil)
                return
            end

            -- Parse JSON response
            raw_body = vim.trim(raw_body)
            if raw_body == "" then
                cb(nil, nil)
                return
            end

            local parse_ok, data = pcall(vim.json.decode, raw_body)
            if not parse_ok then
                local err_msg = "Failed to parse response JSON: " .. tostring(data)
                Log.error(err_msg)
                cb(err_msg, nil)
                return
            end

            cb(nil, data)
        end)
    end)
end

-- ---------------------------------------------------------------------------
-- Global
-- ---------------------------------------------------------------------------

--- GET /global/health
--- @param cb fun(err: string|nil, data: table|nil)
function M.health(cb)
    M.request("GET", "/global/health", nil, cb)
end

-- ---------------------------------------------------------------------------
-- Sessions
-- ---------------------------------------------------------------------------

--- POST /session — create a new session
--- @param title string|nil
--- @param cb fun(err: string|nil, data: table|nil)
function M.session_create(title, cb)
    local body = {}
    if title then
        body.title = title
    end
    M.request("POST", "/session", body, cb)
end

--- GET /session/:id
--- @param session_id string
--- @param cb fun(err: string|nil, data: table|nil)
function M.session_get(session_id, cb)
    M.request("GET", "/session/" .. session_id, nil, cb)
end

--- GET /session
--- @param cb fun(err: string|nil, data: table|nil)
function M.session_list(cb)
    M.request("GET", "/session", nil, cb)
end

--- DELETE /session/:id
--- @param session_id string
--- @param cb fun(err: string|nil, data: table|nil)
function M.session_delete(session_id, cb)
    M.request("DELETE", "/session/" .. session_id, nil, cb)
end

--- GET /session/status
--- @param cb fun(err: string|nil, data: table|nil)
function M.session_status(cb)
    M.request("GET", "/session/status", nil, cb)
end

--- POST /session/:id/abort
--- @param session_id string
--- @param cb fun(err: string|nil, data: table|nil)
function M.session_abort(session_id, cb)
    M.request("POST", "/session/" .. session_id .. "/abort", nil, cb)
end

--- POST /session/:id/revert
--- @param session_id string
--- @param message_id string
--- @param cb fun(err: string|nil, data: table|nil)
function M.session_revert(session_id, message_id, cb)
    M.request("POST", "/session/" .. session_id .. "/revert", { messageID = message_id }, cb)
end

--- GET /session/:id/diff
--- @param session_id string
--- @param cb fun(err: string|nil, data: table|nil)
function M.session_diff(session_id, cb)
    M.request("GET", "/session/" .. session_id .. "/diff", nil, cb)
end

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------

--- Build message body from parts and opts
--- @param parts table[] e.g. {{type="text", text="Hello"}}
--- @param opts table|nil { model?: table, noReply?: boolean, agent?: string }
--- @return table
local function build_message_body(parts, opts)
    opts = opts or {}
    local body = { parts = parts }
    if opts.model then
        body.model = opts.model
    end
    if opts.noReply then
        body.noReply = opts.noReply
    end
    if opts.agent then
        body.agent = opts.agent
    end
    return body
end

--- POST /session/:id/message — send message, wait for full response
--- @param session_id string
--- @param parts table[]
--- @param opts table|nil { model?: table, noReply?: boolean, agent?: string }
--- @param cb fun(err: string|nil, data: table|nil)
function M.session_message(session_id, parts, opts, cb)
    local body = build_message_body(parts, opts)
    M.request("POST", "/session/" .. session_id .. "/message", body, cb)
end

--- POST /session/:id/prompt_async — send message, return immediately (204)
--- @param session_id string
--- @param parts table[]
--- @param opts table|nil { model?: table, noReply?: boolean, agent?: string }
--- @param cb fun(err: string|nil, data: table|nil)
function M.session_prompt_async(session_id, parts, opts, cb)
    local body = build_message_body(parts, opts)
    M.request("POST", "/session/" .. session_id .. "/prompt_async", body, cb)
end

--- GET /session/:id/message — list all messages
--- @param session_id string
--- @param cb fun(err: string|nil, data: table|nil)
function M.session_messages(session_id, cb)
    M.request("GET", "/session/" .. session_id .. "/message", nil, cb)
end

--- GET /session/:id/message/:messageID
--- @param session_id string
--- @param message_id string
--- @param cb fun(err: string|nil, data: table|nil)
function M.session_message_get(session_id, message_id, cb)
    M.request("GET", "/session/" .. session_id .. "/message/" .. message_id, nil, cb)
end

-- ---------------------------------------------------------------------------
-- Config / Providers
-- ---------------------------------------------------------------------------

--- GET /config/providers
--- @param cb fun(err: string|nil, data: table|nil)
function M.providers(cb)
    M.request("GET", "/config/providers", nil, cb)
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Split "provider/model" string into API format
--- @param model_str string e.g. "anthropic/claude-sonnet-4"
--- @return table { providerID: string, modelID: string }
function M.parse_model(model_str)
    local provider, model = model_str:match("^([^/]+)/(.+)$")
    if not provider then
        return { providerID = model_str, modelID = model_str }
    end
    return { providerID = provider, modelID = model }
end

return M
