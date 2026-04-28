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

// Binary tree node for the normal-monitor dwindle layout.
// Leaves hold a window; internal nodes hold two children and a split ratio.
struct SDwindleNode {
    SP<ITarget>                   target; // non-null only for leaves
    std::unique_ptr<SDwindleNode> first, second; // non-null only for internal nodes
    float ratio  = 0.5f;
    bool  splitV = true; // updated each layout pass; used for resize

    bool isLeaf() const { return !!target; }

    void collectTargets(std::vector<SP<ITarget>>& out) const {
        if (isLeaf()) { out.push_back(target); return; }
        first->collectTargets(out);
        second->collectTargets(out);
    }

    // Replace the leaf holding `cur` with an internal node {cur, newT}.
    bool insertNext(const SP<ITarget>& cur, const SP<ITarget>& newT) {
        if (isLeaf()) {
            if (target != cur) return false;
            auto oldLeaf    = std::make_unique<SDwindleNode>();
            oldLeaf->target = cur;
            auto newLeaf    = std::make_unique<SDwindleNode>();
            newLeaf->target = newT;
            target          = nullptr;
            first           = std::move(oldLeaf);
            second          = std::move(newLeaf);
            return true;
        }
        return first->insertNext(cur, newT) || second->insertNext(cur, newT);
    }

    // Remove leaf holding `t`; caller's unique_ptr is replaced with the sibling.
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

    // Find the internal node that directly parents the leaf holding `t`.
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

class CUltrawideAlgorithm final : public ITiledAlgorithm {
  public:
    void newTarget(SP<ITarget> target) override {
        auto parent = m_parent.lock();
        if (parent) {
            auto workArea = parent->space()->workArea();
            if (isUltrawide(workArea)) {
                auto existing = getTiledTargets();
                int  idx      = (int)existing.size();
                m_ordered.emplace_back(target);
                m_colAssignment[target.get()] = (idx < 3) ? idx : cursorColumn(workArea);
            } else {
                insertDwindle(target);
                recalculate();
                return;
            }
        } else {
            m_ordered.emplace_back(target);
        }
        recalculate();
    }

    void movedTarget(SP<ITarget> target, std::optional<Vector2D>) override {
        auto parent = m_parent.lock();
        if (parent) {
            auto workArea = parent->space()->workArea();
            if (isUltrawide(workArea)) {
                bool found = false;
                for (auto& w : m_ordered)
                    if (w.lock() == target) { found = true; break; }
                if (!found) {
                    auto existing = getTiledTargets();
                    int  idx      = (int)existing.size();
                    m_ordered.emplace_back(target);
                    m_colAssignment[target.get()] = (idx < 3) ? idx : cursorColumn(workArea);
                }
            } else {
                if (!dwindleContains(target))
                    insertDwindle(target);
            }
        } else {
            m_ordered.emplace_back(target);
        }
        recalculate();
    }

    void removeTarget(SP<ITarget> target) override {
        std::erase_if(m_ordered, [&](auto& w) {
            auto l = w.lock();
            return !l || l == target;
        });
        m_colAssignment.erase(target.get());
        m_splitRatios.erase(target.get());
        m_splitDirections.erase(target.get());

        if (m_dwindleRoot) {
            if (m_dwindleRoot->isLeaf() && m_dwindleRoot->target == target)
                m_dwindleRoot.reset();
            else
                SDwindleNode::remove(m_dwindleRoot, target);
        }
        recalculate();
    }

    void resizeTarget(const Vector2D& delta, SP<ITarget> target, eRectCorner) override {
        auto parent = m_parent.lock();
        if (!parent) return;
        auto workArea = parent->space()->workArea();

        if (isUltrawide(workArea)) {
            auto tiled = getTiledTargets();
            if (tiled.size() <= 1) return;
            float& ratio = m_splitRatios[target.get()];
            auto   dirIt = m_splitDirections.find(target.get());
            bool   splitV = (dirIt != m_splitDirections.end()) ? dirIt->second : (workArea.w > workArea.h);
            double ref    = splitV ? workArea.w : workArea.h;
            double d      = splitV ? delta.x : delta.y;
            ratio = std::clamp((float)(ratio + d / ref * 2.0), 0.1f, 0.9f);
        } else {
            if (!m_dwindleRoot) return;
            auto* node = m_dwindleRoot->findParentOf(target);
            if (!node) return;
            double ref    = node->splitV ? workArea.w : workArea.h;
            double d      = node->splitV ? delta.x : delta.y;
            node->ratio = std::clamp((float)(node->ratio + d / ref * 2.0), 0.1f, 0.9f);
        }
        recalculate();
    }

