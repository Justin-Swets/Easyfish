"""Loads the whole EasyFish addon in Lua 5.1 against tests/wow_stub.lua and measures what runs while you play.

    python tests/perf.py

Reports, for a small history and a large one:
  * the status window's once-a-second update: time and memory allocated per update
  * the minimap pin update (every 0.5 s): time and memory per update
and lists any global variables the addon creates that it shouldn't.
Timings are Lua 5.1 on this PC, not the game client; compare runs against each other, not against the game.
"""
import os
import re
from lupa.lua51 import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "EasyFish")

EXPECTED_GLOBALS = re.compile(r"^(EasyFish.*|SLASH_EASYFISH\d|BINDING_.*|EasyFishDB)$")


def load_addon():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(os.path.join(ROOT, "tests", "wow_stub.lua"), encoding="utf-8").read())
    lua.execute("STUB_BEFORE = {} for k in pairs(_G) do STUB_BEFORE[k] = true end")
    lua.execute("NS = {}")
    loader = lua.eval("function(src, name) local f, e = loadstring(src, name) if not f then error(e) end return f end")
    toc = open(os.path.join(ADDON, "EasyFish.toc"), encoding="utf-8").read().splitlines()
    for line in toc:
        line = line.strip()
        if line.endswith(".lua"):
            loader(open(os.path.join(ADDON, line), encoding="utf-8").read(), line)("EasyFish", lua.globals().NS)
    lua.execute('fire("ADDON_LOADED", "EasyFish") fire("PLAYER_ENTERING_WORLD") flushTimers()')
    return lua


SEED = r'''
function seed(maps, spotsPerMap, itemsPerSpot)
    local db = NS.db
    local fish = {}
    for i = 1, 40 do fish[i] = "Raw Test Fish " .. i end
    for m = 1, maps do
        local mapID = (m == 1) and S.mapID or (2000 + m)
        db.spots[mapID] = db.spots[mapID] or {}
        for s = 1, spotsPerMap do
            local spot = { x = (s % 50) / 50, y = math.floor(s / 50) / 50, n = 20, casts = 20, catches = 15, junk = 2,
                           seconds = 400, zone = (m == 1) and S.zone or ("Zone " .. m), sub = "Somewhere",
                           items = {}, hours = { [20] = 20 }, mats = {}, chests = (s % 7 == 0) and 1 or 0,
                           pool = (s % 11 == 0) and 3 or nil }
            for k = 1, itemsPerSpot do
                local name = fish[((s + k) % #fish) + 1]
                spot.items[name] = { n = 3, hours = { [20] = 3 } }
                spot.mats[name] = 3
            end
            db.spots[mapID][s .. ":" .. m] = spot
        end
        local zone = (m == 1) and S.zone or ("Zone " .. m)
        db.mats[zone] = {}
        for k = 1, 20 do db.mats[zone][fish[k]] = { n = 10, chest = 1, prof = "Cooking" } end
    end
    for k = 1, #fish do db.totals[fish[k]] = 50 end
    db.chestLoot["Iron Bound Trunk"] = { ["Thick Leather"] = 3, ["Greater Healing Potion"] = 4 }
    db.profs.Cooking = true
    NS.session.count, NS.session.casts, NS.session.copper, NS.session.value = 30, 40, 5000, 6000
    NS.session.activeSeconds = 1200
end

function measure(fn, n)
    collectgarbage("collect")
    collectgarbage("stop")
    local mem0, t0 = collectgarbage("count"), os.clock()
    for i = 1, n do S.t = S.t + 1.1 fn() end
    local t1, mem1 = os.clock(), collectgarbage("count")
    collectgarbage("restart")
    return (t1 - t0) / n * 1000, (mem1 - mem0) / n
end

function statusTick() local f = frames.EasyFishStatus f.scripts.OnUpdate(f, 1.1) end
-- the heatmap's minimap ticker is the unnamed frame with an OnUpdate
function findTicker()
    for _, f in ipairs(STUB_FRAMES) do
        if f.scripts.OnUpdate and not f.name then return f end
    end
end
function minimapTick() local f = MINIMAP_TICKER f.scripts.OnUpdate(f, 0.6) end
'''


def report(label, lua, maps, spots, items):
    lua.execute(f"seed({maps}, {spots}, {items})")
    lua.execute("MINIMAP_TICKER = findTicker()")
    s_ms, s_kb = lua.eval("measure(statusTick, 200)")
    m_ms, m_kb = lua.eval("measure(minimapTick, 200)")
    print(f"{label:<34} status window: {s_ms:7.3f} ms, {s_kb:7.1f} KB per update   "
          f"minimap pins: {m_ms:7.3f} ms, {m_kb:7.1f} KB per update")
    return s_ms, s_kb, m_ms, m_kb


def main():
    results = {}
    for label, maps, spots, items in [("small history (like yours today)", 1, 5, 4),
                                      ("large history (months of fishing)", 25, 80, 8)]:
        lua = load_addon()
        lua.execute(SEED)
        results[label] = report(label, lua, maps, spots, items)

    lua = load_addon()
    created = [k for k in lua.eval("(function() local t = {} for k in pairs(_G) do if not STUB_BEFORE[k] then t[#t+1] = k end end return t end)()").values()]
    stray = sorted(k for k in created if not EXPECTED_GLOBALS.match(str(k)) and k not in ("NS",))
    print("\nglobals the addon created that it shouldn't:", ", ".join(stray) if stray else "none")
    return results


if __name__ == "__main__":
    main()
