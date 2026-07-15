#!/bin/bash
# Kill the pane, then rebalance whichever local group it belonged to (a row
# of side-by-side panes, or a column of stacked panes -- matched by exact
# geometry, not tree structure). Panes outside that group are never touched,
# no matter how deeply nested the layout is. Deliberately avoids
# select-layout -E, whose "spread evenly" can propagate further up the tree
# than intended in deep/complex layouts. Also runs as a separate process to
# avoid embedding tmux's own "-t"/"\;" syntax inside an if-shell/display-menu
# callback string, which nested tmux command parsing does not reliably
# handle.
pane_id="$1"
window_id="$2"

pane_top=$(tmux display-message -p -t "$pane_id" "#{pane_top}")
pane_left=$(tmux display-message -p -t "$pane_id" "#{pane_left}")
pane_height=$(tmux display-message -p -t "$pane_id" "#{pane_height}")
pane_width=$(tmux display-message -p -t "$pane_id" "#{pane_width}")

tmux kill-pane -t "$pane_id"

rebalance() {
    local match_a="$1" match_b="$2" fields="$3" resize_flag="$4"
    mapfile -t group < <(tmux list-panes -t "$window_id" -F "$fields" \
        | awk -v a="$match_a" -v b="$match_b" '$2 == a && $3 == b {print $1, $4}')
    local count=${#group[@]}
    if [ "$count" -gt 1 ]; then
        local total=0
        local ids=()
        for row in "${group[@]}"; do
            ids+=("${row%% *}")
            total=$((total + ${row##* }))
        done
        local even=$((total / count))
        for ((i = 0; i < count - 1; i++)); do
            tmux resize-pane -t "${ids[$i]}" "$resize_flag" "$even"
        done
    fi
}

# row-mates: same top/height as the dead pane -> equalize widths
rebalance "$pane_top" "$pane_height" "#{pane_id} #{pane_top} #{pane_height} #{pane_width}" "-x"
# column-mates: same left/width as the dead pane -> equalize heights
rebalance "$pane_left" "$pane_width" "#{pane_id} #{pane_left} #{pane_width} #{pane_height}" "-y"

tmux refresh-client
