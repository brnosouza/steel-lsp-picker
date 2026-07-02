# steel-lsp-picker

A Helix plugin (Steel/Scheme) that opens a floating picker to manage LSP servers attached to the current buffer.

## Features

- **LSP picker** — lists every language server active on the current buffer with its status (`● ready` / `◌ initialising`)
- **Open log in buffer** — press `l` to filter the full Helix log for the selected LSP and open the result in a new buffer
- **Restart / Stop** — press `r` to restart or `s` to stop the selected LSP

## Requirements

- [Helix](https://github.com/mattwparas/helix) — the `steel-event-system` branch (mattwparas fork)
- Steel Scheme runtime (installed via `cargo xtask steel`)

## Installation

### With Forge (recommended)

```sh
forge pkg install --git https://github.com/brnosouza/steel-lsp-picker.git
```

Or, if you have this repo cloned locally, run `forge install` from its root.

### Manual

```sh
cp -r steel-lsp-picker ~/.config/helix/cogs/lsp-picker
```

## Setup

Add the following to your `~/.config/helix/helix.scm`:

```scheme
(require "lsp-picker/lsp-picker.scm")
(provide lsp-picker)
```

Then bind the command in your `~/.config/helix/init.scm`:

```scheme
(require "helix/keymaps.scm")

(add-global-keybinding
  (hash "normal" (hash "space" (hash "L" ":lsp-picker"))))
```

Reload config or restart Helix. Type `:lsp-picker` to open the picker.

## Keys (inside the picker)

| Key       | Action                                          |
|-----------|-------------------------------------------------|
| `↑` / `↓` | Navigate list                                   |
| `l`       | Open selected LSP's full log in a new buffer    |
| `r`       | Restart selected LSP and close                  |
| `s`       | Stop selected LSP and close                     |
| `Esc`     | Close picker                                    |

## How log opening works

Pressing `l`:
1. Runs `grep -i <lsp-name> <log-path>` (all matching lines, no cap) and writes
   the output to `/tmp/lsp-log-<name>.log`.
2. Opens that file in the editor with `:open`.

The file persists in `/tmp` across invocations. Pressing `l` again overwrites it
with fresh content.

## Configuration

All configuration goes in `~/.config/helix/init.scm`, before the picker is first opened.

### Log file path

```scheme
;; default: ~/.cache/helix/helix.log
(lsp-picker-set-log-path! "/custom/path/helix.log")
```

### Grep command

Pass a **string** (binary name) and standard `-i pattern file > tmpfile` args are
built for you — works for `grep`, `rg`, `ag`, and any tool with compatible flags:

```scheme
(lsp-picker-set-grep-cmd! "grep")  ; default
(lsp-picker-set-grep-cmd! "rg")    ; ripgrep
(lsp-picker-set-grep-cmd! "ag")    ; the silver searcher
```

Pass a **function** `(lsp-name log-path tmp-path) → pipeline-string` for full
control over the shell pipeline:

```scheme
(lsp-picker-set-grep-cmd!
  (lambda (name log-path tmp-path)
    (string-append "rg --case-sensitive " (sh-quote name)
                   " " (sh-quote log-path)
                   " > " (sh-quote tmp-path))))
```

## File layout

```
steel-lsp-picker/
├── cog.scm         # Forge package manifest
├── lsp-picker.scm  # Entry point — event handler + public command
├── lsp-state.scm   # Data: LspEntry, picker state, log pipeline, config knobs
├── lsp-ui.scm      # Rendering: picker box, LSP list, help line
└── README.md       # This file
```

## Development

To iterate without restarting Helix, use `:eval-buffer` or `:reload-all`.

## License

MIT
