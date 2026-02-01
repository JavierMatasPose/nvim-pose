local M = {}

local entries = {}
local current_id = 0

function M.start_request(type, file, line, prompt)
    current_id = current_id + 1
    local entry = {
        id = current_id,
        timestamp = os.time(),
        type = type,
        file = file,
        line = line,
        prompt = prompt,
        response = nil,
        status = "pending"
    }
    table.insert(entries, entry)
    return current_id
end

function M.complete_request(req_id, status, response)
    for _, entry in ipairs(entries) do
        if entry.id == req_id then
            entry.status = status
            entry.response = response
            return
        end
    end
end

function M.get(req_id)
    for _, entry in ipairs(entries) do
        if entry.id == req_id then
            return entry
        end
    end
    return nil
end

function M.get_latest()
    if #entries == 0 then return nil end
    return entries[#entries]
end

function M.get_all()
    return entries
end

function M.get_prev(current_req_id)
    for i = #entries, 1, -1 do
        if entries[i].id < current_req_id then
            return entries[i]
        end
    end
    return nil
end

function M.get_next(current_req_id)
    for i = 1, #entries do
        if entries[i].id > current_req_id then
            return entries[i]
        end
    end
    return nil
end

function M.clear()
    entries = {}
    current_id = 0
end

return M