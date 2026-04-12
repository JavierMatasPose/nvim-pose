local M = {}

local function get_state_file()
    return vim.fn.stdpath("state") .. "/pose_state.json"
end

local function read_state()
    local file_path = get_state_file()

    if vim.fn.filereadable(file_path) == 0 then
        return {}
    end

    local f = io.open(file_path, "r")
    if not f then
        return {}
    end

    local content = f:read("*a")
    f:close()

    if not content or content == "" then
        return {}
    end

    local ok, data = pcall(vim.json.decode, content)
    if not ok or not data then
        return {}
    end

    return data
end

local function write_state(data)
    local file_path = get_state_file()
    local dir = vim.fn.fnamemodify(file_path, ":h")
    vim.fn.mkdir(dir, "p")

    local json = vim.json.encode(data)

    local f = io.open(file_path, "w")
    if f then
        f:write(json)
        f:close()
    end
end

function M.get_last_model()
    local data = read_state()
    return data.last_model
end

function M.set_last_model(model)
    local data = read_state()
    data.last_model = model
    write_state(data)
end

--- @param project_path string
--- @return string|nil
function M.get_session(project_path)
    local data = read_state()
    if data.sessions and data.sessions[project_path] then
        return data.sessions[project_path]
    end
    return nil
end

--- @param project_path string
--- @param session_id string|nil
function M.set_session(project_path, session_id)
    local data = read_state()
    if not data.sessions then
        data.sessions = {}
    end
    data.sessions[project_path] = session_id
    write_state(data)
end

return M
