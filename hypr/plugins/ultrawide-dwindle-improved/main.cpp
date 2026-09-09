#define WLR_USE_UNSTABLE

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/TiledAlgorithm.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <memory>
#include <optional>
#include <unordered_map>
#include <utility>
#include <vector>

using namespace Layout;

static constexpr double ULTRAWIDE_RATIO = 2.1;
static constexpr float  MIN_COL_FRAC    = 0.1f;

static HANDLE g_handle = nullptr;

// Binary tree node for dwindle layout — used for normal monitors and per-column in ultrawide.
struct SDwindleNode {
    SP<ITarget>                   target;
    std::unique_ptr<SDwindleNode> first, second;
    float ratio  = 0.5f;
    bool  splitV = true;

    bool isLeaf() const { return !!target; }

    void collectTargets(std::vector<SP<ITarget>>& out) const {
        if (isLeaf()) { out.push_back(target); return; }
        first->collectTargets(out);
        second->collectTargets(out);
    }

    // Split the leaf holding `cur` into an internal node. If newFirst, newT goes on the
    // top/left and cur goes on the bottom/right; otherwise cur is top/left, newT bottom/right.
    // The split orientation is decided once, here, from cur's box at the moment of the
    // split — not recomputed later from the box shape (see layout()), so resizing a
    // column/split wide or tall never flips it between stacked and side-by-side on its own.
    bool insertNext(const SP<ITarget>& cur, const SP<ITarget>& newT, bool newFirst = false) {
        if (isLeaf()) {
            if (target != cur) return false;
            auto oldLeaf    = std::make_unique<SDwindleNode>();
            oldLeaf->target = cur;
            auto newLeaf    = std::make_unique<SDwindleNode>();
            newLeaf->target = newT;
            target          = nullptr;
            auto curBox     = cur->position();
            splitV          = curBox.w > curBox.h;
            if (newFirst) {
                first  = std::move(newLeaf);
                second = std::move(oldLeaf);
            } else {
                first  = std::move(oldLeaf);
                second = std::move(newLeaf);
            }
            return true;
        }
        return first->insertNext(cur, newT, newFirst) || second->insertNext(cur, newT, newFirst);
    }

    static bool remove(std::unique_ptr<SDwindleNode>& self, const SP<ITarget>& t) {
        if (!self || self->isLeaf()) return false;
        if (self->first->isLeaf() && self->first->target == t) {
            self = std::move(self->second);
            return true;
        }
        if (self->second->isLeaf() && self->second->target == t) {
            self = std::move(self->first);
            return true;
        }
        return remove(self->first, t) || remove(self->second, t);
    }

    // Builds the chain of ancestors from `t`'s immediate parent up to the
    // root, nearest first. Each entry records whether `t` descends through
    // that ancestor's `first` child (true) or `second` child (false).
    bool buildPath(const SP<ITarget>& t, std::vector<std::pair<SDwindleNode*, bool>>& path) {
        if (isLeaf())
            return target == t;
        if (first->buildPath(t, path)) {
            path.emplace_back(this, true);
            return true;
        }
        if (second->buildPath(t, path)) {
            path.emplace_back(this, false);
            return true;
        }
        return false;
    }

    void swapTargets(const SP<ITarget>& a, const SP<ITarget>& b) {
        if (isLeaf()) {
            if      (target == a) target = b;
            else if (target == b) target = a;
            return;
        }
        first->swapTargets(a, b);
        second->swapTargets(a, b);
    }

    void layout(const CBox& box) {
        if (isLeaf()) {
            target->setPositionGlobal(box);
            target->warpPositionSize();
            return;
        }
        // splitV is fixed at creation time (see insertNext/appendToEnd), not
        // recomputed from the box here — so a column/split's orientation
        // never flips on its own just because a resize made it wider or
        // taller than it started.
        CBox fBox, sBox;
        if (splitV) {
            double w = box.w * ratio;
            fBox = {box.x,     box.y, w,         box.h};
            sBox = {box.x + w, box.y, box.w - w, box.h};
        } else {
            double h = box.h * ratio;
            fBox = {box.x, box.y,     box.w, h        };
            sBox = {box.x, box.y + h, box.w, box.h - h};
        }
        first->layout(fBox);
        second->layout(sBox);
    }
};

