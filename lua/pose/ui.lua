local M = {}

local Config = require("pose.config")
local Models = require("pose.models")
local State = require("pose.state")

--- @param opts table { width: number, height: number, title: string, title_pos: string }
--- @return number buf, number win
local function create_centered_window(opts)
    local width = math.floor(vim.o.columns * (opts.width or 0.6))
    local height = math.floor(vim.o.lines * (opts.height or 0.6))

    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local buf = vim.api.nvim_create_buf(false, true)

    local win_opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = Config.options.ui.border or "rounded",
        title = opts.title or " Pose ",
        title_pos = opts.title_pos or "center",
    }

    local win = vim.api.nvim_open_win(buf, true, win_opts)

    return buf, win
end

--- @param opts table { on_confirm: fun(text: string), on_cancel: fun() }
function M.prompt(opts)
    local ui_conf = Config.options.ui
    local buf, win = create_centered_window({
        width = ui_conf.width,
        height = ui_conf.height,
        title = " Prompt Pose: ",
    })

    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].bufhidden = "wipe"

    vim.cmd("startinsert")

    local function close()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    local function confirm()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local text = table.concat(lines, "\n")
        close()
        if opts.on_confirm then
            opts.on_confirm(text)
        end
    end

    local function cancel()
        close()
        if opts.on_cancel then
            opts.on_cancel()
        end
    end

    local map_opts = { noremap = true, silent = true, buffer = buf }

    vim.keymap.set("n", "<CR>", confirm, map_opts)
    vim.keymap.set("i", "<CR>", confirm, map_opts)
    vim.keymap.set("n", "<Esc>", cancel, map_opts)
end

function M.prompt_with_model(opts)
    opts = opts or {}
    local ui_conf = Config.options.ui
    local models = Models.get_available()
    
    local current_model_idx = 1
    local last_model = State.get_last_model()
    if last_model then
        for i, model in ipairs(models) do
            if model == last_model then
                current_model_idx = i
                break
            end
        end
    end
    
    local function get_title()
        local base_title = opts.title or " Pose Prompt "
        return string.format("%s | Model: %s", base_title, models[current_model_idx])
    end
    
    local buf, win = create_centered_window({
        width = ui_conf.width,
        height = ui_conf.height,
        title = get_title(),
    })

    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].bufhidden = "wipe"

    vim.cmd("startinsert")

    local function update_title()
        vim.api.nvim_win_set_config(win, { title = get_title() })
    end

    local function close()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    local function confirm()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local prompt_text = table.concat(lines, "\n")
        local selected_model = models[current_model_idx]
        
        State.set_last_model(selected_model)
        
        close()
        if opts.on_confirm then
            opts.on_confirm(prompt_text, selected_model)
        end
    end

    local function cancel()
        close()
        if opts.on_cancel then
            opts.on_cancel()
        end
    end

    local function cycle_model_next()
        current_model_idx = (current_model_idx % #models) + 1
        update_title()
    end

    local function cycle_model_prev()
        current_model_idx = current_model_idx - 1
        if current_model_idx < 1 then
            current_model_idx = #models
        end
        update_title()
    end

    local map_opts = { noremap = true, silent = true, buffer = buf }

    vim.keymap.set("n", "<CR>", confirm, map_opts)
    vim.keymap.set("i", "<CR>", confirm, map_opts)
    vim.keymap.set("n", "<Esc>", cancel, map_opts)
    vim.keymap.set("n", "<Tab>", cycle_model_next, map_opts)
    vim.keymap.set("i", "<Tab>", cycle_model_next, map_opts)
    vim.keymap.set("n", "<S-Tab>", cycle_model_prev, map_opts)
    vim.keymap.set("i", "<S-Tab>", cycle_model_prev, map_opts)
end

--- @param text string
function M.show_result(text)
    local ui_conf = Config.options.ui
    local buf, win = create_centered_window({
        width = ui_conf.width,
        height = ui_conf.height,
        title = " Pose Result ",
    })

    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].bufhidden = "wipe"

    local lines = vim.split(text, "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    vim.bo[buf].modifiable = false

    local map_opts = { noremap = true, silent = true, buffer = buf }
    vim.keymap.set("n", "<Esc>", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, map_opts)
    vim.keymap.set("n", "q", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, map_opts)
end

--- @param msg string
function M.show_error(msg)
    local buf, win = create_centered_window({
        width = 0.4,
        height = 0.2,
        title = " Pose Error ",
    })

    local lines = vim.split(msg, "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    local map_opts = { noremap = true, silent = true, buffer = buf }
    vim.keymap.set("n", "<Esc>", function()
        vim.api.nvim_win_close(win, true)
    end, map_opts)
    vim.keymap.set("n", "q", function()
        vim.api.nvim_win_close(win, true)
    end, map_opts)
end

function M.show_history_entry(entry)
    local buf, win = create_centered_window({
        width = 0.8,
        height = 0.8,
        title = string.format(" Request #%d (%s) ", entry.id, entry.type:upper()),
    })

    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].bufhidden = "wipe"

    local content = {}
    
    local function append_text(text)
        if not text or text == "" then return end
        local lines = vim.split(text, "\n")
        for _, line in ipairs(lines) do
            table.insert(content, line)
        end
    end

    table.insert(content, string.format("**File:** `%s:%d`", entry.file, entry.line))
    table.insert(content, string.format("**Time:** %s", os.date("%Y-%m-%d %H:%M:%S", entry.timestamp)))
    table.insert(content, string.format("**Status:** %s", entry.status))
    table.insert(content, "")
    table.insert(content, "## Prompt")
    table.insert(content, "```")
    append_text(entry.prompt)
    table.insert(content, "```")
    table.insert(content, "")
    table.insert(content, "## Response")
    if entry.response then
        append_text(entry.response)
    else
        table.insert(content, "*No response captured*")
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
    vim.bo[buf].modifiable = false

    local map_opts = { noremap = true, silent = true, buffer = buf }
    local function close()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    vim.keymap.set("n", "<Esc>", close, map_opts)
    vim.keymap.set("n", "q", close, map_opts)

    vim.keymap.set("n", "n", function()
        local next_entry = require("pose.history").get_next(entry.id)
        if next_entry then
            close()
            M.show_history_entry(next_entry)
        else
            print("No newer requests.")
        end
    end, map_opts)

    vim.keymap.set("n", "p", function()
        local prev_entry = require("pose.history").get_prev(entry.id)
        if prev_entry then
            close()
            M.show_history_entry(prev_entry)
        else
            print("No older requests.")
        end
    end, map_opts)
end

return M
