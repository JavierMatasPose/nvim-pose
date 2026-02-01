local M = {}

local prompts_config = nil

local function get_prompts_file()
    local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
    return plugin_root .. "/prompts.json"
end

function M.load()
    if prompts_config then
        return prompts_config
    end
    
    local file_path = get_prompts_file()
    
    if vim.fn.filereadable(file_path) == 0 then
        local err_msg = string.format(
            "[Pose] CRITICAL: prompts.json not found at: %s\n" ..
            "This file is required for the plugin to work.\n" ..
            "Reinstall the plugin or check the installation path.",
            file_path
        )
        vim.notify(err_msg, vim.log.levels.ERROR)
        error(err_msg)
    end
    
    local f = io.open(file_path, "r")
    if not f then
        local err_msg = "[Pose] CRITICAL: Failed to open prompts.json. Check file permissions."
        vim.notify(err_msg, vim.log.levels.ERROR)
        error(err_msg)
    end
    
    local content = f:read("*a")
    f:close()
    
    local ok, data = pcall(vim.json.decode, content)
    if not ok then
        local err_msg = string.format(
            "[Pose] CRITICAL: Failed to parse prompts.json: %s\n" ..
            "Check for JSON syntax errors in: %s",
            tostring(data),
            file_path
        )
        vim.notify(err_msg, vim.log.levels.ERROR)
        error(err_msg)
    end
    
    prompts_config = data
    return prompts_config
end

local function render_template(template, variables)
    local result = template
    for key, value in pairs(variables) do
        local placeholder = "{{" .. key .. "}}"
        result = result:gsub(placeholder, tostring(value or ""))
    end
    return result
end

function M.edit_request(file_path, selection_info, context_lines, user_instruction)
    local config = M.load()
    
    if not config.edit then
        error("[Pose] prompts.json is missing or invalid. Cannot generate edit request.")
    end
    
    return render_template(config.edit.template, {
        file_path = file_path,
        selection_info = selection_info,
        context_lines = context_lines,
        user_instruction = user_instruction,
        system_directive = config.edit.system_directive
    })
end

function M.chat_context(user_prompt, filetype, selection_text)
    local config = M.load()
    
    if not config.chat then
        error("[Pose] prompts.json is missing or invalid. Cannot generate chat context.")
    end
    
    return render_template(config.chat.context_template, {
        user_prompt = user_prompt,
        filetype = filetype,
        selection_text = selection_text
    })
end

return M
