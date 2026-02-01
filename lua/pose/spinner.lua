local M = {}

local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local interval = 80 -- ms

--- @class Spinner
--- @field buf number Buffer ID
--- @field line number Linea (0-indexed)
--- @field timer userdata|nil uv_timer
--- @field frame_idx number
--- @field ns_id number Namespace ID
--- @field extmark_id number|nil
local Spinner = {}
Spinner.__index = Spinner

--- @param buf number Buffer donde mostrarlo (nil = actual)
--- @param line number Línea donde mostrarlo (nil = cursor actual)
function M.new(buf, line)
    local self = setmetatable({}, Spinner)
    self.buf = buf or vim.api.nvim_get_current_buf()
    self.line = line or (vim.api.nvim_win_get_cursor(0)[1] - 1)
    self.frame_idx = 1
    self.ns_id = vim.api.nvim_create_namespace("pose_spinner")
    return self
end

--- Inicia la animación
function Spinner:start(msg)
    if self.timer then
        return
    end

    msg = msg or "Generando..."
    self.timer = vim.loop.new_timer()

    self.timer:start(
        0,
        interval,
        vim.schedule_wrap(function()
            if not vim.api.nvim_buf_is_valid(self.buf) then
                self:stop()
                return
            end

            local icon = frames[self.frame_idx]
            self.frame_idx = (self.frame_idx % #frames) + 1

            local text = icon .. " " .. msg

            local opts = {
                id = self.extmark_id,
                virt_text = { { text, "Comment" } },
                virt_text_pos = "eol", -- Al final de la línea
            }

            self.extmark_id = vim.api.nvim_buf_set_extmark(self.buf, self.ns_id, self.line, 0, opts)
        end)
    )
end

--- Detiene y limpia el spinner
function Spinner:stop()
    if self.timer then
        self.timer:stop()
        self.timer:close()
        self.timer = nil
    end

    if vim.api.nvim_buf_is_valid(self.buf) then
        vim.api.nvim_buf_clear_namespace(self.buf, self.ns_id, 0, -1)
    end
end

return M
