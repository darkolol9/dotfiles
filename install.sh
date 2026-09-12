#!/usr/bin/env bash
# Symlink everything under home/ into $HOME, preserving directory structure.
#
# Symlinks rather than copies so that editing ~/.tmux.conf edits the repo, and
# `git status` shows drift. Anything already there that is not our symlink is
# renamed aside rather than clobbered.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$repo/home"
stamp="$(date +%Y%m%d%H%M%S)"

# Hard dependencies. fzf in particular fails late and confusingly otherwise:
# prefix+s opens a popup that dies instantly with "fzf: command not found".
missing=()
for cmd in tmux git fzf awk flock; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [ "${#missing[@]}" -gt 0 ]; then
    printf 'missing required commands: %s\n\n' "${missing[*]}" >&2
    printf 'install them first, e.g.\n' >&2
    printf '  sudo apt install %s\n' "${missing[*]}" >&2
    exit 1
fi

# Soft dependency: without one of these, copy-mode silently discards the copy.
if ! command -v pbcopy >/dev/null 2>&1 \
   && ! command -v wl-copy >/dev/null 2>&1 \
   && ! command -v xclip >/dev/null 2>&1 \
   && ! command -v xsel >/dev/null 2>&1 \
   && ! command -v clip.exe >/dev/null 2>&1; then
    printf 'warning: no clipboard tool found (xclip, wl-copy, xsel, pbcopy).\n' >&2
    printf '         copy-mode will still work, but copies go nowhere.\n\n' >&2
fi

link() {
    local rel="$1" from="$src/$1" to="$HOME/$1"
    mkdir -p "$(dirname "$to")"
    if [ -L "$to" ]; then
        if [ "$(readlink -f "$to")" = "$from" ]; then
            printf '  ok     %s\n' "$rel"; return
        fi
        rm -f "$to"
    elif [ -e "$to" ]; then
        mv "$to" "$to.backup.$stamp"
        printf '  backup %s -> %s.backup.%s\n' "$rel" "$rel" "$stamp"
    fi
    ln -s "$from" "$to"
    printf '  link   %s\n' "$rel"
}

printf 'linking into %s\n' "$HOME"
# No find -printf: macOS find does not have it.
while IFS= read -r rel; do
    link "$rel"
done < <(cd "$src" && find . -type f | sed 's|^\./||' | sort)

# TPM bootstraps nothing by itself -- without this clone the `run` line at the
# end of .tmux.conf silently does nothing and no plugin ever loads.
tpm="$HOME/.tmux/plugins/tpm"
if [ ! -d "$tpm" ]; then
    printf '\ncloning tpm\n'
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm"
fi

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl --user daemon-reload 2>/dev/null || true
    printf '\nsystemd user units reloaded\n'
    printf 'enable the tmux boot service with:  systemctl --user enable --now tmux.service\n'
fi

# Shell integration: ~/.local/bin on PATH, plus the `tm` shortcut for use
# outside tmux. A marked block so re-running is idempotent and removal is
# obvious.
marker='# >>> dotfiles: tmux >>>'
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    if grep -qF "$marker" "$rc"; then
        printf '  ok     %s (shell block)\n' "${rc#"$HOME"/}"
        continue
    fi
    cat >> "$rc" <<EOF

$marker
case ":\$PATH:" in *":\$HOME/.local/bin:"*) ;; *) export PATH="\$HOME/.local/bin:\$PATH" ;; esac
alias tm="tmux-sessions"
# <<< dotfiles: tmux <<<
EOF
    printf '  append %s (shell block)\n' "${rc#"$HOME"/}"
done

cat <<'EOF'

done. next:
  tmux source-file ~/.tmux.conf     (or start tmux)
  prefix + I                        install plugins, first run only
EOF