static void appendToEnd(std::unique_ptr<SDwindleNode>& node, const SP<ITarget>& newT) {
    if (node->isLeaf()) {
        auto oldLeaf    = std::make_unique<SDwindleNode>();
        oldLeaf->target = node->target;
        auto newLeaf    = std::make_unique<SDwindleNode>();
        newLeaf->target = newT;
        auto curBox     = node->target->position();
        node->target    = nullptr;
        node->splitV    = curBox.w > curBox.h;
        node->first     = std::move(oldLeaf);
        node->second    = std::move(newLeaf);
        return;
    }
    appendToEnd(node->second, newT);
}

// Determine whether the new window should go before (top/left of) the nearest window.
// Compares cursor position to the nearest window's center along the axis that will be split.
// A window whose box.w > box.h will get a vertical split (left/right), so we compare X.
// Otherwise it gets a horizontal split (top/bottom), so we compare Y.
static bool computeNewFirst(const SP<ITarget>& nearest) {
    auto box      = nearest->position();
    auto mousePos = g_pInputManager->getMouseCoordsInternal();
    if (box.w > box.h)
        return mousePos.x < box.x + box.w * 0.5; // vertical split → compare X
    else
        return mousePos.y < box.y + box.h * 0.5; // horizontal split → compare Y
}

// Walks `path` (nearest-ancestor-first, from SDwindleNode::buildPath) for the
// first node whose split orientation matches `wantSplitV`, on the side
// implied by wantFirstSide/wantSecondSide, and nudges its ratio by `d` pixels
// against `outerDim` (the pixel size, along this axis, of the box being
// subdivided). Returns whether a matching ancestor was found and adjusted.
static bool resizeAlongPath(std::vector<std::pair<SDwindleNode*, bool>>& path, bool wantSplitV, double d, double outerDim, bool wantFirstSide,
                             bool wantSecondSide) {
    for (auto& [node, isFirst] : path) {
        if (node->splitV != wantSplitV) continue;
        if (!((isFirst && wantFirstSide) || (!isFirst && wantSecondSide))) continue;
        node->ratio = std::clamp((float)(node->ratio + d / outerDim * 2.0), 0.1f, 0.9f);
        return true;
    }
    return false;
}

// What a resize drag should affect, recovered from where the grab actually
// sits on the window rather than from Hyprland's own corner classification.
// Hyprland's mouse-resize dispatch has no "pure edge" concept at all — every
// grab is classified into one of the 4 diagonal quadrants (see
// DragController::dragBegin upstream), even a grab dead-center on an edge —
// so relying on that corner alone means ordinary hand jitter during a
// straight up/down (or left/right) drag leaks a spurious resize into the
// other axis. Instead, for a real mouse drag (corner != CORNER_NONE, so the
// live cursor position is meaningfully placed on this window), we measure
// how close the grab point is to each edge: only near-corner grabs (near an
// edge on BOTH axes) enable both axes; a grab near just one pair of edges
// enables only that axis, matching ordinary tiling-WM edge/corner semantics.
// For a programmatic resize (CORNER_NONE, e.g. a keybind), there's no
// meaningful grab point at all, so both axes stay enabled and side
// preference falls back to the delta's own sign, matching prior behavior.
struct SGrabZone {
    bool allowHorizontal = true, allowVertical = true;
    bool preferLeft = false, preferRight = false, preferTop = false, preferBottom = false;
};

static SGrabZone computeGrabZone(const SP<ITarget>& target, eRectCorner corner, const Vector2D& delta) {
    static constexpr double EDGE_ZONE = 0.2; // fraction of each dimension counted as "near that edge"

    SGrabZone zone;
    if (corner == CORNER_NONE) {
        zone.preferRight  = delta.x > 0;
        zone.preferLeft   = !zone.preferRight;
        zone.preferBottom = delta.y > 0;
        zone.preferTop    = !zone.preferBottom;
        return zone;
    }

    auto   box   = target->position();
    auto   mouse = g_pInputManager->getMouseCoordsInternal();
    double fx    = box.w > 0.0 ? (mouse.x - box.x) / box.w : 0.5;
    double fy    = box.h > 0.0 ? (mouse.y - box.y) / box.h : 0.5;

    zone.preferLeft      = fx < EDGE_ZONE;
    zone.preferRight     = fx > 1.0 - EDGE_ZONE;
    zone.preferTop       = fy < EDGE_ZONE;
    zone.preferBottom    = fy > 1.0 - EDGE_ZONE;
    zone.allowHorizontal = zone.preferLeft || zone.preferRight;
    zone.allowVertical   = zone.preferTop || zone.preferBottom;
    return zone;
}

