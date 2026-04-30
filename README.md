# osc-relay.nvim

Forward OSC escape sequences from `:terminal` children out to the host terminal emulator. Lets nested tools (build scripts, AI agents, CLIs) drive the host's tab title, progress bar, and other terminal features that Neovim would otherwise swallow.

```
┌─────────────── Host terminal (e.g. Windows Terminal) ───────────────┐
│                                                                     │
│   nvim (TUI)                                                        │
│    ├── osc-relay.nvim                                               │
│    │      TermRequest → vim.uv.fs_write(2, bytes) ──┐               │
│    │                                                ▼               │
│    └── :terminal                                tab updates         │
│         └── opencode / build / lazygit / …                          │
│              └── emits OSC 9;4 (progress)                           │
└─────────────────────────────────────────────────────────────────────┘
```

## Why

Neovim's `:terminal` parses the child process's output stream and consumes OSC sequences itself. The host terminal never sees them. This plugin listens for the `TermRequest` autocmd (Neovim ≥ 0.10), filters by OSC selector, and re-emits the bytes from Neovim's own stderr — which *is* connected to the host terminal's pty.

Result: any tool running inside `:terminal` can control the host as if it were running natively.

## Requirements

- Neovim **≥ 0.10**
- A host terminal that understands the OSC sequences you forward. Tested:
  - **Windows Terminal** — full OSC 9;4 progress bar support
  - **iTerm2** — OSC 9 (notification), uses different progress conventions
  - **WezTerm** — OSC 9;4 supported
  - **tmux / zellij** — pass-through wrapping handled (see [Multiplexers](#multiplexers))

## Install

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "MoaidHathot/osc-relay.nvim",
  event = "VeryLazy",
  opts = {},
}
```

[packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use({
  "MoaidHathot/osc-relay.nvim",
  config = function() require("osc-relay").setup() end,
})
```

The plugin auto-bootstraps on startup with safe defaults. Calling `setup({})` is only needed if you want to override defaults.

## Default config

```lua
require("osc-relay").setup({
  enabled   = true,
  -- OSC selectors to forward. "*" = all.
  allow     = { "9;4" },         -- progress bar only by default
  deny      = {},
  -- "focused" = only the focused :terminal forwards (avoids races
  -- when several inner tools fight for the tab); "all" = last writer wins;
  -- function(buf) -> boolean for custom logic.
  scope     = "focused",
  -- Wrap in DCS passthrough when nested under tmux. "auto" detects
  -- $TMUX/$ZELLIJ; "off" disables wrapping.
  multiplex = "auto",
  -- Events that emit OSC 9;4;0;0 to clear the bar.
  reset_on  = { "TermClose", "VimLeavePre" },
  -- Fire User OscRelay autocmd alongside the host write.
  notify    = true,
  debug     = false,
})
```

## Recipes

### Reflect inner-process state in Windows Terminal tabs

If the inner tool already emits `OSC 9;4` (e.g. an [OpenCode](https://opencode.ai) plugin, `cargo` with a wrapper, a CI script), nothing to do — `osc-relay.nvim` forwards it.

To emit OSC 9;4 yourself from a shell, see the OSC 9;4 reference: state is one of `0` (clear), `1` (green progress), `2` (red error), `3` (pulsing yellow), `4` (solid yellow); percent is `0–100`:

```sh
printf '\e]9;4;3;0\e\\'    # pulsing yellow (working)
printf '\e]9;4;1;75\e\\'   # 75% green
printf '\e]9;4;0;0\e\\'    # clear
```

### Also forward titles

```lua
require("osc-relay").setup({ allow = { "0", "2", "9;4" } })
```

Note: this competes with Neovim's own title management. If you have `'title'` set, expect flicker between Neovim's title and the inner tool's. Default is off for that reason.

### Show same state inside Neovim (lualine example)

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "OscRelay",
  callback = function(ev)
    if ev.data.selector == "9;4" then
      local state = ev.data.sequence:match("9;4;(%d+)")
      local map = { ["0"] = "idle", ["1"] = "progress",
                    ["2"] = "error", ["3"] = "busy", ["4"] = "warn" }
      vim.g.osc_relay_state = map[state] or "idle"
      vim.cmd.redrawstatus()
    end
  end,
})
```

Then in lualine:

```lua
{ function() return vim.g.osc_relay_state or "" end }
```

### Disable for one buffer

```lua
require("osc-relay").disable(vim.api.nvim_get_current_buf())
```

### Manual relay

```lua
require("osc-relay").send("\27]0;custom title\27\\")
```

## Multiplexers

Under tmux, OSC sequences need DCS passthrough wrapping (`\ePtmux;…\e\\`) to traverse tmux's parser. `multiplex = "auto"` (default) detects `$TMUX` and wraps automatically. tmux config must allow it:

```tmux
set -g allow-passthrough on
```

Zellij has no general OSC passthrough mechanism. The plugin passes bytes through unwrapped; some sequences will reach the host, others (including OSC 9;4) will not. This is a zellij limitation.

## API

```lua
require("osc-relay").setup(opts)        -- merge opts and (re)attach autocmd
require("osc-relay").enable(buf?)       -- enable globally or per-buffer
require("osc-relay").disable(buf?)
require("osc-relay").send(bytes)        -- write bytes directly to host pty
require("osc-relay").status()           -- inspection table
```

## `User OscRelay` autocmd

Fired (when `notify = true`) for every forwarded sequence:

```lua
{
  selector = "9;4",
  sequence = "\27]9;4;3;0\27\\",
  buf      = 12,
}
```

## Health

```
:checkhealth osc-relay
```

Reports nvim version, `vim.uv.fs_write` availability, detected multiplexer, current config, and whether the `TermRequest` autocmd is registered.

## How it works

1. Neovim ≥ 0.10 fires the `TermRequest` autocmd whenever a `:terminal` child emits an OSC, DCS, or APC sequence. The full bytes are in `ev.data.sequence`.
2. We parse the OSC selector (`9;4`, `0`, `2`, …) and check it against `allow`/`deny`.
3. We check `scope` — by default only the focused `:terminal` buffer forwards.
4. We wrap in tmux passthrough if needed, then write the bytes to fd 2 (`vim.uv.fs_write(2, …)`), which is Neovim's stderr — connected to the host terminal's pty.
5. On `TermClose` or `VimLeavePre`, we emit `OSC 9;4;0;0` to clear the bar.

## License

[Unlicense](LICENSE) — public domain.
