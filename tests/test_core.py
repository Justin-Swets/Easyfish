"""Behaviour tests for EasyFish, run against the real addon code with a simulated WoW API.

    python tests/test_core.py

Covers double right-click safety, the dashboard's caching (it must refresh exactly when something changes), and
that looking at the dashboard never creates fishing spots.
"""
import sys
from perf import load_addon

results = []


def check(label, got, want):
    ok = got == want
    results.append(ok)
    print(("PASS " if ok else "FAIL ") + f"{label}: {got!r}" + ("" if ok else f"  (expected {want!r})"))


HELPERS = r'''
function reset(pole, mouseover, combat) S.pole, S.mouseover, S.combat = pole, mouseover, combat; S.armedWith = nil; S.equipped = {}; S.queue = {} end
function rightClick()
    for _, fn in ipairs(WorldFrame.hooks.OnMouseDown) do fn(WorldFrame, "RightButton") end
    S.t = S.t + 0.1
    for _, fn in ipairs(WorldFrame.hooks.OnMouseUp) do fn(WorldFrame, "RightButton") end
    flushTimers()
end
function castClick(button)
    local b = frames.EasyFishCastButton
    b.scripts.PreClick(b, button, true)
    local acted = b.attrs.type ~= nil
    b.scripts.PostClick(b, button, true)
    return acted
end
-- a full fishing cast and catch, the way the game reports it
function fishAndCatch(name, quantity)
    fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast", 7620)
    fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast", 7620)
    S.fishingLoot, S.loot = true, { { name = name, quantity = quantity or 1, quality = 1 } }
    fire("LOOT_OPENED")
    fire("LOOT_CLOSED")
    S.loot = {}
    flushTimers()
end
function spotCount()
    local n = 0
    for _, spots in pairs(NS.db.spots) do for _ in pairs(spots) do n = n + 1 end end
    return n
end
function statusTick() local f = frames.EasyFishStatus f.scripts.OnUpdate(f, 1.1) end
function topNames()
    local t = {}
    for i, row in ipairs(NS.TopFishRows().rows) do t[i] = (row.name:gsub(" |c.*", "")) end   -- drop the grey skill number
    return table.concat(t, ",")
end
'''


def new():
    lua = load_addon()
    lua.execute(HELPERS)
    return lua


print("=== double right-click safety")
lua = new(); run = lua.eval; ex = lua.execute
ex("reset(false, false, false)"); ex("rightClick()")
check("no pole: double right-click arms", run("S.armedWith"), None)
check("no pole: gear equipped", run("#S.equipped"), 0)
ex("reset(true, false, false)"); ex("rightClick()")
check("pole on open water: arms as a double-click", run("S.armedWith"), "EasyCast")
check("pole on open water: second click casts", run("castClick('EasyCast')"), True)
ex("reset(true, true, false)"); ex("rightClick()")
check("over a creature: arms", run("S.armedWith"), None)
ex("reset(true, false, false)"); ex("rightClick()"); ex("S.mouseover = true")
check("moved onto a creature before the 2nd click: casts", run("castClick('EasyCast')"), False)
check("action restored after a swallowed click", run("frames.EasyFishCastButton.attrs.type"), "macro")
ex("reset(true, false, true)"); ex("rightClick()")
check("in combat: arms", run("S.armedWith"), None)
ex("reset(true, false, false)"); ex("rightClick()"); ex("S.pole = false")
check("pole removed before the 2nd click: casts", run("castClick('EasyCast')"), False)
check("pole removed before the 2nd click: equips", run("#S.equipped"), 0)
ex("reset(false, false, false)"); ex("castClick('LeftButton')")
check("Cast key without a pole: equips it (deliberate)", run("#S.equipped"), 1)

print("\n=== looking at the dashboard never creates spots")
lua = new(); run = lua.eval; ex = lua.execute
for x in (0.10, 0.20, 0.30, 0.40, 0.50):
    ex(f"S.x = {x}; statusTick(); flushTimers()")
check("spots after walking through 5 places with the window open", run("spotCount()"), 0)
ex("fishAndCatch('Raw Rockscale Cod')")
check("spots after one real cast", run("spotCount()"), 1)

print("\n=== empty spots from older versions are cleaned up on load")
lua = load_addon()
lua.execute('''
NS.db.spots[1434] = {
    ["1:1"] = { x = 0.1, y = 0.1, n = 0, casts = 0, catches = 0, junk = 0, items = {}, hours = {}, seconds = 0 },
    ["2:2"] = { x = 0.2, y = 0.2, n = 3, casts = 3, catches = 2, junk = 0, items = { ["Raw Rockscale Cod"] = { n = 2, hours = {} } }, hours = {}, seconds = 30 },
}
NS.db.spots[9999] = { ["3:3"] = { x = 0.3, y = 0.3, n = 0, casts = 0, catches = 0, junk = 0, items = {}, hours = {}, seconds = 0 } }
fire("ADDON_LOADED", "EasyFish")
''')
lua.execute(HELPERS)
check("fished spot kept", lua.eval("NS.db.spots[1434]['2:2'] ~= nil"), True)
check("empty spot removed", lua.eval("NS.db.spots[1434]['1:1'] == nil"), True)
check("map left with no spots removed", lua.eval("NS.db.spots[9999] == nil"), True)

print("\n=== dashboard cache refreshes exactly when something changes")
lua = new(); run = lua.eval; ex = lua.execute
ex("fishAndCatch('Raw Rockscale Cod', 3)")
check("top fish after first catch", run("topNames()"), "Rockscale Cod")
ex("fishAndCatch('Oily Blackmouth', 5)")
check("top fish updates after the next catch", run("topNames()").split(",")[0], "Oily Blackmouth")
# change data behind the addon's back with no event: the cache should (correctly) not notice...
ex("NS.db.spots[S.mapID][next(NS.db.spots[S.mapID])].items['Raw Firefin Snapper'] = { n = 50, hours = {} }")
check("no event yet: cached value kept", run("topNames()").split(",")[0], "Oily Blackmouth")
# ...until any game event
ex('fire("BAG_UPDATE_DELAYED")')
check("after any event: refreshed", run("topNames()").split(",")[0], "Firefin Snapper")
ex("S.mapID = 1435")
check("different map: refreshed without an event", run("NS.TopFishRows().header"), "TOP FISH THIS SESSION")
ex("S.mapID = 1434")

print("\n=== an item the game hasn't loaded yet is retried, not cached blank")
lua = new(); run = lua.eval; ex = lua.execute
ex('''
ITEMS[777] = { "Raw Mystery Fish", 7, 8, 55 }
LOADED = false
local orig = C_Item.GetItemInfo
C_Item.GetItemInfo = function(item) if item == "Raw Mystery Fish" and not LOADED then return nil end return orig(item) end
GetItemInfo = C_Item.GetItemInfo
''')
ex("fishAndCatch('Raw Mystery Fish')")
check("price while item info missing", run("NS.TopFishRows().rows[1].value"), "")
ex("LOADED = true")
check("price once the game has the item (no event needed)", run("NS.TopFishRows().rows[1].value") != "", True)

print(f"\n{sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
