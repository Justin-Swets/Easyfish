"""Smoke test: exercises every slash command, settings tab and event handler, and reports any error that EasyFish's
protective pcall wrappers would otherwise swallow silently in game, plus WoW globals it touched that the stub
doesn't define (to spot typos).

    python tests/smoke.py
"""
import sys
from perf import load_addon, SEED

lua = load_addon()
lua.execute(SEED)
lua.execute("seed(3, 20, 4)")
lua.execute(r'''
ERRORS = {}
local realPcall = pcall
pcall = function(fn, ...)
    local results = { realPcall(fn, ...) }
    if not results[1] then
        local msg = tostring(results[2])
        -- expected failures: optional WoW APIs the stub leaves as dummies
        if not msg:find("Settings") and not msg:find("WorldMapFrame") then ERRORS[#ERRORS + 1] = msg end
    end
    return unpack(results)
end

local commands = { "", "status", "where", "spots", "pools", "pools all", "trainer", "trainer go", "find Rockscale",
    "mats", "mats all", "chests", "want Raw Test Fish 3", "want", "price", "price Raw Test Fish 3", "scan", "stats",
    "toggle", "toggle", "sound", "sound", "loot", "loot", "show", "show", "minimap", "minimap", "chest Old Crate",
    "chest", "keyboard", "keyboard", "spell", "reset", "help" }
for _, c in ipairs(commands) do
    local ok, err = realPcall(SlashCmdList.EASYFISH, c)
    if not ok then ERRORS[#ERRORS + 1] = "/fish " .. c .. ": " .. tostring(err) end
    flushTimers()
end

-- open the settings panel on every tab (runs every tab's refresh functions)
local options = frames.EasyFishOptions
for i = 1, 10 do
    local ok, err = realPcall(function() if options.scripts.OnShow then options.scripts.OnShow(options) end end)
    if not ok then ERRORS[#ERRORS + 1] = "settings: " .. tostring(err) end
end

for _, ev in ipairs({ "MERCHANT_SHOW", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "QUEST_LOG_UPDATE",
                      "PLAYER_TARGET_CHANGED", "SKILL_LINES_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED",
                      "ZONE_CHANGED_NEW_AREA", "LOOT_BIND_CONFIRM", "PLAYER_LOGOUT" }) do
    local ok, err = realPcall(fire, ev)
    if not ok then ERRORS[#ERRORS + 1] = ev .. ": " .. tostring(err) end
    flushTimers()
end
for i = 1, 5 do
    local f = frames.EasyFishStatus f.scripts.OnUpdate(f, 1.1)
    for _, t in ipairs(STUB_FRAMES) do if t.scripts.OnUpdate and not t.name then t.scripts.OnUpdate(t, 0.6) end end
end
''')
errors = list(lua.eval("ERRORS").values())
unknown = sorted(k for k in lua.eval("STUB_UNKNOWN").keys())
print("errors caught:", len(errors))
for e in errors:
    print("  -", e)
print("WoW globals touched that the stub doesn't define:", ", ".join(unknown))
sys.exit(1 if errors else 0)
