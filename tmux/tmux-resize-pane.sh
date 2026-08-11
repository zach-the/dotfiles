#!/bin/bash
# Resize the given pane to a percentage of its row's total width, then
# rebalance every other pane sharing that row to evenly split the width
# left over. Panes outside that row are never touched, no matter how
# deeply nested the layout is.
#
# "Row" is defined by vertical overlap, not exact geometry match: a column
# that's itself split top/bottom (so its sub-panes are shorter than their
# full-height neighbors) still counts as one slot in the row, found by
# matching left-edge position and deduping. Matching only exact top+height
# (as an earlier version of this script did) silently drops such columns
# from the total, throwing off every percentage.
#
# Resizes are applied strictly in left-to-right order, and the pane left
# unset to auto-absorb the remainder is chosen to never be the target pane.
# resize-pane -x negotiates space with whichever neighbor is adjacent, so
# resizing the target first and then walking the other panes in list order
# (as an earlier version did) could touch the target's own border again as
# a side effect, silently undoing it -- hence needing a second press to
# converge. Processing left-to-right and only ever moving each pane's
# right-hand border (against a not-yet-finalized neighbor) avoids that.
percent="$1"   # target width as a percentage of the row's total width
pane_id="$2"

match_top=$(tmux display-message -p -t "$pane_id" "#{pane_top}")
match_height=$(tmux display-message -p -t "$pane_id" "#{pane_height}")
match_bottom=$((match_top + match_height))

slots=()   # not mapfile: macOS's /bin/bash (3.2, what the shebang always resolves to) predates it
while IFS= read -r line; do
    slots+=("$line")
done < <(tmux list-panes -t "$pane_id" -F "#{pane_id} #{pane_top} #{pane_height} #{pane_left} #{pane_width}" \
    | awk -v ttop="$match_top" -v tbot="$match_bottom" '
        { id=$1; top=$2; height=$3; left=$4; width=$5; bottom = top + height
          if (top < tbot && bottom > ttop && !(left in seen)) {
              seen[left] = 1
              print left, width, id
          }
        }' | sort -n -k1,1)

count=${#slots[@]}
if [ "$count" -lt 2 ]; then
    tmux refresh-client
    exit 0
fi

total=0
target_index=-1
for i in "${!slots[@]}"; do
    slot="${slots[$i]}"
    width="${slot#* }"; width="${width%% *}"
    total=$((total + width))
    id="${slot##* }"
    [ "$id" = "$pane_id" ] && target_index=$i
done

target_width=$(( total * percent / 100 ))
other_count=$((count - 1))
remaining=$((total - target_width))
even=$((remaining / other_count))

auto_index=$((count - 1))
[ "$auto_index" -eq "$target_index" ] && auto_index=$((count - 2))

for i in "${!slots[@]}"; do
    [ "$i" -eq "$auto_index" ] && continue
    id="${slots[$i]##* }"
    if [ "$i" -eq "$target_index" ]; then
        tmux resize-pane -t "$id" -x "$target_width"
    else
        tmux resize-pane -t "$id" -x "$even"
    fi
done

tmux refresh-client
