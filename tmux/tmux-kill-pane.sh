#!/bin/bash
# Kill the pane, then rebalance whichever local group it belonged to (a row
# of side-by-side panes, or a column of stacked panes) to fill the freed
# space evenly. Panes outside that group are never touched, no matter how
# deeply nested the layout is. Deliberately avoids select-layout -E, whose
# "spread evenly" can propagate further up the tree than intended in
# deep/complex layouts. Also runs as a separate process to avoid embedding
# tmux's own "-t"/"\;" syntax inside an if-shell/display-menu callback
# string, which nested tmux command parsing does not reliably handle.
#
# Group membership is found by cross-axis overlap + edge dedup, not exact
# geometry match (mirrors tmux-resize-pane.sh / tmux-split-pane.sh): a
# column that's itself split top/bottom has sub-panes shorter than a
# full-height neighbor, so exact top+height matching would silently exclude
# it from its row group -- e.g. killing a full-height pane next to such a
# column would leave the column's width untouched while its neighbor
# absorbed all the freed space, producing uneven columns.
pane_id="$1"
window_id="$2"

pane_top=$(tmux display-message -p -t "$pane_id" "#{pane_top}")
pane_left=$(tmux display-message -p -t "$pane_id" "#{pane_left}")
pane_height=$(tmux display-message -p -t "$pane_id" "#{pane_height}")
pane_width=$(tmux display-message -p -t "$pane_id" "#{pane_width}")
pane_bottom=$((pane_top + pane_height))
pane_right=$((pane_left + pane_width))

tmux kill-pane -t "$pane_id"

rebalance() {
    local awk_prog="$1" resize_flag="$2"
    shift 2
    local slots=()   # not mapfile: macOS's /bin/bash (3.2, what the shebang always resolves to) predates it
    while IFS= read -r line; do
        slots+=("$line")
    done < <(tmux list-panes -t "$window_id" -F "#{pane_id} #{pane_top} #{pane_height} #{pane_left} #{pane_width}" \
        | awk "$@" "$awk_prog" | sort -n -k1,1)

    local count=${#slots[@]}
    if [ "$count" -gt 1 ]; then
        local total=0
        local ids=()
        for slot in "${slots[@]}"; do
            ids+=("${slot##* }")
            local size="${slot#* }"; size="${size%% *}"
            total=$((total + size))
        done
        local even=$((total / count))
        for ((i = 0; i < count - 1; i++)); do
            tmux resize-pane -t "${ids[$i]}" "$resize_flag" "$even"
        done
    fi
}

# row-mates: vertical overlap with the dead pane -> equalize widths, dedup by left
rebalance '
    { id=$1; top=$2; height=$3; left=$4; width=$5; bottom = top + height
      if (top < pbot && bottom > ptop && !(left in seen)) {
          seen[left] = 1
          print left, width, id
      }
    }' "-x" -v ptop="$pane_top" -v pbot="$pane_bottom"

# column-mates: horizontal overlap with the dead pane -> equalize heights, dedup by top
rebalance '
    { id=$1; top=$2; height=$3; left=$4; width=$5; right = left + width
      if (left < pright && right > pleft && !(top in seen)) {
          seen[top] = 1
          print top, height, id
      }
    }' "-y" -v pleft="$pane_left" -v pright="$pane_right"

tmux refresh-client
