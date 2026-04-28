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
#include <optional>
#include <unordered_map>
#include <vector>

using namespace Layout;

// Aspect ratio above which a monitor is considered ultrawide.
// 21:9 = 2.33, 32:9 = 3.56. Using 2.1 catches anything wider than ~17:8.
static constexpr double ULTRAWIDE_RATIO = 2.1;

class CUltrawideAlgorithm final : public ITiledAlgorithm {
  public:
    // --- ITiledAlgorithm interface ---

    void newTarget(SP<ITarget> target) override {
        auto parent = m_parent.lock();

        if (parent) {
            auto workArea = parent->space()->workArea();
            auto existing = getTiledTargets(); // snapshot before insertion

            if (isUltrawide(workArea)) {
                int idx = (int)existing.size(); // index the new window will occupy
                m_ordered.emplace_back(target);
                m_colAssignment[target.get()] = (idx < 3) ? idx : cursorColumn(workArea);
            } else {
                // Dwindle: insert after whichever existing window the cursor is on.
                auto cursorTarget = getTargetUnderCursor(existing);
                if (!cursorTarget)
                    cursorTarget = getTargetNearestCursor(existing);
                if (cursorTarget) {
                    for (auto it = m_ordered.begin(); it != m_ordered.end(); ++it) {
                        if (it->lock() == cursorTarget) {
                            m_ordered.insert(it, WP<ITarget>(target));
                            recalculate();
                            return;
                        }
                    }
                }
                m_ordered.emplace_back(target); // fallback: cursor not on any window
            }
        } else {
            m_ordered.emplace_back(target);
        }

        recalculate();
    }

    void movedTarget(SP<ITarget> target, std::optional<Vector2D>) override {
        bool found = false;
        for (auto& w : m_ordered) {
            if (w.lock() == target) { found = true; break; }
        }
        if (!found) {
            auto parent = m_parent.lock();
            if (parent) {
                auto workArea = parent->space()->workArea();
                auto existing = getTiledTargets();
                int  idx      = (int)existing.size();

                m_ordered.emplace_back(target);

                if (isUltrawide(workArea))
                    m_colAssignment[target.get()] = (idx < 3) ? idx : cursorColumn(workArea);
            } else {
                m_ordered.emplace_back(target);
            }
        }

        recalculate();
    }

    void removeTarget(SP<ITarget> target) override {
        std::erase_if(m_ordered, [&](auto& w) {
            auto l = w.lock();
            return !l || l == target;
        });
        m_splitRatios.erase(target.get());
        m_colAssignment.erase(target.get());
        m_splitDirections.erase(target.get());
        recalculate();
    }

    void resizeTarget(const Vector2D& delta, SP<ITarget> target, eRectCorner) override {
        auto tiled = getTiledTargets();
        if (tiled.size() <= 1) return;

        auto parent = m_parent.lock();
        if (!parent) return;
        auto workArea = parent->space()->workArea();

        float& ratio = m_splitRatios[target.get()];

        // Use the split direction cached during the last layout pass for this window.
        // layoutDwindle() determines direction from the local sub-box, not the full workspace,
        // so using workArea.w > workArea.h here would be wrong for nested splits.
        auto dirIt = m_splitDirections.find(target.get());
        bool splitV = (dirIt != m_splitDirections.end()) ? dirIt->second : (workArea.w > workArea.h);
        double ref  = splitV ? workArea.w : workArea.h;
        double d    = splitV ? delta.x : delta.y;
        ratio       = std::clamp((float)(ratio + d / ref * 2.0), 0.1f, 0.9f);

        recalculate();
    }

    void recalculate() override {
        auto parent = m_parent.lock();
        if (!parent) return;

        auto workArea = parent->space()->workArea();
        auto tiled    = getTiledTargets();
        if (tiled.empty()) return;

        if (isUltrawide(workArea))
            layoutUltrawide(tiled, workArea);
        else
            layoutDwindle(tiled, workArea);
    }

    SP<ITarget> getNextCandidate(SP<ITarget> old) override {
        auto tiled = getTiledTargets();
        if (tiled.empty()) return nullptr;

        auto it = std::ranges::find(tiled, old);
        if (it == tiled.end() || it == tiled.begin())
            return tiled.back();
        return *std::prev(it);
    }

    void swapTargets(SP<ITarget> a, SP<ITarget> b) override {
        // Swap column assignments so windows stay in their visual columns.
        auto itA = m_colAssignment.find(a.get());
        auto itB = m_colAssignment.find(b.get());
        if (itA != m_colAssignment.end() && itB != m_colAssignment.end())
            std::swap(itA->second, itB->second);

        for (auto& w : m_ordered) {
            auto l = w.lock();
            if (l == a)      w = b;
            else if (l == b) w = a;
        }
        recalculate();
    }

    void moveTargetInDirection(SP<ITarget> t, Math::eDirection dir, bool) override {
        auto parent = m_parent.lock();
        if (!parent) return;
        auto workArea = parent->space()->workArea();
        auto tiled    = getTiledTargets();
        int  idx      = getIndex(tiled, t);
        if (idx < 0) return;

        if (isUltrawide(workArea) && (int)tiled.size() >= 3) {
            // Move between columns on ultrawide.
            int col = m_colAssignment.count(t.get()) ? m_colAssignment[t.get()] : 0;
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
    }

  private:
    std::vector<WP<ITarget>>            m_ordered;
    std::unordered_map<ITarget*, float> m_splitRatios;
    std::unordered_map<ITarget*, int>   m_colAssignment;  // 0, 1, or 2 — ultrawide only
    std::unordered_map<ITarget*, bool>  m_splitDirections; // true=vertical split (left/right), false=horizontal

    bool isUltrawide(const CBox& box) const {
        return box.h > 0.0 && (box.w / box.h) > ULTRAWIDE_RATIO;
    }

    // Which of the 3 columns does the cursor currently sit in?
    int cursorColumn(const CBox& workArea) const {
        auto   pos  = g_pInputManager->getMouseCoordsInternal();
        double relX = pos.x - workArea.x;
        double colW = workArea.w / 3.0;
        if (relX < colW)     return 0;
        if (relX < colW * 2) return 1;
        return 2;
    }

    // Returns the tiled target whose bounding box contains the cursor, or nullptr.
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

    // Fallback: returns the tiled target whose center is geometrically closest to the cursor.
    // Used when the cursor is in a panel, gap, or otherwise not inside any window.
    SP<ITarget> getTargetNearestCursor(const std::vector<SP<ITarget>>& targets) const {
        if (targets.empty()) return nullptr;
        auto        pos     = g_pInputManager->getMouseCoordsInternal();
        SP<ITarget> best;
        double      bestDist = std::numeric_limits<double>::max();
        for (auto& t : targets) {
            auto   box  = t->position();
            double cx   = box.x + box.w * 0.5;
            double cy   = box.y + box.h * 0.5;
            double dx   = pos.x - cx;
            double dy   = pos.y - cy;
            double dist = dx * dx + dy * dy;
            if (dist < bestDist) {
                bestDist = dist;
                best     = t;
            }
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

    int getIndex(const std::vector<SP<ITarget>>& tiled, const SP<ITarget>& t) const {
        for (int i = 0; i < (int)tiled.size(); i++)
            if (tiled[i] == t) return i;
        return -1;
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

        // 3+ windows: 3 equal columns, each window in its assigned column.
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