    void recalculate() override {
        auto parent = m_parent.lock();
        if (!parent) return;
        auto workArea = parent->space()->workArea();

        if (isUltrawide(workArea)) {
            auto tiled = getTiledTargets();
            if (!tiled.empty())
                layoutUltrawide(tiled, workArea);
        } else {
            if (m_dwindleRoot)
                m_dwindleRoot->layout(workArea);
        }
    }

    SP<ITarget> getNextCandidate(SP<ITarget> old) override {
        auto parent = m_parent.lock();
        if (!parent) return nullptr;
        auto workArea = parent->space()->workArea();

        std::vector<SP<ITarget>> tiled;
        if (isUltrawide(workArea))
            tiled = getTiledTargets();
        else if (m_dwindleRoot)
            m_dwindleRoot->collectTargets(tiled);

        if (tiled.empty()) return nullptr;
        auto it = std::ranges::find(tiled, old);
        if (it == tiled.end() || it == tiled.begin()) return tiled.back();
        return *std::prev(it);
    }

    void swapTargets(SP<ITarget> a, SP<ITarget> b) override {
        auto parent = m_parent.lock();
        if (!parent) return;
        auto workArea = parent->space()->workArea();

        if (isUltrawide(workArea)) {
            auto itA = m_colAssignment.find(a.get());
            auto itB = m_colAssignment.find(b.get());
            if (itA != m_colAssignment.end() && itB != m_colAssignment.end())
                std::swap(itA->second, itB->second);
            for (auto& w : m_ordered) {
                auto l = w.lock();
                if      (l == a) w = b;
                else if (l == b) w = a;
            }
        } else {
            if (m_dwindleRoot)
                m_dwindleRoot->swapTargets(a, b);
        }
        recalculate();
    }

    void moveTargetInDirection(SP<ITarget> t, Math::eDirection dir, bool) override {
        auto parent = m_parent.lock();
        if (!parent) return;
        auto workArea = parent->space()->workArea();
        auto tiled    = getTiledTargets();

        if (isUltrawide(workArea) && (int)tiled.size() >= 3) {
            int col    = m_colAssignment.count(t.get()) ? m_colAssignment[t.get()] : 0;
            int newCol = col;
            switch (dir) {
                case Math::DIRECTION_LEFT:  newCol = col - 1; break;
                case Math::DIRECTION_RIGHT: newCol = col + 1; break;
                default: break;
            }
            newCol = std::clamp(newCol, 0, 2);
            if (newCol != col) {
                m_colAssignment[t.get()] = newCol;
                recalculate();
            }
            return;
        }

        std::vector<SP<ITarget>> ordered;
        if (isUltrawide(workArea))
            ordered = tiled;
        else if (m_dwindleRoot)
            m_dwindleRoot->collectTargets(ordered);

        int idx = -1;
        for (int i = 0; i < (int)ordered.size(); i++)
            if (ordered[i] == t) { idx = i; break; }
        if (idx < 0) return;

        int next = idx;
        switch (dir) {
            case Math::DIRECTION_LEFT:
            case Math::DIRECTION_UP:   next = idx - 1; break;
            case Math::DIRECTION_RIGHT:
            case Math::DIRECTION_DOWN: next = idx + 1; break;
            default: return;
        }
        if (next < 0 || next >= (int)ordered.size()) return;
        swapTargets(t, ordered[next]);
    }

  private:
    // Ultrawide: column-based list + per-column linear dwindle
    std::vector<WP<ITarget>>            m_ordered;
    std::unordered_map<ITarget*, int>   m_colAssignment;
    std::unordered_map<ITarget*, float> m_splitRatios;
    std::unordered_map<ITarget*, bool>  m_splitDirections;

    // Normal monitor: binary tree dwindle
    std::unique_ptr<SDwindleNode> m_dwindleRoot;

    bool isUltrawide(const CBox& box) const {
        return box.h > 0.0 && (box.w / box.h) > ULTRAWIDE_RATIO;
    }

    int cursorColumn(const CBox& workArea) const {
        auto   pos  = g_pInputManager->getMouseCoordsInternal();
        double relX = pos.x - workArea.x;
        double colW = workArea.w / 3.0;
        if (relX < colW)     return 0;
        if (relX < colW * 2) return 1;
        return 2;
    }

    SP<ITarget> getTargetUnderCursor(const std::vector<SP<ITarget>>& targets) const {
        auto pos = g_pInputManager->getMouseCoordsInternal();
        for (auto& t : targets) {
            auto box = t->position();
            if (pos.x >= box.x && pos.x < box.x + box.w &&
                pos.y >= box.y && pos.y < box.y + box.h)
                return t;
        }
        return nullptr;
    }

