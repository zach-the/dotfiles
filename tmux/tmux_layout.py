# Shared pane-tree engine for tmux layout manipulation.
#
# tmux's #{window_layout} comes in two formats depending on version:
#   - tmux >= 3.8: a JSON tree, e.g. {"V":2,"L":{"t":"h","w":...,"c":[...]}}
#   - older tmux (verified against a real tmux 3.7c binary; the format is
#     unchanged for many years before that, so this also covers 3.6a): the
#     classic checksummed string, e.g.
#     "21be,200x50,0,0{100x50,0,0,0,99x50,101,0[...]}"
#
# Both encode the same thing: a recursive tree of "h" (LEFTRIGHT, panes
# side by side) and "v" (TOPBOTTOM, panes stacked) containers, bottoming
# out in "p" (pane) leaves, each carrying w/h/x/y. parse_layout() and
# serialize_layout() convert either format to/from one in-memory schema,
# {"t": "p"|"h"|"v", "w", "h", "x", "y", "c": [...]} (leaves carry "I",
# the pane id, instead of "c"), so callers don't need to care which
# format the running tmux speaks.
import json
import re
import subprocess


def tmux(*args):
    # stdout/stderr/universal_newlines rather than capture_output/text:
    # those are Python 3.7+, and some hosts still ship 3.6 as python3.
    return subprocess.run(
        ["tmux", *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        check=True,
    ).stdout.strip()


def parse_layout(raw):
    """raw #{window_layout} text -> (tree, fmt), fmt in {"json", "classic"}."""
    raw = raw.strip()
    if raw.startswith("{"):
        return json.loads(raw)["L"], "json"
    _, body = raw.split(",", 1)
    tree, pos = _parse_classic(body, 0)
    assert pos == len(body), f"trailing data in layout string: {body[pos:]!r}"
    return tree, "classic"


def _parse_classic(s, pos):
    m = re.match(r"(\d+)x(\d+),(\d+),(\d+)", s[pos:])
    w, h, x, y = (int(v) for v in m.groups())
    pos += m.end()
    node = {"w": w, "h": h, "x": x, "y": y}
    if pos < len(s) and s[pos] in "{[":
        opener = s[pos]
        closer = "}" if opener == "{" else "]"
        node["t"] = "h" if opener == "{" else "v"
        pos += 1
        children = []
        child, pos = _parse_classic(s, pos)
        children.append(child)
        while s[pos] == ",":
            child, pos = _parse_classic(s, pos + 1)
            children.append(child)
        assert s[pos] == closer
        node["c"] = children
        pos += 1
    else:
        node["t"] = "p"
        assert s[pos] == ","
        pos += 1
        m2 = re.match(r"(\d+)", s[pos:])
        node["I"] = "%" + m2.group(1)
        pos += m2.end()
    return node, pos


def serialize_layout(tree, fmt):
    """(tree, fmt) -> raw text suitable for `tmux select-layout`."""
    if fmt == "json":
        return json.dumps({"V": 2, "L": tree})
    body = _serialize_classic(tree)
    return f"{_classic_checksum(body):04x},{body}"


def _serialize_classic(node):
    s = f"{node['w']}x{node['h']},{node['x']},{node['y']}"
    if node["t"] == "p":
        return s + "," + node["I"].lstrip("%")
    opener, closer = ("{", "}") if node["t"] == "h" else ("[", "]")
    return s + opener + ",".join(_serialize_classic(c) for c in node["c"]) + closer


def _classic_checksum(body):
    csum = 0
    for ch in body:
        csum = (csum >> 1) + ((csum & 1) << 15)
        csum += ord(ch)
    return csum & 0xFFFF


def equalize(node, x, y, w, h):
    """Recursively give every split in the subtree equal shares, at every level."""
    node["x"], node["y"], node["w"], node["h"] = x, y, w, h
    if node["t"] == "p":
        return
    children = node["c"]
    n = len(children)
    gaps = n - 1  # one 1-cell border between each pair of siblings
    if node["t"] == "h":  # children side by side -- split width
        avail = w - gaps
        base, rem = divmod(avail, n)
        cur = x
        for i, child in enumerate(children):
            cw = base + (1 if i < rem else 0)
            equalize(child, cur, y, cw, h)
            cur += cw + 1
    else:  # "v": children stacked -- split height
        avail = h - gaps
        base, rem = divmod(avail, n)
        cur = y
        for i, child in enumerate(children):
            ch = base + (1 if i < rem else 0)
            equalize(child, x, cur, w, ch)
            cur += ch + 1


def find_path(node, pane_id, path=None):
    """List of nodes from root to the leaf whose pane id is pane_id, or None."""
    path = (path or []) + [node]
    if node["t"] == "p":
        return path if node["I"] == pane_id else None
    for child in node["c"]:
        found = find_path(child, pane_id, path)
        if found:
            return found
    return None


def set_width(node, new_x, new_w):
    """Propagate a new x/w down through node's subtree.

    If node is a "v" split, its children stack and each already spans the
    full width, so every child just inherits the same new_x/new_w
    unchanged (y/h untouched). If node is an "h" split, its children
    divide new_w between them, each keeping its old proportional share
    (not reset to equal -- that's equalize()'s job). A leaf just takes
    new_x/new_w directly.
    """
    old_w = node["w"]
    node["x"], node["w"] = new_x, new_w
    if node["t"] == "p":
        return
    if node["t"] == "v":
        for child in node["c"]:
            set_width(child, new_x, new_w)
        return
    n = len(node["c"])
    gaps = n - 1
    old_avail = old_w - gaps
    new_avail = new_w - gaps
    sizes, assigned = [], 0
    for i, child in enumerate(node["c"]):
        if i == n - 1:
            cw = new_avail - assigned
        else:
            cw = round(child["w"] * new_avail / old_avail)
            assigned += cw
        sizes.append(cw)
    cur = new_x
    for child, cw in zip(node["c"], sizes):
        set_width(child, cur, cw)
        cur += cw + 1


def set_height(node, new_y, new_h):
    """Mirror of set_width() for the y/h axis."""
    old_h = node["h"]
    node["y"], node["h"] = new_y, new_h
    if node["t"] == "p":
        return
    if node["t"] == "h":
        for child in node["c"]:
            set_height(child, new_y, new_h)
        return
    n = len(node["c"])
    gaps = n - 1
    old_avail = old_h - gaps
    new_avail = new_h - gaps
    sizes, assigned = [], 0
    for i, child in enumerate(node["c"]):
        if i == n - 1:
            ch = new_avail - assigned
        else:
            ch = round(child["h"] * new_avail / old_avail)
            assigned += ch
        sizes.append(ch)
    cur = new_y
    for child, ch in zip(node["c"], sizes):
        set_height(child, cur, ch)
        cur += ch + 1


def resize_within_ancestor(tree, pane_id, percent, axis_type):
    """Resize pane_id to `percent` of the *whole window's* span on this
    axis -- axis_type "h" sizes the pane to that fraction of the full
    width, "v" of the full height -- redistributing what's left evenly
    among every true sibling the pane has on that axis, at any nesting
    depth. "Every sibling at any depth" is the key piece: a pane nested
    two levels deep (its own small side-by-side split, itself inside one
    slot of a 3-column window) has row-mates at *both* levels -- the pane
    right next to it, and the far columns clear across the window -- and
    all of them compete for the same horizontal space the pane is asking
    to grow into. Resizing against only the nearest level leaves the pane
    a fraction of a fraction of the window (way too small); resizing the
    pane's whole containing branch as one unit against only the outer
    level grows the branch but leaves the pane's share *within* that
    branch unchanged (still not what the pane itself ends up with). This
    walks the pane's full ancestor chain, flattens every sibling found
    along the way -- near and far -- into one row, and solves for sizes
    so the pane itself lands at exactly `percent` of the window, with
    every ancestor branch's width then following as a consequence (summed
    from its children where it splits on this axis, inherited unchanged
    where it splits on the other axis) rather than being chosen directly.
    Panes outside the pane's ancestry entirely are never touched. Returns
    False (no-op) if the pane has no siblings on this axis anywhere in its
    ancestry (it's already alone in its row/column).
    """
    path = find_path(tree, pane_id)
    if path is None:
        return False

    mates = []
    for i in range(len(path) - 1):
        if path[i]["t"] == axis_type:
            continuing = path[i + 1]
            mates.extend(c for c in path[i]["c"] if c is not continuing)
    if not mates:
        return False

    size_key, pos_key = ("w", "x") if axis_type == "h" else ("h", "y")
    setter = set_width if axis_type == "h" else set_height

    other_count = len(mates)
    gaps = other_count  # one gap between the target and each mate, in the
    # single flattened row -- regardless of how those mates are nested
    avail = tree[size_key] - gaps
    target_size = avail * percent // 100
    remaining = avail - target_size
    even = remaining // other_count
    leftover = remaining - even * other_count

    mate_size = {id(m): even + (1 if i < leftover else 0) for i, m in enumerate(mates)}

    # Bottom-up: derive each ancestor-on-the-path's own span from its
    # children now that the leaf and every mate have a final size --
    # summed (+1 gap each) where it splits on this axis, inherited
    # unchanged from the continuing child where it splits the other way.
    node_size = {id(path[-1]): target_size}
    for i in range(len(path) - 2, -1, -1):
        node, child = path[i], path[i + 1]
        if node["t"] == axis_type:
            node_size[id(node)] = node_size[id(child)] + sum(
                mate_size[id(c)] + 1 for c in node["c"] if c is not child
            )
        else:
            node_size[id(node)] = node_size[id(child)]

    # Top-down: lay out each path node's children in their original visual
    # order, recursing into the continuing child and plainly (proportionally)
    # resizing every mate via setter().
    def apply(idx, pos, size):
        node = path[idx]
        node[pos_key], node[size_key] = pos, size
        if idx == len(path) - 1:
            return
        continuing = path[idx + 1]
        if node["t"] == axis_type:
            cur = pos
            for child in node["c"]:
                if child is continuing:
                    apply(idx + 1, cur, node_size[id(continuing)])
                    cur += node_size[id(continuing)] + 1
                else:
                    setter(child, cur, mate_size[id(child)])
                    cur += mate_size[id(child)] + 1
        else:
            for child in node["c"]:
                if child is continuing:
                    apply(idx + 1, pos, size)
                else:
                    setter(child, pos, size)

    apply(0, tree[pos_key], node_size[id(path[0])])
    return True
