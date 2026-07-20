#!/usr/bin/env bash
set -uo pipefail

# cron runs with a minimal PATH that doesn't include a sideloaded tmux.
export PATH="$HOME/.local/bin:$PATH"

ROOT_DIR="${TMUX_FRAME_SAVE_DIR:-$HOME/.tmux-frame-save}"
# Skip sessions ending in a dash + long numeric suffix (e.g. "MAIN-1784555926") —
# these are throwaway timestamp-suffixed viewing/duplicate sessions, not real ones.
EXCLUDE_REGEX="${TMUX_FRAME_SAVE_EXCLUDE_REGEX:-}"
if [ -z "$EXCLUDE_REGEX" ]; then
    EXCLUDE_REGEX='.*-[0-9]{5,}$'
fi
TAB=$'\t'

# No tmux server reachable -> leave existing snapshots alone (don't wipe them
# just because tmux isn't running right now) and do nothing else.
tmux list-sessions >/dev/null 2>&1 || exit 0

mkdir -p "$ROOT_DIR"

sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_'; }

declare -A live_sessions=()
declare -A live_windows=()

while IFS="$TAB" read -r session win_idx win_name; do
    [ -z "$session" ] && continue
    [[ "$session" =~ $EXCLUDE_REGEX ]] && continue
    sess_key="$(sanitize "$session")"
    sess_dir="$ROOT_DIR/$sess_key"
    mkdir -p "$sess_dir"
    live_sessions["$sess_key"]=1

    win_file="win${win_idx}-$(sanitize "$win_name").txt"
    live_windows["$sess_key/$win_file"]=1

    tmpfile="$sess_dir/.$win_file.tmp"
    : > "$tmpfile"
    while IFS="$TAB" read -r pane_id pane_idx; do
        {
            printf '===== pane %s (%s) =====\n' "$pane_idx" "$pane_id"
            tmux capture-pane -p -t "$pane_id" 2>/dev/null
            printf '\n'
        } >> "$tmpfile"
    done < <(tmux list-panes -t "${session}:${win_idx}" -F "#{pane_id}${TAB}#{pane_index}" 2>/dev/null)
    mv -f "$tmpfile" "$sess_dir/$win_file"
done < <(tmux list-windows -a -F "#{session_name}${TAB}#{window_index}${TAB}#{window_name}" 2>/dev/null)

# Drop session directories for sessions that no longer exist.
for dir in "$ROOT_DIR"/*/; do
    [ -d "$dir" ] || continue
    dname="$(basename "$dir")"
    [ -n "${live_sessions[$dname]+x}" ] || rm -rf -- "$dir"
done

# Drop window files, within still-live sessions, for windows that no longer exist.
for sess_key in "${!live_sessions[@]}"; do
    sess_dir="$ROOT_DIR/$sess_key"
    for f in "$sess_dir"/*.txt; do
        [ -e "$f" ] || continue
        key="$sess_key/$(basename "$f")"
        [ -n "${live_windows[$key]+x}" ] || rm -f -- "$f"
    done
done
