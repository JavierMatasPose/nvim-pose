local M = {}

local function get_state_file()
    return vim.fn.stdpath("state") .. "/pose_state.json"
end

function M.get_last_model()
    local file_path = get_state_file()
    
    if vim.fn.filereadable(file_path) == 0 then
        return nil
    end
    
    local f = io.open(file_path, "r")
    if not f then
        return nil
    end
    
    local content = f:read("*a")
    f:close()
    
    if not content or content == "" then
        return nil
    end
    
    local ok, data = pcall(vim.json.decode, content)
    if not ok or not data or not data.last_model then
        return nil
    end
    
    return data.last_model
end

function M.set_last_model(model)
    local file_path = get_state_file()
    local dir = vim.fn.fnamemodify(file_path, ":h")
    vim.fn.mkdir(dir, "p")
    
    local data = { last_model = model }
    local json = vim.json.encode(data)
    
    local f = io.open(file_path, "w")
    if f then
        f:write(json)
        f:close()
    end
end

return M