class CUltrawideImprovedAlgorithm final : public ITiledAlgorithm {
  public:
    void newTarget(SP<ITarget> target) override {
        if (target->floating()) return;

        auto parent = m_parent.lock();
        if (!parent) {
            insertIntoNormalDwindle(target);
            return;
        }

        auto workArea = parent->space()->workArea();

        if (!isUltrawide(workArea)) {
            insertIntoNormalDwindle(target);
            recalculate();
            return;
        }

        placeNewUltrawideTarget(target, workArea);
        recalculate();
    }

    void movedTarget(SP<ITarget> target, std::optional<Vector2D>) override {
        if (target->floating()) return;

        auto parent = m_parent.lock();
        if (!parent) {
            if (!normalDwindleContains(target))
                insertIntoNormalDwindle(target);
            recalculate();
            return;
        }

        auto workArea = parent->space()->workArea();

        if (!isUltrawide(workArea)) {
            if (!normalDwindleContains(target))
                insertIntoNormalDwindle(target);
            recalculate();
            return;
        }

        bool known = false;
        for (auto& w : m_uwOrdered)
            if (w.lock() == target) { known = true; break; }

        if (!known)
            placeNewUltrawideTarget(target, workArea);

        recalculate();
    }

    void removeTarget(SP<ITarget> target) override {
        if (m_dwindleRoot) {
            if (m_dwindleRoot->isLeaf() && m_dwindleRoot->target == target)
                m_dwindleRoot.reset();
            else
                SDwindleNode::remove(m_dwindleRoot, target);
        }

        std::erase_if(m_uwOrdered, [&](auto& w) {
            auto l = w.lock();
            return !l || l == target;
        });

        auto colIt = m_colAssignment.find(target.get());
        if (colIt != m_colAssignment.end()) {
            int col = colIt->second;
            m_colAssignment.erase(colIt);

            if (m_colRoots[col]) {
                if (m_colRoots[col]->isLeaf() && m_colRoots[col]->target == target)
                    m_colRoots[col].reset();
                else
                    SDwindleNode::remove(m_colRoots[col], target);
            }

            compactColumns();

            // On ultrawide, restore columns lost to compaction if the
            // remaining window count still justifies them.
            auto parent2 = m_parent.lock();
            if (parent2) {
                auto wa = parent2->space()->workArea();
                if (isUltrawide(wa))
                    rebalanceColumns();
            }
        }

        recalculate();
    }

