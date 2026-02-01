# nvim-pose

AI-powered code editing directly from Neovim via OpenCode.

**nvim-pose** is a lightweight Neovim plugin that wraps the `opencode` CLI, enabling context-aware AI assistance for editing files and answering coding questions without leaving your editor.

## Features

- **Direct File Editing**: AI writes changes directly to disk, Neovim reloads automatically
- **Smart Context**: Sends visual selections and file context to AI
- **Model Selection**: Cycle through available models with `<Tab>` in chat window
- **Request History**: Navigate previous requests with `:PoseHistory`
- **Persistent Logging**: All interactions logged to `~/.local/state/nvim/pose.log`
- **Lazy Server**: `opencode serve` starts automatically when needed
- **Template System**: Customizable prompts via `prompts.json`

## Prerequisites

- Neovim >= 0.11
- [opencode](https://opencode.ai) CLI installed and configured
- OpenCode API key set up

## Installation

### lazy.nvim

```lua
{
  "JavierMatasPose/nvim-pose",
  config = function()
    require("pose").setup({
      -- Optional overrides
      server = {
        auto_start = true,
        port = 4096,
      },
      ui = {
        width = 0.6,
        height = 0.2,
        border = "rounded",
      },
    })
  end,
}
```

### packer.nvim

```lua
use {
  "JavierMatasPose/nvim-pose",
  config = function()
    require("pose").setup()
  end,
}
```

### Manual Installation

```bash
git clone https://github.com/JavierMatasPose/nvim-pose ~/.config/nvim/pack/plugins/start/nvim-pose
```

Add to your `init.lua`:

```lua
require("pose").setup()
```

## Configuration

### Required: OpenCode Permissions

Create `opencode.json` in your **project root** (NOT in the plugin directory):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "read": "allow",
    "edit": {
      "*": "deny",
      "$PWD/**": "allow"
    },
    "write": {
      "*": "deny",
      "$PWD/**": "allow"
    },
    "bash": {
      "*": "deny",
      "ls *": "allow",
      "cat *": "allow",
      "grep *": "allow",
      "find *": "allow",
      "git status": "allow",
      "git log *": "allow",
      "git diff *": "allow"
    }
  }
}
```

**Why this matters**: OpenCode requires explicit permissions to edit files. Without `opencode.json`, `:PoseEdit` will fail silently.

### Optional: Customize Prompts

The plugin includes default prompts in `prompts.json`. To customize:

1. Copy `prompts.json` from the plugin directory to your project
2. Edit templates (use `{{placeholders}}` for dynamic values)
3. Plugin loads project-local `prompts.json` if found, otherwise uses defaults

Example prompt customization:

```json
{
  "edit": {
    "template": "CUSTOM EDIT REQUEST\nFile: {{file_path}}\n{{context_lines}}\n\n{{user_instruction}}"
  }
}
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:PoseChat` | Open chat window (sends visual selection as context) |
| `:PoseEdit` | Edit current file based on visual selection + instruction |
| `:PoseLogs` | View persistent log file in new tab |
| `:PoseHistory` | Navigate request history (`n`/`p` to cycle, `<CR>` to rerun) |
| `:PoseToQf` | Export history to Quickfix list |
| `:PoseServerStart` | Manually start `opencode serve` |
| `:PoseServerStop` | Stop background server |
| `:PoseInfo` | Show server status (PID, port, uptime) |

### Workflow Examples

#### 1. Quick Code Chat

```vim
" Select code in visual mode
V
5j

" Ask a question
:PoseChat
" Type: "Explain this function"
```

#### 2. Direct File Editing

```vim
" Select code to modify
V
10j

" Request changes
:PoseEdit
" Type: "Refactor to use async/await"

" AI writes changes → Neovim reloads buffer automatically
```

#### 3. Model Selection

```vim
:PoseChat
" In the chat window:
" Press <Tab> to cycle through models
" Press <Shift-Tab> to go backwards
" Model shown in window title: " Pose Chat | Model: anthropic/claude-sonnet-4 "
```

#### 4. Review History

```vim
:PoseHistory
" Navigate with n/p
" Press <CR> to rerun a previous request
```

### Key Bindings (in Chat Window)

| Key | Action |
|-----|--------|
| `<CR>` | Send message |
| `<C-c>` / `<Esc>` | Close window |
| `<Tab>` | Next model |
| `<S-Tab>` | Previous model |

## How It Works

```
┌─────────────────────────────────────────────────────┐
│ Neovim (nvim-pose)                                  │
│  ├─ Visual selection → context                      │
│  ├─ User prompt → rendered via prompts.json         │
│  └─ Model selection → persisted in state.json       │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
          ┌────────────────────┐
          │ opencode serve     │ (lazy start on first request)
          │ :4096              │
          └────────┬───────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ opencode run --attach                               │
│  ├─ Sends prompt + context                          │
│  ├─ Receives streaming response                     │
│  └─ Writes files directly (via permissions)         │
└─────────────────────────────────────────────────────┘
                   │
                   ▼
          Files updated on disk
                   │
                   ▼
      Neovim reloads buffers (:checktime)
```

## Troubleshooting

### `:PoseEdit` does nothing

**Solution**: Check `opencode.json` permissions. Ensure `"edit": { "$PWD/**": "allow" }` is set.

### Server won't start

```vim
:PoseInfo
```

Check log output:

```vim
:PoseLogs
```

Common issues:
- `opencode` not in PATH
- Port 4096 already in use (change in config)
- OpenCode API key not configured

### Models not loading

Run manually:

```bash
opencode models
```

If this fails, check your OpenCode installation and API key.

### Permission denied errors

Verify `opencode.json` exists in your **project root** (not in the plugin directory).

## Advanced

### Custom Configuration

```lua
require("pose").setup({
  server = {
    auto_start = true,
    opencode_command = "opencode", -- Use custom path if needed
    port = 4096,
    timeout_ms = 10000, -- Increase for slow connections
  },
  ui = {
    width = 0.8,  -- 80% of screen width
    height = 0.3, -- 30% of screen height
    border = "double",
  },
  log = {
    level = "debug", -- More verbose logging
    path = vim.fn.expand("~/.pose-debug.log"),
  },
})
```

### Using with Multiple Projects

Each project needs its own `opencode.json`. Example structure:

```
~/projects/
├── project-a/
│   ├── opencode.json  ← Allows editing $PWD/project-a/**
│   └── src/
├── project-b/
│   ├── opencode.json  ← Allows editing $PWD/project-b/**
│   └── lib/
```

This prevents accidental cross-project edits.

## Development

### Testing

```bash
cd nvim-pose
nvim --headless -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
```

### Code Formatting

```bash
make fmt   # Format with stylua
make lint  # Check formatting
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Run `make fmt` before committing
4. Submit a pull request

## License

MIT

## Credits

Built as a lightweight interface to [OpenCode](https://opencode.ai).
Inspired by [99](https://github.com/ThePrimeagen/99) from ThePrimeagen.

---

