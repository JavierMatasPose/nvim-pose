local Api = require("pose.api")
local State = require("pose.state")
local Log = require("pose.log")

local M = {}

local current_session_id = nil

local function get_project_path()
    return vim.fn.getcwd()
end

--- @param cb fun(session_id: string)
function M.ensure_session(cb)
    if current_session_id then
        cb(current_session_id)
        return
    end

    local project = get_project_path()
    local stored_id = State.get_session(project)

    if stored_id then
        Api.session_get(stored_id, function(err, data)
            if not err and data and data.id then
                current_session_id = stored_id
                Log.debug("Resumed session " .. stored_id)
                cb(stored_id)
            else
                Log.debug("Stored session invalid, creating new")
                M.new_session(cb)
            end
        end)
    else
        M.new_session(cb)
    end
end

--- @param cb fun(session_id: string)
function M.new_session(cb)
    local project = get_project_path()
    local title = "nvim-pose: " .. vim.fn.fnamemodify(project, ":t")

    Api.session_create(title, function(err, data)
        if err then
            Log.error("Failed to create session: " .. err)
            return
        end
        current_session_id = data.id
        State.set_session(project, data.id)
        Log.info("Created session " .. data.id)
        cb(data.id)
    end)
end

--- @return string|nil
function M.current()
    return current_session_id
end

--- @param cb fun(sessions: table[])
function M.list(cb)
    Api.session_list(function(err, data)
        if err then
            Log.error("Failed to list sessions: " .. err)
            cb({})
            return
        end
        cb(data or {})
    end)
end

function M.clear()
    current_session_id = nil
    local project = get_project_path()
    State.set_session(project, nil)
end

return M