    void resizeTarget(const Vector2D& delta, SP<ITarget> target, eRectCorner corner) override {
        auto parent = m_parent.lock();
        if (!parent) return;
        auto workArea = parent->space()->workArea();

        if (!isUltrawide(workArea)) {
            if (!m_dwindleRoot) return;

            // The immediate parent only accounts for one axis (whichever
            // orientation it happens to split on) — a corner drag needs
            // both, so walk the full ancestor chain and resolve each axis
            // against whichever ancestor actually owns that boundary.
            std::vector<std::pair<SDwindleNode*, bool>> path;
            if (!m_dwindleRoot->buildPath(target, path)) return;

            auto zone = computeGrabZone(target, corner, delta);

            // Vertical-split (left/right) ancestors resolve delta.x: our
            // side is `first` (left) when dragging the right edge,
            // `second` (right) when dragging the left edge.
            if (delta.x != 0.0 && zone.allowHorizontal)
                resizeAlongPath(path, true, delta.x, workArea.w, zone.preferRight, zone.preferLeft);

            // Horizontal-split (top/bottom) ancestors resolve delta.y: our
            // side is `first` (top) when dragging the bottom edge,
            // `second` (bottom) when dragging the top edge.
            if (delta.y != 0.0 && zone.allowVertical)
                resizeAlongPath(path, false, delta.y, workArea.h, zone.preferBottom, zone.preferTop);

            recalculate();
            return;
        }

        auto colIt = m_colAssignment.find(target.get());
        if (colIt == m_colAssignment.end()) return;
        int col = colIt->second;

        auto zone   = computeGrabZone(target, corner, delta);
        auto colBox = computeColBox(workArea, col);

        std::vector<std::pair<SDwindleNode*, bool>> path;
        if (m_colRoots[col])
            m_colRoots[col]->buildPath(target, path);

        // Horizontal: an internal left/right split within this column (e.g.
        // two windows side by side in the same column) owns this boundary
        // if one exists on the dragged side; only if there's no such split
        // does this edge belong to the outer inter-column boundary instead.
        if (delta.x != 0.0 && zone.allowHorizontal &&
            !resizeAlongPath(path, true, delta.x, colBox.w, zone.preferRight, zone.preferLeft) && m_numCols > 1) {
            bool adjustRight = zone.preferRight;
            bool adjustLeft  = zone.preferLeft;

            bool hasLeft  = col - 1 >= 0;
            bool hasRight = col + 1 < m_numCols;

            if (adjustRight && hasRight) {
                float combined = m_colWidths[col] + m_colWidths[col + 1];
                float newThis  = std::clamp(
                    (float)(m_colWidths[col] + delta.x / workArea.w),
                    MIN_COL_FRAC * combined,
                    (1.0f - MIN_COL_FRAC) * combined);
                m_colWidths[col + 1] = combined - newThis;
                m_colWidths[col]     = newThis;
            } else if (adjustLeft && hasLeft) {
                float combined = m_colWidths[col - 1] + m_colWidths[col];
                float newThis  = std::clamp(
                    (float)(m_colWidths[col] - delta.x / workArea.w),
                    MIN_COL_FRAC * combined,
                    (1.0f - MIN_COL_FRAC) * combined);
                m_colWidths[col - 1] = combined - newThis;
                m_colWidths[col]     = newThis;
            } else if (adjustLeft && hasRight) {
                // Leftmost column: its left edge is pinned to the screen
                // edge and can't move, so a top/bottom-left corner drag
                // has no left boundary to act on. Fall back to the
                // column's right boundary instead, keeping the same
                // sign convention (shrink this column on positive
                // delta.x) a real left-edge drag would have.
                float combined = m_colWidths[col] + m_colWidths[col + 1];
                float newThis  = std::clamp(
                    (float)(m_colWidths[col] - delta.x / workArea.w),
                    MIN_COL_FRAC * combined,
                    (1.0f - MIN_COL_FRAC) * combined);
                m_colWidths[col + 1] = combined - newThis;
                m_colWidths[col]     = newThis;
            } else if (adjustRight && hasLeft) {
                // Rightmost column: symmetric fallback against its left
                // neighbor, since its own right edge is the screen edge.
                float combined = m_colWidths[col - 1] + m_colWidths[col];
                float newThis  = std::clamp(
                    (float)(m_colWidths[col] + delta.x / workArea.w),
                    MIN_COL_FRAC * combined,
                    (1.0f - MIN_COL_FRAC) * combined);
                m_colWidths[col - 1] = combined - newThis;
                m_colWidths[col]     = newThis;
            }
        }

        // Intra-column dwindle resize (delta.y). Walks the full ancestor
        // chain within the column, not just the immediate parent — e.g. two
        // windows side by side share a left/right split as their immediate
        // parent, so the top/bottom boundary against a window below them
        // (or above) sits one level further up and would otherwise never be
        // found.
        if (delta.y != 0.0 && zone.allowVertical)
            resizeAlongPath(path, false, delta.y, colBox.h, zone.preferBottom, zone.preferTop);

        recalculate();
    }

    void recalculate(eRecalculateReason reason = RECALCULATE_REASON_UNKNOWN) override {
        auto parent = m_parent.lock();
        if (!parent) return;
        auto workArea = parent->space()->workArea();

        if (!isUltrawide(workArea)) {
            if (m_dwindleRoot)
                m_dwindleRoot->layout(workArea);
            return;
        }

        for (int c = 0; c < m_numCols; c++) {
            if (!m_colRoots[c]) continue;
            CBox colBox = computeColBox(workArea, c);
            m_colRoots[c]->layout(colBox);
        }
    }

