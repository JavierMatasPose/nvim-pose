-- Health check for nvim-pose
-- Run with :checkhealth pose

local M = {}

local function check_executable(cmd)
  return vim.fn.executable(cmd) == 1
end

local function check_file_exists(path)
  return vim.fn.filereadable(path) == 1
end

local function get_opencode_version()
  local obj = vim.system({ "opencode", "--version" }, { text = true }):wait()
  if obj.code ~= 0 then
    return nil
  end
  return vim.trim(obj.stdout)
end

function M.check()
  vim.health.start("nvim-pose health check")

  -- Check opencode CLI
  if check_executable("opencode") then
    vim.health.ok("opencode CLI found in PATH")
    local version = get_opencode_version()
    if version and version ~= "" then
      vim.health.info("Version: " .. version)
    end
  else
    vim.health.error(
      "opencode CLI not found in PATH",
      {
        "Install from https://opencode.ai",
        "Ensure opencode is in your PATH",
      }
    )
  end

  -- Check opencode.json in current directory
  local cwd = vim.fn.getcwd()
  local config_path = cwd .. "/opencode.json"
  if check_file_exists(config_path) then
    vim.health.ok("opencode.json found in current directory: " .. config_path)

    -- Try to parse it
    local ok, config_content = pcall(vim.fn.readfile, config_path)
    if ok then
      local parse_ok, config = pcall(vim.json.decode, table.concat(config_content, "\n"))
      if parse_ok then
        vim.health.ok("opencode.json is valid JSON")

        -- Check permissions
        if config.permission then
          if config.permission.edit then
            vim.health.ok("Edit permissions configured")
          else
            vim.health.warn(
              "No edit permissions found",
              { 'Add "edit": { "$PWD/**": "allow" } to opencode.json' }
            )
          end

          if config.permission.write then
            vim.health.ok("Write permissions configured")
          else
            vim.health.warn(
              "No write permissions found",
              { 'Add "write": { "$PWD/**": "allow" } to opencode.json' }
            )
          end
        else
          vim.health.error(
            "No permissions configured in opencode.json",
            {
              "Add permission block to opencode.json",
              "See :help pose-config for examples",
            }
          )
        end
      else
        vim.health.error("opencode.json is invalid JSON", { "Check for syntax errors" })
      end
    end
  else
    vim.health.warn(
      "opencode.json not found in current directory",
      {
        "Create opencode.json in your project root",
        "Required for :PoseEdit to work",
        "See :help pose-config for template",
      }
    )
  end

  -- Check prompts.json in plugin directory
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
  local prompts_path = plugin_root .. "/prompts.json"
  if check_file_exists(prompts_path) then
    vim.health.ok("prompts.json found in plugin directory")
  else
    vim.health.error(
      "prompts.json missing from plugin directory",
      {
        "Reinstall the plugin or restore prompts.json",
        "Expected at: " .. prompts_path,
      }
    )
  end

  -- Check state directory
  local state_dir = vim.fn.stdpath("state")
  if vim.fn.isdirectory(state_dir) == 1 then
    vim.health.ok("State directory exists: " .. state_dir)
  else
    vim.health.warn("State directory not found", { "Will be created on first use" })
  end

  -- Check if server is running
  local log = require("pose.log")
  local server_module_ok, server = pcall(require, "pose.server")
  if server_module_ok then
    local status = server.get_status()
    if status.pid then
      vim.health.ok("opencode serve is running (PID: " .. status.pid .. ")")
    else
      vim.health.info("opencode serve not currently running (will start automatically)")
    end
  end

  -- Check for common port conflicts
  if vim.fn.executable("lsof") == 1 then
    local obj = vim.system({ "lsof", "-i", ":4096" }, { text = true }):wait()
    if obj.code == 0 and obj.stdout and obj.stdout ~= "" then
      vim.health.warn(
        "Port 4096 is in use",
        {
          "Another process may be using the default port",
          "Configure a different port in setup() if needed",
        }
      )
    end
  end

  -- Check nvim version
  local nvim_version = vim.version()
  if nvim_version.minor >= 10 then
    vim.health.ok(
      string.format("Neovim version %d.%d.%d", nvim_version.major, nvim_version.minor, nvim_version.patch)
    )
  else
    vim.health.error(
      "Neovim version too old",
      { "nvim-pose requires Neovim >= 0.10", "Current: " .. vim.version() }
    )
  end
end

return M
