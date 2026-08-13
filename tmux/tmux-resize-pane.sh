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
#
# After the width pass, if the target pane isn't already full-height (i.e.
# it shares its column with at least one other pane stacked above/below
# it), it's also resized to 5/7 of that column's total height, with the
# same top-to-bottom rebalancing applied to its vertical neighbors. A pane
# alone in its column is already full height, so this is a no-op for it --
# mirroring how a pane alone in its row is left untouched by the width
# pass above.
percent="$1"   # target width as a percentage of the row's total width
pane_id="$2"

# axis: "x" resizes width across a row (panes grouped by vertical overlap,
# deduped by left edge); "y" resizes height down a column (panes grouped
# by horizontal overlap, deduped by top edge).
resize_axis() {
    local size_percent="$1" target_id="$2" axis="$3"
    local pos_field size_field cross_pos_field cross_size_field
    if [ "$axis" = "x" ]; then
        pos_field=pane_top; size_field=pane_height
        cross_pos_field=pane_left; cross_size_field=pane_width
    else
        pos_field=pane_left; size_field=pane_width
        cross_pos_field=pane_top; cross_size_field=pane_height
    fi

    local match_pos match_size match_end
    match_pos=$(tmux display-message -p -t "$target_id" "#{$pos_field}")
    match_size=$(tmux display-message -p -t "$target_id" "#{$size_field}")
    match_end=$((match_pos + match_size))

    local slots=()   # not mapfile: macOS's /bin/bash (3.2) predates it
    while IFS= read -r line; do
        slots+=("$line")
    done < <(tmux list-panes -t "$target_id" -F "#{pane_id} #{$pos_field} #{$size_field} #{$cross_pos_field} #{$cross_size_field}" \
        | awk -v tstart="$match_pos" -v tend="$match_end" '
            { id=$1; pos=$2; size=$3; cpos=$4; csize=$5; end = pos + size
              if (pos < tend && end > tstart && !(cpos in seen)) {
                  seen[cpos] = 1
                  print cpos, csize, id
              }
            }' | sort -n -k1,1)

    local count=${#slots[@]}
    if [ "$count" -lt 2 ]; then
        return 0
    fi

    local total=0 target_index=-1
    for i in "${!slots[@]}"; do
        local slot="${slots[$i]}"
        local sz="${slot#* }"; sz="${sz%% *}"
        total=$((total + sz))
        local id="${slot##* }"
        [ "$id" = "$target_id" ] && target_index=$i
    done

    local target_size=$(( total * size_percent / 100 ))
    local other_count=$((count - 1))
    local remaining=$((total - target_size))
    local even=$((remaining / other_count))

    local auto_index=$((count - 1))
    [ "$auto_index" -eq "$target_index" ] && auto_index=$((count - 2))

    for i in "${!slots[@]}"; do
        [ "$i" -eq "$auto_index" ] && continue
        local id="${slots[$i]##* }"
        if [ "$i" -eq "$target_index" ]; then
            tmux resize-pane -t "$id" "-$axis" "$target_size"
        else
            tmux resize-pane -t "$id" "-$axis" "$even"
        fi
    done
}

resize_axis "$percent" "$pane_id" x
resize_axis 71 "$pane_id" y   # ~5/7

tmux refresh-client
