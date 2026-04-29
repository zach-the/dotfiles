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
#include <vector>

using namespace Layout;

static constexpr double ULTRAWIDE_RATIO = 2.1;
static constexpr float  MIN_COL_FRAC    = 0.1f;

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
    bool insertNext(const SP<ITarget>& cur, const SP<ITarget>& newT, bool newFirst = false) {
        if (isLeaf()) {
            if (target != cur) return false;
            auto oldLeaf    = std::make_unique<SDwindleNode>();
            oldLeaf->target = cur;
            auto newLeaf    = std::make_unique<SDwindleNode>();
            newLeaf->target = newT;
            target          = nullptr;
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

    SDwindleNode* findParentOf(const SP<ITarget>& t) {
        if (isLeaf()) return nullptr;
        if ((first->isLeaf()  && first->target  == t) ||
            (second->isLeaf() && second->target == t))
            return this;
        auto* r = first->findParentOf(t);
        return r ? r : second->findParentOf(t);
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
        splitV = box.w > box.h;
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
        node->target    = nullptr;
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
            int col = pickColumnByCentroid(workArea, 3);
            m_colAssignment[target.get()] = col;
            insertIntoColTree(col, target);

        } else {
            int col = pickColumnByCentroidActual(workArea);
            m_colAssignment[target.get()] = col;
            insertIntoColTree(col, target);
        }

        m_uwOrdered.emplace_back(target);
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

        if (!known) {
            int col = (m_numCols > 0) ? pickColumnByCentroidActual(workArea) : 0;
            if (m_numCols == 0) {
                m_numCols      = 1;
                m_colWidths[0] = 1.0f;
                col            = 0;
            }
            m_colAssignment[target.get()] = col;
            insertIntoColTree(col, target);
            m_uwOrdered.emplace_back(target);
        }

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

            // On ultrawide with exactly 3 remaining windows, ensure we have 3 equal columns.
            auto parent2 = m_parent.lock();
            if (parent2) {
                auto wa = parent2->space()->workArea();
                if (isUltrawide(wa))
                    tryRebalanceToThreeCols();
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
            auto* node = m_dwindleRoot->findParentOf(target);
            if (!node) return;
            double ref  = node->splitV ? workArea.w : workArea.h;
            double d    = node->splitV ? delta.x : delta.y;
            node->ratio = std::clamp((float)(node->ratio + d / ref * 2.0), 0.1f, 0.9f);
            recalculate();
            return;
        }

        auto colIt = m_colAssignment.find(target.get());
        if (colIt == m_colAssignment.end()) return;
        int col = colIt->second;

        // Column boundary resize (delta.x).
        if (delta.x != 0.0 && m_numCols > 1) {
            bool adjustRight = false;
            bool adjustLeft  = false;
            switch (corner) {
                case CORNER_TOPRIGHT:
                case CORNER_BOTTOMRIGHT: adjustRight = true; break;
                case CORNER_TOPLEFT:
                case CORNER_BOTTOMLEFT:  adjustLeft  = true; break;
                default:
                    if (delta.x > 0) adjustRight = true;
                    else             adjustLeft  = true;
                    break;
            }

            if (adjustRight && col + 1 < m_numCols) {
                float combined = m_colWidths[col] + m_colWidths[col + 1];
                float newThis  = std::clamp(
                    (float)(m_colWidths[col] + delta.x / workArea.w),
                    MIN_COL_FRAC * combined,
                    (1.0f - MIN_COL_FRAC) * combined);
                m_colWidths[col + 1] = combined - newThis;
                m_colWidths[col]     = newThis;
            } else if (adjustLeft && col - 1 >= 0) {
                float combined = m_colWidths[col - 1] + m_colWidths[col];
                float newThis  = std::clamp(
                    (float)(m_colWidths[col] - delta.x / workArea.w),
                    MIN_COL_FRAC * combined,
                    (1.0f - MIN_COL_FRAC) * combined);
                m_colWidths[col - 1] = combined - newThis;
                m_colWidths[col]     = newThis;
            }
        }

        // Intra-column dwindle resize (delta.y).
        if (delta.y != 0.0 && m_colRoots[col]) {
            auto* node = m_colRoots[col]->findParentOf(target);
            if (node && !node->splitV) {
                CBox colBox = computeColBox(workArea, col);
                node->ratio = std::clamp(
                    (float)(node->ratio + delta.y / colBox.h * 2.0),
                    0.1f, 0.9f);
            }
        }

        recalculate();
    }

    void recalculate() override {
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

    // After compaction, if exactly 3 tiled windows remain but we have fewer than 3 columns,
    // pop the last window from the largest column into a new rightmost column.
    void tryRebalanceToThreeCols() {
        if (m_numCols >= 3) return;

        int total = 0;
        for (int c = 0; c < m_numCols; c++)
            total += (int)getColTargets(c).size();
        if (total != 3) return;

        // Find the column with the most windows.
        int maxCol = 0, maxCount = 0;
        for (int c = 0; c < m_numCols; c++) {
            int cnt = (int)getColTargets(c).size();
            if (cnt > maxCount) { maxCount = cnt; maxCol = c; }
        }
        if (maxCount <= 1) return;

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

        float frac = 1.0f / (float)m_numCols;
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
