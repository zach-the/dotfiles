#!/bin/bash
# Computes the fzf `pos(N)` action for J/K session-hop in tmux-choose-tree.sh.
# $1 = next|prev, $2 = current 1-based fzf position, $3 = the window list file
# (one line per window, tab-delimited: field 1 = session name, field 2 =
# switch target, empty on the session-divider row so we can skip past it).
dir="$1"
pos="$2"
file="$3"

awk -F'\t' -v dir="$dir" -v pos="$pos" '
{ sess[NR] = $1; target[NR] = $2 }
END {
    n = NR
    cur = sess[pos]
    if (dir == "next") {
        i = -1
        for (j = pos + 1; j <= n; j++) {
            if (sess[j] != cur) { i = j; break }
        }
        if (i == -1) i = n
    } else {
        start = pos
        while (start > 1 && sess[start - 1] == cur) start--
        if (start <= 1) {
            i = 1
        } else {
            prevsess = sess[start - 1]
            i = start - 1
            while (i > 1 && sess[i - 1] == prevsess) i--
        }
    }
    if (target[i] == "" && i < n) i++
    print "pos(" i ")"
}' "$file"
