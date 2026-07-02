# AGENTS.md — steel-lsp-picker

This document describes the architecture of `steel-lsp-picker` and serves as a guide for future contributors using LLM agents to extend the plugin.

## Architecture at a glance

The plugin is a hand-rolled Helix component (no external UI library). It uses `new-component!` / `push-component!` from `helix/components` to place a floating picker on the compositor.

```
┌─────────────────┐
│ lsp-picker.scm  │  Public command `lsp-picker`, event handler
│  (commands)     │  routes keys → state mutations + side-effects
└────────┬────────┘
         │ uses
         ▼
┌─────────────────┐        ┌─────────────────┐
│  lsp-ui.scm     │        │  lsp-input.scm  │
│ (render-lsp-    │        │  (Input struct, │
│  picker,        │        │   key handling) │
│  cursor)        │        └─────────────────┘
└────────┬────────┘
         │ uses
         ▼
┌─────────────────┐
│ lsp-state.scm   │
│ (LspEntry,      │
│  LspPickerState,│
│  log reader,    │
│  buffer opener) │
└─────────────────┘
```

## File responsibilities

| File             | Scope                                                                                     |
|------------------|-------------------------------------------------------------------------------------------|
| `cog.scm`        | Forge package manifest. No external UI library dependency.                                |
| `lsp-input.scm`  | `Input` struct: text box + cursor. `Input-press` maps key events → 'changed/'moved/'ignore. |
| `lsp-state.scm`  | Data model: `LspEntry`, `LspPickerState`. Client fetch/filter, log reading (`lsp-read-log`), `open-lsp-log-in-buffer!`, config knobs. |
| `lsp-ui.scm`     | Rendering only: `render-lsp-picker` (picker box, input line, LSP list, help line), `get-lsp-picker-cursor`. No event logic. |
| `lsp-picker.scm` | Public command `lsp-picker`, event handler (`handle-event`), restart/stop helpers.        |
| `README.md`      | User docs.                                                                                 |
| `AGENTS.md`      | This file.                                                                                 |

## Key bindings inside the picker

| Key  | Action                                          |
|------|-------------------------------------------------|
| ↑/↓  | Navigate list                                   |
| r    | Restart selected LSP, close picker              |
| s    | Stop selected LSP, close picker                 |
| l    | Open selected LSP's log in a scratch buffer     |
| Esc  | Close picker                                    |
| text | Routed to `Input-press` for filter editing      |

## Extending the plugin

1. **New key action** — add a `cond` branch in `handle-event` in `lsp-picker.scm` that checks `key-event-char`. Call whatever side-effect you need (state mutation, Helix command, etc.) and return `event-result/close` or `event-result/consume`.
2. **New per-item info in the list** — extend `render-lsp-list` in `lsp-ui.scm`.
3. **Different log content** — change `lsp-read-log` in `lsp-state.scm` (currently `grep -i <name> <log-path> | tail -100`).
4. **New data source** — swap `lsp-fetch-clients` / `lsp-filter-clients` in `lsp-state.scm` and update `LspPickerState` fields accordingly.

### Example: adding a "copy LSP name to clipboard" key (`c`)

1. `lsp-picker.scm` — add a branch in `handle-event`:
   ```scheme
   ((and (key-event-char event) (char=? (key-event-char event) #\c)
         (not (key-event-modifier event)))
    (let ([name (lsp-selected-name state)])
      (when name (set-register! #\+ (list name))))
    event-result/close)
   ```
2. `lsp-ui.scm` — update `render-help-line` to mention `c:copy-name`.
3. `README.md` — document the new key.

## Key API references

| Symbol                        | Module                    | Purpose                                            |
|-------------------------------|---------------------------|----------------------------------------------------|
| `get-active-lsp-clients`      | `helix/misc.scm`          | List LSP client handles for current buffer         |
| `lsp-client-name`             | `helix/misc.scm`          | Get name string from client handle                 |
| `lsp-client-initialized?`     | `helix/misc.scm`          | Check if LSP has completed init                    |
| `lsp-restart`                 | `helix/commands.scm`      | Restart named LSP server                           |
| `lsp-stop`                    | `helix/commands.scm`      | Stop named LSP server                              |
| `new` (`:new`)                | `helix/commands.scm`      | Open a fresh scratch buffer (used for log opener)  |
| `insert_string`               | `helix/static.scm`        | Insert text at cursor                              |
| `set-scratch-buffer-name!`    | `helix/editor.scm`        | Name a scratch buffer                              |
| `new-component!`              | `helix/components`        | Create a compositor component                      |
| `push-component!`             | `helix/components`        | Push component onto the compositor                 |
| `event-result/close`          | `helix/components`        | Return from event handler to close the component   |
| `event-result/consume`        | `helix/components`        | Return from event handler to keep component open   |

## Historical notes

- **v0.2 (microscope.hx)** — the plugin briefly used microscope.hx for the picker UI. It was reverted because the log panel and custom key bindings (especially `l` for opening the log in a buffer) required the hand-rolled component approach.
- **Log I/O stays synchronous** — a prior `spawn-native-thread + hx.with-context` attempt froze the UI under LSP notification bursts. `lsp-read-log` remains synchronous; a typical `grep | tail -n 100` completes in <100ms.
