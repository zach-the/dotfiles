#!/bin/bash
# Split the source pane, then rebalance every pane sharing its row/column
# (matched by exact geometry, not tree structure) to split evenly along the
# split axis. Panes outside that row/column are never touched, no matter how
# deeply nested the layout is -- this avoids relying on select-layout -E,
# whose "spread evenly" can propagate further up the tree than intended in
# deep/complex layouts.
direction="$1"   # -v (new pane below) or -h (new pane to the right)
pane_id="$2"

pane_path=$(tmux display-message -p -t "$pane_id" "#{pane_current_path}")

tmux split-window "$direction" -t "$pane_id" -c "$pane_path"

if [ "$direction" = "-v" ]; then
    # Siblings share the same left/width (a column); equalize heights.
    match_a=$(tmux display-message -p -t "$pane_id" "#{pane_left}")
    match_b=$(tmux display-message -p -t "$pane_id" "#{pane_width}")
    fields="#{pane_id} #{pane_left} #{pane_width} #{pane_height}"
    resize_flag="-y"
else
    # Siblings share the same top/height (a row); equalize widths.
    match_a=$(tmux display-message -p -t "$pane_id" "#{pane_top}")
    match_b=$(tmux display-message -p -t "$pane_id" "#{pane_height}")
    fields="#{pane_id} #{pane_top} #{pane_height} #{pane_width}"
    resize_flag="-x"
fi

mapfile -t group < <(tmux list-panes -t "$pane_id" -F "$fields" \
    | awk -v a="$match_a" -v b="$match_b" '$2 == a && $3 == b {print $1, $4}')

count=${#group[@]}
if [ "$count" -gt 1 ]; then
    total=0
    ids=()
    for row in "${group[@]}"; do
        ids+=("${row%% *}")
        total=$((total + ${row##* }))
    done
    even=$((total / count))
    for ((i = 0; i < count - 1; i++)); do
        tmux resize-pane -t "${ids[$i]}" "$resize_flag" "$even"
    done
fi

tmux refresh-client
