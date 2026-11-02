#!/usr/bin/env python3
# Recursively equalize every split in a tmux window's pane tree.
#
# tmux's own `select-layout -E` only rebalances the active pane's immediate
# siblings, not the whole tree (per `man tmux`), and in practice is a no-op
# on layouts with manually-set custom ratios -- it only corrects rounding
# drift, despite the name. This instead reads the real pane tree from
# `#{window_layout}` and gives every split equal shares at every nesting
# level (horizontal splits first, then the vertical splits nested inside
# each of those, and so on down the tree), then feeds the rebuilt tree
# back to `select-layout`. See tmux_layout.py for the format details (it
# transparently handles both the tmux >= 3.8 JSON layout format and the
# classic checksummed string format older tmux versions use).
import sys

from tmux_layout import equalize, parse_layout, serialize_layout, tmux


def main():
    target = sys.argv[1] if len(sys.argv) > 1 else ""
    target_args = ["-t", target] if target else []

    raw = tmux("display-message", "-p", *target_args, "#{window_layout}")
    tree, fmt = parse_layout(raw)

    equalize(tree, tree["x"], tree["y"], tree["w"], tree["h"])

    tmux("select-layout", *target_args, serialize_layout(tree, fmt))


if __name__ == "__main__":
    main()