    SP<ITarget> getNextCandidate(SP<ITarget> old) override {
        auto tiled = getAllTiledTargets();
        if (tiled.empty()) return nullptr;
        auto it = std::ranges::find(tiled, old);
        if (it == tiled.end() || it == tiled.begin()) return tiled.back();
        return *std::prev(it);
    }

    void swapTargets(SP<ITarget> a, SP<ITarget> b) override {
        auto parent = m_parent.lock();
        if (!parent) return;
        auto workArea = parent->space()->workArea();

        if (!isUltrawide(workArea)) {
            if (m_dwindleRoot) m_dwindleRoot->swapTargets(a, b);
            recalculate();
            return;
        }

        auto itA = m_colAssignment.find(a.get());
        auto itB = m_colAssignment.find(b.get());
        if (itA == m_colAssignment.end() || itB == m_colAssignment.end()) return;

        std::swap(itA->second, itB->second);

        // swapTargets on each tree swaps the leaf pointers in place, so the trees
        // correctly reflect the new assignment after the map swap above.
        for (int c = 0; c < 3; c++) {
            if (m_colRoots[c]) m_colRoots[c]->swapTargets(a, b);
        }

        recalculate();
    }

    void moveTargetInDirection(SP<ITarget> t, Math::eDirection dir, bool) override {
        auto parent = m_parent.lock();
        if (!parent) return;
        auto workArea = parent->space()->workArea();

        if (!isUltrawide(workArea)) {
            auto tiled = getAllTiledTargets();
            int  idx   = -1;
            for (int i = 0; i < (int)tiled.size(); i++)
                if (tiled[i] == t) { idx = i; break; }
            if (idx < 0) return;
            int next = idx;
            switch (dir) {
                case Math::DIRECTION_LEFT:
                case Math::DIRECTION_UP:   next = idx - 1; break;
                case Math::DIRECTION_RIGHT:
                case Math::DIRECTION_DOWN: next = idx + 1; break;
                default: return;
            }
            if (next < 0 || next >= (int)tiled.size()) return;
            swapTargets(t, tiled[next]);
            return;
        }

        auto colIt = m_colAssignment.find(t.get());
        if (colIt == m_colAssignment.end()) return;
        int col = colIt->second;

        if (dir == Math::DIRECTION_LEFT || dir == Math::DIRECTION_RIGHT) {
            int newCol = col + (dir == Math::DIRECTION_RIGHT ? 1 : -1);
            if (newCol < 0 || newCol >= m_numCols) return;

            if (m_colRoots[col]) {
                if (m_colRoots[col]->isLeaf() && m_colRoots[col]->target == t)
                    m_colRoots[col].reset();
                else
                    SDwindleNode::remove(m_colRoots[col], t);
            }

            colIt->second = newCol;
            insertIntoColTree(newCol, t);
            recalculate();
            return;
        }

        // UP/DOWN: cycle within the column.
        auto colTargets = getColTargets(col);
        int  idx        = -1;
        for (int i = 0; i < (int)colTargets.size(); i++)
            if (colTargets[i] == t) { idx = i; break; }
        if (idx < 0) return;
        int next = idx + (dir == Math::DIRECTION_DOWN ? 1 : -1);
        if (next < 0 || next >= (int)colTargets.size()) return;
        swapTargets(t, colTargets[next]);
    }

  private:
    std::vector<WP<ITarget>>          m_uwOrdered;
    std::unordered_map<ITarget*, int> m_colAssignment;
    std::unique_ptr<SDwindleNode>     m_colRoots[3];
    float                             m_colWidths[3] = {1.0f, 0.0f, 0.0f};
    int                               m_numCols      = 0;

    std::unique_ptr<SDwindleNode> m_dwindleRoot;

    bool isUltrawide(const CBox& box) const {
        return box.h > 0.0 && (box.w / box.h) > ULTRAWIDE_RATIO;
    }

    CBox computeColBox(const CBox& workArea, int col) const {
        double x = workArea.x;
        for (int c = 0; c < col; c++)
            x += m_colWidths[c] * workArea.w;
        return {x, workArea.y, m_colWidths[col] * workArea.w, workArea.h};
    }

