#!/bin/bash
# Computes the fzf `pos(N)` action for J/K session-hop in tmux-choose-tree.sh.
# $1 = next|prev, $2 = current 1-based fzf position, $3 = the window list file
# (one line per window, tab-delimited, field 1 = session name).
dir="$1"
pos="$2"
file="$3"

awk -F'\t' -v dir="$dir" -v pos="$pos" '
{ sess[NR] = $1 }
END {
    cur = sess[pos]
    if (dir == "next") {
        for (i = pos + 1; i <= NR; i++) {
            if (sess[i] != cur) { print "pos(" i ")"; exit }
        }
        print "pos(" NR ")"
    } else {
        start = pos
        while (start > 1 && sess[start - 1] == cur) start--
        if (start <= 1) { print "pos(1)"; exit }
        prevsess = sess[start - 1]
        i = start - 1
        while (i > 1 && sess[i - 1] == prevsess) i--
        print "pos(" i ")"
    }
}' "$file"