    SP<ITarget> getTargetNearestCursor(const std::vector<SP<ITarget>>& targets) const {
        if (targets.empty()) return nullptr;
        auto        pos      = g_pInputManager->getMouseCoordsInternal();
        SP<ITarget> best;
        double      bestDist = std::numeric_limits<double>::max();
        for (auto& t : targets) {
            auto   box  = t->position();
            double cx   = box.x + box.w * 0.5;
            double cy   = box.y + box.h * 0.5;
            double dx   = pos.x - cx;
            double dy   = pos.y - cy;
            double dist = dx * dx + dy * dy;
            if (dist < bestDist) { bestDist = dist; best = t; }
        }
        return best;
    }

    std::vector<SP<ITarget>> getTiledTargets() {
        std::erase_if(m_ordered, [](auto& w) { return w.expired(); });
        std::vector<SP<ITarget>> result;
        for (auto& w : m_ordered) {
            auto l = w.lock();
            if (l && !l->floating())
                result.push_back(l);
        }
        return result;
    }

    bool dwindleContains(const SP<ITarget>& t) const {
        if (!m_dwindleRoot) return false;
        std::vector<SP<ITarget>> targets;
        m_dwindleRoot->collectTargets(targets);
        for (auto& x : targets)
            if (x == t) return true;
        return false;
    }

    void insertDwindle(const SP<ITarget>& newTarget) {
        if (newTarget->floating()) return;

        if (!m_dwindleRoot) {
            m_dwindleRoot         = std::make_unique<SDwindleNode>();
            m_dwindleRoot->target = newTarget;
            return;
        }

        std::vector<SP<ITarget>> existing;
        m_dwindleRoot->collectTargets(existing);
        std::erase_if(existing, [](const SP<ITarget>& t) { return t->floating(); });

        auto cursorTarget = getTargetUnderCursor(existing);
        if (!cursorTarget)
            cursorTarget = getTargetNearestCursor(existing);

        if (cursorTarget)
            m_dwindleRoot->insertNext(cursorTarget, newTarget);
        else
            appendToEnd(m_dwindleRoot, newTarget);
    }

    // Append newTarget as the second child of the deepest rightmost node.
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

    float getSplitRatio(ITarget* t) {
        return m_splitRatios.emplace(t, 0.5f).first->second;
    }

    void layoutUltrawide(const std::vector<SP<ITarget>>& targets, const CBox& box) {
        int n = (int)targets.size();
        if (n <= 2) {
            double colW = box.w / n;
            for (int i = 0; i < n; i++) {
                CBox col{box.x + colW * i, box.y, colW, box.h};
                targets[i]->setPositionGlobal(col);
                targets[i]->warpPositionSize();
            }
            return;
        }

        double colW = box.w / 3.0;
        std::array<std::vector<SP<ITarget>>, 3> cols;
        for (auto& t : targets) {
            auto it  = m_colAssignment.find(t.get());
            int  col = (it != m_colAssignment.end()) ? it->second : 0;
            cols[col].push_back(t);
        }
        for (int c = 0; c < 3; c++) {
            if (cols[c].empty()) continue;
            CBox colBox{box.x + colW * c, box.y, colW, box.h};
            layoutDwindle(cols[c], colBox);
        }
    }

    void layoutDwindle(const std::vector<SP<ITarget>>& targets, const CBox& box) {
        if (targets.empty()) return;
        if (targets.size() == 1) {
            targets[0]->setPositionGlobal(box);
            targets[0]->warpPositionSize();
            return;
        }
        float  ratio  = getSplitRatio(targets[0].get());
        bool   splitV = box.w > box.h;
        m_splitDirections[targets[0].get()] = splitV;

        CBox first, rest;
        if (splitV) {
            double splitW = box.w * ratio;
            first = {box.x,          box.y, splitW,         box.h};
            rest  = {box.x + splitW, box.y, box.w - splitW, box.h};
        } else {
            double splitH = box.h * ratio;
            first = {box.x, box.y,          box.w, splitH        };
            rest  = {box.x, box.y + splitH, box.w, box.h - splitH};
        }
        targets[0]->setPositionGlobal(first);
        targets[0]->warpPositionSize();
        layoutDwindle({targets.begin() + 1, targets.end()}, rest);
    }
};

// --- Plugin entry points ---

APICALL EXPORT const char* __hyprland_api_get_hash() {
    return __hyprland_api_get_client_hash();
}

APICALL EXPORT std::string pluginAPIVersion() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO pluginInit(HANDLE handle) {
    HyprlandAPI::addTiledAlgo(
        handle,
        "ultrawide-dwindle",
        &typeid(CUltrawideAlgorithm),
        []() -> UP<ITiledAlgorithm> { return makeUnique<CUltrawideAlgorithm>(); });

    return {"ultrawide-dwindle",
            "Dwindle with equal 3-column support for ultrawide monitors",
            "zach", "1.0"};
}

APICALL EXPORT void pluginExit() {}