    // Pick column by proximity to evenly-spaced centroids (used for 2nd and 3rd window,
    // before stored colWidths are meaningful).
    int pickColumnByCentroid(const CBox& workArea, int numCols) const {
        double mouseX = g_pInputManager->getMouseCoordsInternal().x;
        double colW   = workArea.w / numCols;
        int    best   = 0;
        double bestD  = std::numeric_limits<double>::max();
        for (int c = 0; c < numCols; c++) {
            double centroid = workArea.x + colW * c + colW * 0.5;
            double d        = std::abs(mouseX - centroid);
            if (d < bestD) { bestD = d; best = c; }
        }
        return best;
    }

    // Pick column using actual stored colWidths (for 4th+ window or moved targets).
    int pickColumnByCentroidActual(const CBox& workArea) const {
        double mouseX = g_pInputManager->getMouseCoordsInternal().x;
        int    best   = 0;
        double bestD  = std::numeric_limits<double>::max();
        double x      = workArea.x;
        for (int c = 0; c < m_numCols; c++) {
            double w        = m_colWidths[c] * workArea.w;
            double centroid = x + w * 0.5;
            double d        = std::abs(mouseX - centroid);
            if (d < bestD) { bestD = d; best = c; }
            x += w;
        }
        return best;
    }

    std::vector<SP<ITarget>> getUltrawideTiledTargets() {
        std::erase_if(m_uwOrdered, [](auto& w) { return w.expired(); });
        std::vector<SP<ITarget>> result;
        for (auto& w : m_uwOrdered) {
            auto l = w.lock();
            if (l && !l->floating())
                result.push_back(l);
        }
        return result;
    }

    std::vector<SP<ITarget>> getColTargets(int col) const {
        std::vector<SP<ITarget>> result;
        if (m_colRoots[col])
            m_colRoots[col]->collectTargets(result);
        return result;
    }

    SP<ITarget> getNearestInCol(int col) const {
        auto colTargets = getColTargets(col);
        if (colTargets.empty()) return nullptr;
        auto        mousePos = g_pInputManager->getMouseCoordsInternal();
        double      bestDist = std::numeric_limits<double>::max();
        SP<ITarget> best;
        for (auto& t : colTargets) {
            auto   box = t->position();
            double cx  = box.x + box.w * 0.5;
            double cy  = box.y + box.h * 0.5;
            double d   = (mousePos.x - cx) * (mousePos.x - cx) + (mousePos.y - cy) * (mousePos.y - cy);
            if (d < bestDist) { bestDist = d; best = t; }
        }
        return best;
    }

