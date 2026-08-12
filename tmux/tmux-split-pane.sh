#!/bin/bash
# Split the source pane, then rebalance every pane sharing its row/column to
# split evenly along the split axis. Panes outside that row/column are never
# touched, no matter how deeply nested the layout is -- this avoids relying
# on select-layout -E, whose "spread evenly" can propagate further up the
# tree than intended in deep/complex layouts.
#
# Siblings are found by overlap on the cross axis, not exact geometry match:
# a column that's itself split top/bottom (or a row that's itself split
# left/right) has sub-panes shorter/narrower than their full-size neighbors,
# so exact-match grouping would silently exclude it -- e.g. splitting a pane
# in the right-hand slot of a layout whose left column is itself split
# top/bottom would only equalize within that one slot, never touching the
# left column, leaving the overall row un-thirded. Matching by overlap
# (dedup'd by the shared edge -- top for columns, left for rows) treats a
# split slot as one group member, same as tmux-resize-pane.sh does for rows.
direction="$1"   # -v (new pane below) or -h (new pane to the right)
pane_id="$2"

pane_path=$(tmux display-message -p -t "$pane_id" "#{pane_current_path}")

tmux split-window "$direction" -t "$pane_id" -c "$pane_path"

match_top=$(tmux display-message -p -t "$pane_id" "#{pane_top}")
match_height=$(tmux display-message -p -t "$pane_id" "#{pane_height}")
match_left=$(tmux display-message -p -t "$pane_id" "#{pane_left}")
match_width=$(tmux display-message -p -t "$pane_id" "#{pane_width}")

if [ "$direction" = "-v" ]; then
    # New pane is below; siblings are the rest of the same column -- group by
    # horizontal overlap, dedup by top, resize heights.
    match_right=$((match_left + match_width))
    awk_prog='
        { id=$1; top=$2; height=$3; left=$4; width=$5; right = left + width
          if (left < mright && right > mleft && !(top in seen)) {
              seen[top] = 1
              print top, height, id
          }
        }'
    resize_flag="-y"
else
    # New pane is to the right; siblings are the rest of the same row --
    # group by vertical overlap, dedup by left, resize widths.
    match_bottom=$((match_top + match_height))
    awk_prog='
        { id=$1; top=$2; height=$3; left=$4; width=$5; bottom = top + height
          if (top < mbot && bottom > mtop && !(left in seen)) {
              seen[left] = 1
              print left, width, id
          }
        }'
    resize_flag="-x"
fi

slots=()   # not mapfile: macOS's /bin/bash (3.2, what the shebang always resolves to) predates it
while IFS= read -r line; do
    slots+=("$line")
done < <(tmux list-panes -t "$pane_id" -F "#{pane_id} #{pane_top} #{pane_height} #{pane_left} #{pane_width}" \
    | awk -v mtop="$match_top" -v mbot="${match_bottom:-0}" -v mleft="$match_left" -v mright="${match_right:-0}" \
        "$awk_prog" | sort -n -k1,1)

count=${#slots[@]}
if [ "$count" -lt 2 ]; then
    tmux refresh-client
    exit 0
fi

total=0
for slot in "${slots[@]}"; do
    size="${slot#* }"; size="${size%% *}"
    total=$((total + size))
done
even=$((total / count))

for ((i = 0; i < count - 1; i++)); do
    id="${slots[$i]##* }"
    tmux resize-pane -t "$id" "$resize_flag" "$even"
done

tmux refresh-client
