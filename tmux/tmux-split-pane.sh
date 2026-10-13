#!/bin/bash
# Split the source pane, then do the equivalent of Alt+= (select-layout -E)
# so that creating a pane, closing a pane (tmux-kill-pane.sh) and pressing
# Alt+= all equalize the same way.
#
# The previous geometry-based rebalance is kept commented out below in case
# it's ever wanted again; to go back, uncomment it and remove the
# select-layout line.
direction="$1"   # -v (new pane below) or -h (new pane to the right)
pane_id="$2"

pane_path=$(tmux display-message -p -t "$pane_id" "#{pane_current_path}")

tmux split-window "$direction" -t "$pane_id" -c "$pane_path"

# Same as the Alt+= binding in tmux.conf. Targets the source pane, which is a
# direct sibling of the new (now focused) pane, so the result is the same as
# pressing Alt+= right after the split.
tmux select-layout -t "$pane_id" -E

# --- OLD: geometry-based rebalance ---
# What it did: after the split, rebalance every pane sharing the source
# pane's row/column to split evenly along the split axis only. Panes outside
# that row/column were never touched, no matter how deeply nested the layout
# is -- this avoided relying on select-layout -E, whose "spread evenly" can
# propagate further up the tree than intended in deep/complex layouts (e.g.
# when the new pane's own group is already even, -E moves up and evens the
# parent group instead, undoing a manual 67/33 split).
#
# Siblings were found by overlap on the cross axis, not exact geometry match:
# a column that's itself split top/bottom (or a row that's itself split
# left/right) has sub-panes shorter/narrower than their full-size neighbors,
# so exact-match grouping would silently exclude it -- e.g. splitting a pane
# in the right-hand slot of a layout whose left column is itself split
# top/bottom would only equalize within that one slot, never touching the
# left column, leaving the overall row un-thirded. Matching by overlap
# (dedup'd by the shared edge -- top for columns, left for rows) treats a
# split slot as one group member, same as tmux-resize-pane.sh does for rows.
#
# Step 1: read the source pane's geometry (post-split) to match against.
# match_top=$(tmux display-message -p -t "$pane_id" "#{pane_top}")
# match_height=$(tmux display-message -p -t "$pane_id" "#{pane_height}")
# match_left=$(tmux display-message -p -t "$pane_id" "#{pane_left}")
# match_width=$(tmux display-message -p -t "$pane_id" "#{pane_width}")
#
# Step 2: pick the grouping rule and resize axis for this split direction.
# if [ "$direction" = "-v" ]; then
#     # New pane is below; siblings are the rest of the same column -- group by
#     # horizontal overlap, dedup by top, resize heights.
#     match_right=$((match_left + match_width))
#     awk_prog='
#         { id=$1; top=$2; height=$3; left=$4; width=$5; right = left + width
#           if (left < mright && right > mleft && !(top in seen)) {
#               seen[top] = 1
#               print top, height, id
#           }
#         }'
#     resize_flag="-y"
# else
#     # New pane is to the right; siblings are the rest of the same row --
#     # group by vertical overlap, dedup by left, resize widths.
#     match_bottom=$((match_top + match_height))
#     awk_prog='
#         { id=$1; top=$2; height=$3; left=$4; width=$5; bottom = top + height
#           if (top < mbot && bottom > mtop && !(left in seen)) {
#               seen[left] = 1
#               print left, width, id
#           }
#         }'
#     resize_flag="-x"
# fi
#
# Step 3: collect the group's slots as "edge size pane_id", ordered by edge.
# slots=()   # not mapfile: macOS's /bin/bash (3.2, what the shebang always resolves to) predates it
# while IFS= read -r line; do
#     slots+=("$line")
# done < <(tmux list-panes -t "$pane_id" -F "#{pane_id} #{pane_top} #{pane_height} #{pane_left} #{pane_width}" \
#     | awk -v mtop="$match_top" -v mbot="${match_bottom:-0}" -v mleft="$match_left" -v mright="${match_right:-0}" \
#         "$awk_prog" | sort -n -k1,1)
#
# Step 4: nothing to balance if the pane has no group-mates.
# count=${#slots[@]}
# if [ "$count" -lt 2 ]; then
#     tmux refresh-client
#     exit 0
# fi
#
# Step 5: set every slot but the last to total/count; the last absorbs the
# remainder.
# total=0
# for slot in "${slots[@]}"; do
#     size="${slot#* }"; size="${size%% *}"
#     total=$((total + size))
# done
# even=$((total / count))
#
# for ((i = 0; i < count - 1; i++)); do
#     id="${slots[$i]##* }"
#     tmux resize-pane -t "$id" "$resize_flag" "$even"
# done

tmux refresh-client