    // Assign `target` a column the first time it enters ultrawide
    // tiling, growing m_numCols 1 -> 2 -> 3 as needed so the first
    // three windows always claim three separate columns regardless of
    // cursor position. Shared by newTarget and movedTarget's "unknown
    // target" branch so a window arriving either way (a brand new
    // window, or one coming back from floating, another workspace, or
    // a plugin reload) gets the same placement guarantees — only once
    // there are already 3+ columns does cursor position pick among the
    // existing ones (pickColumnByCentroidActual), since at that point
    // every column is already occupied and there's no empty slot to
    // guarantee.
    void placeNewUltrawideTarget(const SP<ITarget>& target, const CBox& workArea) {
        auto existing = getUltrawideTiledTargets();
        int  n        = (int)existing.size();

        if (n == 0) {
            m_numCols      = 1;
            m_colWidths[0] = 1.0f;
            m_colWidths[1] = 0.0f;
            m_colWidths[2] = 0.0f;
            m_colAssignment[target.get()] = 0;
            insertIntoColTree(0, target);

        } else if (n == 1) {
            m_numCols      = 2;
            m_colWidths[0] = 0.5f;
            m_colWidths[1] = 0.5f;
            m_colWidths[2] = 0.0f;

            // Cursor picks which column the NEW window occupies.
            // The existing window (currently in col 0) moves to the other column.
            int newCol      = pickColumnByCentroid(workArea, 2);
            int existingCol = 1 - newCol;

            if (existingCol != 0) {
                // Move existing window from col 0 to col 1.
                m_colAssignment[existing[0].get()] = existingCol;
                m_colRoots[existingCol]            = std::move(m_colRoots[0]);
                // m_colRoots[0] is now nullptr (moved-from)
            }
            // existingCol == 0 means newCol == 1: existing stays in col 0, new goes to col 1.

            m_colAssignment[target.get()] = newCol;
            insertIntoColTree(newCol, target);

        } else if (n == 2) {
            m_numCols      = 3;
            m_colWidths[0] = 1.0f / 3.0f;
            m_colWidths[1] = 1.0f / 3.0f;
            m_colWidths[2] = 1.0f / 3.0f;

            // The two existing windows are one-per-column under the
            // current 2-column layout (cols 0 and 1) — sort them into
            // left/right order so it can be preserved below.
            SP<ITarget> leftExisting  = existing[0];
            SP<ITarget> rightExisting = existing[1];
            if (m_colAssignment[leftExisting.get()] > m_colAssignment[rightExisting.get()])
                std::swap(leftExisting, rightExisting);

            // Cursor picks which of the 3 new columns the NEW window
            // claims; the two existing windows shift into the
            // remaining slots, keeping their relative left-right
            // order. Unlike just cursor-picking a slot for the new
            // window alone (the old, buggy approach — it could stack
            // onto an already-occupied column and leave column 2
            // permanently empty), this guarantees all three columns
            // end up occupied while still following the cursor,
            // mirroring the n==1 reshuffle above.
            int newCol = pickColumnByCentroid(workArea, 3);

            std::unique_ptr<SDwindleNode> rest[2]        = {std::move(m_colRoots[0]), std::move(m_colRoots[1])};
            SP<ITarget>                   restTargets[2] = {leftExisting, rightExisting};

            int ri = 0;
            for (int c = 0; c < 3; c++) {
                if (c == newCol) {
                    m_colRoots[c]         = std::make_unique<SDwindleNode>();
                    m_colRoots[c]->target = target;
                    m_colAssignment[target.get()] = c;
                } else {
                    m_colRoots[c]                        = std::move(rest[ri]);
                    m_colAssignment[restTargets[ri].get()] = c;
                    ri++;
                }
            }

        } else {
            int col = pickColumnByCentroidActual(workArea);
            m_colAssignment[target.get()] = col;
            insertIntoColTree(col, target);
        }

        m_uwOrdered.emplace_back(target);
    }

    void insertIntoColTree(int col, const SP<ITarget>& target) {
        if (!m_colRoots[col]) {
            m_colRoots[col]         = std::make_unique<SDwindleNode>();
            m_colRoots[col]->target = target;
            return;
        }
        auto nearest = getNearestInCol(col);
        if (nearest)
            m_colRoots[col]->insertNext(nearest, target, computeNewFirst(nearest));
        else
            appendToEnd(m_colRoots[col], target);
    }

    void compactColumns() {
        int remap[3] = {-1, -1, -1};
        int newIdx   = 0;
        for (int c = 0; c < m_numCols; c++) {
            if (m_colRoots[c])
                remap[c] = newIdx++;
        }

        int newNumCols = newIdx;
        if (newNumCols == m_numCols) return;

        for (auto& [ptr, col] : m_colAssignment) {
            if (remap[col] >= 0) col = remap[col];
        }

        std::unique_ptr<SDwindleNode> newRoots[3];
        for (int c = 0; c < m_numCols; c++) {
            if (remap[c] >= 0)
                newRoots[remap[c]] = std::move(m_colRoots[c]);
        }
        for (int c = 0; c < 3; c++)
            m_colRoots[c] = std::move(newRoots[c]);

        m_numCols = newNumCols;
        float frac = (m_numCols > 0) ? (1.0f / (float)m_numCols) : 1.0f;
        for (int c = 0; c < 3; c++)
            m_colWidths[c] = (c < m_numCols) ? frac : 0.0f;
    }

