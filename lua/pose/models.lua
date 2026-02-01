local M = {}

local cached_models = nil

function M.get_available()
    if cached_models then
        return cached_models
    end

    local cmd = { "opencode", "models" }
    local result = vim.fn.system(cmd)
    
    if vim.v.shell_error ~= 0 then
        vim.notify("[Pose] Failed to get models: " .. result, vim.log.levels.WARN)
        return { "anthropic/claude-sonnet-4" }
    end

    local models = {}
    for line in result:gmatch("[^\r\n]+") do
        local trimmed = vim.trim(line)
        if trimmed ~= "" and not trimmed:match("^Available models:") and not trimmed:match("^%-%-%-") then
            table.insert(models, trimmed)
        end
    end

    if #models == 0 then
        models = { "anthropic/claude-sonnet-4" }
    end

    cached_models = models
    return models
end

function M.clear_cache()
    cached_models = nil
end

return M
