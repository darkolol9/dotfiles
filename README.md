# dotfiles

tmux configuration, keybindings and plugin declarations, synced across machines.

## Install on a new machine

```sh
git clone <this repo> ~/dotfiles
~/dotfiles/install.sh
tmux                    # then: prefix + I   (installs plugins, first run only)
```

`install.sh` symlinks everything under `home/` into `$HOME`, clones TPM if it is
missing, and reloads systemd user units. Anything already in place that is not
one of our symlinks is renamed to `*.backup.<timestamp>` rather than clobbered.

The prefix is `Ctrl-Space`.

## What is tracked

| path | what it is |
| --- | --- |
| `home/.tmux.conf` | all config, keybindings, `@plugin` declarations |
| `home/.local/bin/tmux-sessions` | fzf session manager (`prefix + s`) |
| `home/.local/bin/tmux-resurrect-save` | single-flight wrapper around resurrect's save |
| `home/.local/bin/tmux-copy` | clipboard shim: X11 / Wayland / macOS / WSL |
| `home/.config/systemd/user/tmux.service` | starts a detached server at boot |

## What is deliberately not tracked

**Sessions.** `~/.local/share/tmux/resurrect/` holds tmux-resurrect's snapshots
and is gitignored. Sessions stay machine-local by design; only configuration
syncs. Those files also record the full command line and working directory of
every pane, which is not something to push to a remote.

**Plugin code.** `~/.tmux/plugins/` is four separate git clones that TPM owns.
The portable part is the `set -g @plugin` lines in `.tmux.conf`; `prefix + I`
rebuilds the clones from them.

## Session manager

`prefix + s` opens an fzf picker in a popup.

| key | action |
| --- | --- |
| `Tab` | mark / unmark a session |
| `Ctrl-A` / `Ctrl-O` | mark all / unmark all, respecting the current filter |
| `Ctrl-X` | kill everything marked; confirms for more than one |
| `Enter` | switch to the session |
| `Ctrl-N` / `Ctrl-R` | new / rename |
| `Ctrl-T` | toggle preview |

Also `prefix + S` for tmux's native tree and `prefix + X` to kill the current
session.

## Pane flash

Moving focus between panes briefly tints the body of the pane you land on, so
it is obvious which one is selected. Tunable in `.tmux.conf`:

```tmux
set -g @pane_flash_style 'bg=#1e3a5f'   # the tint
set -g @pane_rest_style  'default'      # what it returns to
set -g @pane_flash_ms    '150'          # how long
```

It is driven by the `after-select-pane` hook, so it covers every route into a
pane: the Alt-arrow bindings, `prefix` + arrow, and mouse clicks.

Two things to know. It tints via `window-active-style`, which sets the pane's
*default* background, so it shows wherever the running program has not painted
its own -- a shell tints completely, a full-screen TUI like vim or htop tints
little or not at all. And it deliberately does not flash
`pane-active-border-style`: tmux draws a border only where two panes meet, so a
pane against the window edge has no outline there and a border flash reads as a
partial bracket rather than a highlight.

## Why tmux-resurrect-save exists

`save.sh` names its output file to the second and ends with:

```sh
if files_differ "$new" "$last"; then ln -fs "$new" "$last"; else rm "$new"; fi
```

Two saves in the same second compute the same path. The first writes it and
points `last` at it; the second rewrites the identical file, compares it against
`last` -- which by then *is* that file -- finds no difference, and deletes it.
`last` is left dangling and nothing is ever restored.

A `session-closed` hook fires once per closing session, so a bulk kill or a
server shutdown makes that collision a certainty. Everything therefore saves
through `tmux-resurrect-save`, which uses `flock -n` to let exactly one save run
per burst, on the trailing edge so it captures the final state. Nothing should
ever call `save.sh` directly.