    // After compaction, restore columns up to min(total windows, 3) —
    // not just when exactly 3 remain. compactColumns() only ever
    // shrinks m_numCols (whenever any column empties out), so without
    // this, closing windows in the wrong order can strand a monitor at
    // 1-2 columns even with far more than 3 windows still open, and
    // every window added afterward keeps piling into those same few
    // columns instead of spreading back out to 3. Loops rather than a
    // single pop since compaction can drop more than one column at once.
    void rebalanceColumns() {
        int total = 0;
        for (int c = 0; c < m_numCols; c++)
            total += (int)getColTargets(c).size();

        int target = std::min(total, 3);
        while (m_numCols < target) {
            // Find the column with the most windows.
            int maxCol = 0, maxCount = 0;
            for (int c = 0; c < m_numCols; c++) {
                int cnt = (int)getColTargets(c).size();
                if (cnt > maxCount) { maxCount = cnt; maxCol = c; }
            }
            if (maxCount <= 1) break; // nothing left to redistribute

            // Take the last window (in tree order) from that column.
            auto colTargets = getColTargets(maxCol);
            auto toMove     = colTargets.back();

            if (m_colRoots[maxCol]->isLeaf() && m_colRoots[maxCol]->target == toMove)
                m_colRoots[maxCol].reset();
            else
                SDwindleNode::remove(m_colRoots[maxCol], toMove);

            int newCol = m_numCols;
            m_numCols++;
            m_colAssignment[toMove.get()] = newCol;
            m_colRoots[newCol]            = std::make_unique<SDwindleNode>();
            m_colRoots[newCol]->target    = toMove;
        }

        float frac = (m_numCols > 0) ? (1.0f / (float)m_numCols) : 1.0f;
        for (int c = 0; c < 3; c++)
            m_colWidths[c] = (c < m_numCols) ? frac : 0.0f;
    }

    bool normalDwindleContains(const SP<ITarget>& t) const {
        if (!m_dwindleRoot) return false;
        std::vector<SP<ITarget>> targets;
        m_dwindleRoot->collectTargets(targets);
        for (auto& x : targets)
            if (x == t) return true;
        return false;
    }

    SP<ITarget> getNearestInDwindle(const std::vector<SP<ITarget>>& targets) const {
        if (targets.empty()) return nullptr;
        auto        mousePos = g_pInputManager->getMouseCoordsInternal();
        SP<ITarget> best;
        double      bestDist = std::numeric_limits<double>::max();
        for (auto& t : targets) {
            auto   box = t->position();
            double cx  = box.x + box.w * 0.5;
            double cy  = box.y + box.h * 0.5;
            double d   = (mousePos.x - cx) * (mousePos.x - cx) + (mousePos.y - cy) * (mousePos.y - cy);
            if (d < bestDist) { bestDist = d; best = t; }
        }
        return best;
    }

    void insertIntoNormalDwindle(const SP<ITarget>& target) {
        if (target->floating()) return;

        if (!m_dwindleRoot) {
            m_dwindleRoot         = std::make_unique<SDwindleNode>();
            m_dwindleRoot->target = target;
            return;
        }

        std::vector<SP<ITarget>> existing;
        m_dwindleRoot->collectTargets(existing);
        std::erase_if(existing, [](const SP<ITarget>& t) { return t->floating(); });

        auto nearest = getNearestInDwindle(existing);
        if (nearest)
            m_dwindleRoot->insertNext(nearest, target, computeNewFirst(nearest));
        else
            appendToEnd(m_dwindleRoot, target);
    }

    std::vector<SP<ITarget>> getAllTiledTargets() {
        auto parent = m_parent.lock();
        if (!parent) return {};
        auto workArea = parent->space()->workArea();

        std::vector<SP<ITarget>> result;
        if (isUltrawide(workArea)) {
            for (int c = 0; c < m_numCols; c++) {
                if (m_colRoots[c])
                    m_colRoots[c]->collectTargets(result);
            }
        } else if (m_dwindleRoot) {
            m_dwindleRoot->collectTargets(result);
        }
        return result;
    }
};

APICALL EXPORT const char* __hyprland_api_get_hash() {
    return __hyprland_api_get_client_hash();
}

APICALL EXPORT std::string pluginAPIVersion() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO pluginInit(HANDLE handle) {
    g_handle = handle;
    HyprlandAPI::addTiledAlgo(
        handle,
        "ultrawide-dwindle-improved",
        &typeid(CUltrawideImprovedAlgorithm),
        []() -> UP<ITiledAlgorithm> { return makeUnique<CUltrawideImprovedAlgorithm>(); });

    return {"ultrawide-dwindle-improved",
            "Ultrawide-aware dwindle: fullscreen→2col→3col with per-column dwindle trees",
            "zach", "1.0"};
}

APICALL EXPORT void pluginExit() {}
