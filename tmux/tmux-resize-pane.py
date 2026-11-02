#!/usr/bin/env python3
# Resize a pane to a percentage of its row's width and (if it shares a
# column with panes above/below) a percentage of that column's height,
# rebalancing the rest of each axis's siblings in the space left over.
#
# Replaces the old geometry-overlap heuristic (grouping panes by
# cross-axis overlap, deduped by shared edge), which broke down on any
# layout where a slot in the target's row/column was itself further split
# -- e.g. two side-by-side panes stacked inside one column of a 3-column
# row: the heuristic's dedup-by-left-edge saw the inner split as a *second*
# distinct column instead of recognizing it as one slot, miscounting the
# group and sending most of the resize into whichever neighbor happened to
# be adjacent -- the "grows by crushing one side" bug. This instead walks
# tmux's real pane tree (see tmux_layout.py) to find the pane's true row
# and column siblings, however deeply nested, and rewrites the whole
# subtree's geometry in one `select-layout` call instead of a sequence of
# individual `resize-pane` calls whose border-negotiation can ripple
# further than intended.
import sys

from tmux_layout import parse_layout, resize_within_ancestor, serialize_layout, tmux


def main():
    percent = int(sys.argv[1])
    pane_id = sys.argv[2]
    height_percent = int(sys.argv[3]) if len(sys.argv) > 3 else 71

    raw = tmux("display-message", "-p", "-t", pane_id, "#{window_layout}")
    window_id = tmux("display-message", "-p", "-t", pane_id, "#{window_id}")
    tree, fmt = parse_layout(raw)

    resize_within_ancestor(tree, pane_id, percent, "h")  # row: width
    resize_within_ancestor(tree, pane_id, height_percent, "v")  # column: height

    tmux("select-layout", "-t", window_id, serialize_layout(tree, fmt))
    tmux("refresh-client")


if __name__ == "__main__":
    main()
