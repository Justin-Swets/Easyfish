-- EasyFish Pools: find and remember fishing pools (wreckage, schools, debris).
--
-- There is no API that lists pools, so this works two ways:
--
--   1. Named detection. Pools are game objects, so with soft-targeting on the client will name whatever your
--      cast is aimed at ("softinteract"). When that gives us a known pool name, we know for certain.
--   2. Burst heuristic. Pool loot ignores the junk roll and a pool is fished out in a handful of casts, so
--      several junk-free catches in quick succession from one spot is a pool even when we never saw its name.
--
-- Either way the spot is flagged, drawn with a distinct pin, and listed by /fish pools. Wreckage pools are
-- where trunks and crates come from, so this is how you make finding them repeatable.

local ADDON, NS = ...
local Print, safe = NS.Print, NS.safe

NS.CopyDefaults(NS.DEFAULTS, {
    poolTrack  = true,
    poolAlert  = true,   -- chat line when a pool is recognised
    poolBurst  = 3,      -- junk-free catches in a row at one spot before it counts as a pool
    poolWindow = 120,    -- ...within this many seconds
})

------------------------------------------------------------------------------------------------------------------------
-- Known pools (Classic). Keys are matched case-insensitively as substrings, so Forever's variants still hit.
------------------------------------------------------------------------------------------------------------------------
NS.POOLS = {
    { match = "wreckage",          kind = "treasure", note = "crates, trunks and cloth" },
    { match = "debris",            kind = "treasure", note = "crates and trunks" },
    { match = "flotsam",           kind = "treasure", note = "crates and trunks" },
    { match = "oily blackmouth",   kind = "fish",     note = "Oily Blackmouth" },
    { match = "firefin snapper",   kind = "fish",     note = "Firefin Snapper" },
    { match = "sagefish",          kind = "fish",     note = "Sagefish" },
    { match = "stonescale",        kind = "fish",     note = "Stonescale Eel" },
    { match = "mightfish",         kind = "fish",     note = "Mightfish" },
    { match = "lobster",           kind = "fish",     note = "Darkclaw Lobster" },
    { match = "school",            kind = "fish",     note = "a fish school" },
    { match = "elemental water",   kind = "special",  note = "Globe of Water" },
}

function NS.PoolInfo(name)
    if type(name) ~= "string" or name == "" then return nil end
    local lower = name:lower()
    for _, p in ipairs(NS.POOLS) do
        if lower:find(p.match, 1, true) then return p end
    end
    return nil
end

------------------------------------------------------------------------------------------------------------------------
-- Named detection: whatever the cast is aimed at
------------------------------------------------------------------------------------------------------------------------
local function AimedName()
    for _, token in ipairs({ "softinteract", "target", "mouseover" }) do
        if safe(UnitExists, token) then
            local name = safe(UnitName, token)
            if type(name) == "string" and NS.PoolInfo(name) then return name end
        end
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Recording
------------------------------------------------------------------------------------------------------------------------
local burst = { spot = nil, n = 0, last = 0 }
local castPool  -- pool name seen when this cast started

local function MarkPool(spot, name, certain)
    if not spot then return end
    spot.pool = (spot.pool or 0) + 1
    spot.poolCertain = spot.poolCertain or certain
    if name then
        spot.poolNames = spot.poolNames or {}
        spot.poolNames[name] = (spot.poolNames[name] or 0) + 1
    end
    if NS.db.poolAlert and not spot.poolAnnounced then
        spot.poolAnnounced = true
        local info = name and NS.PoolInfo(name)
        Print("|cff44ff44Pool:|r %s%s - this spot is now marked on your map.",
            name or "unnamed pool (detected from a run of clean catches)",
            info and (" - " .. info.note) or "")
    end
end

NS.On("UNIT_SPELLCAST_CHANNEL_START", function(_, _, spellID)
    if not NS.db.poolTrack or not NS.IsFishingSpell(spellID) then return end
    castPool = AimedName()
end)

NS.OnCatch(function(loot)
    if not NS.db.poolTrack then return end
    local spot = NS.CurrentSpot and NS.CurrentSpot()
    if not spot then return end

    -- Certain: we saw the pool's name
    if castPool then
        MarkPool(spot, castPool, true)
        castPool = nil
        burst.spot, burst.n = nil, 0
        return
    end

    -- Heuristic: a run of junk-free catches from one spot
    local clean = true
    for _, item in ipairs(loot) do
        if NS.IsJunk(item) then clean = false break end
    end
    local now = GetTime()
    if not clean or (burst.spot ~= spot) or (now - burst.last > (NS.db.poolWindow or 120)) then
        burst.spot, burst.n = clean and spot or nil, clean and 1 or 0
    else
        burst.n = burst.n + 1
    end
    burst.last = now
    if burst.n >= (NS.db.poolBurst or 3) and not spot.poolCertain then
        MarkPool(spot, nil, false)
        burst.n = 0
    end
end)

function NS.IsPoolSpot(spot)
    return spot and (spot.pool or 0) > 0
end

-- Best label for a pool spot
function NS.PoolLabel(spot)
    if not spot.poolNames then return spot.poolCertain and "pool" or "likely pool" end
    local best, bestN
    for name, n in pairs(spot.poolNames) do
        if not bestN or n > bestN then best, bestN = name, n end
    end
    return best or "pool"
end

------------------------------------------------------------------------------------------------------------------------
-- Reports
------------------------------------------------------------------------------------------------------------------------
local function PoolList(zoneOnly)
    local zone = GetRealZoneText()
    local list = {}
    for _, map in pairs(NS.db.spots) do
        for _, spot in pairs(map) do
            if NS.IsPoolSpot(spot) and (not zoneOnly or spot.zone == zone) then list[#list + 1] = spot end
        end
    end
    table.sort(list, function(a, b) return (a.pool or 0) > (b.pool or 0) end)
    return list
end

NS.AddCommand("pools", function(rest)
    rest = strtrim(rest or "")
    local zoneOnly = rest ~= "all"
    local list = PoolList(zoneOnly)
    Print("Pools you have fished %s:", zoneOnly and ("in " .. (GetRealZoneText() or "?")) or "(everywhere)")
    for i = 1, math.min(#list, 12) do
        local s = list[i]
        local chests = (s.chests or 0) > 0 and (", %d chests"):format(s.chests) or ""
        Print("  %s - %s / %s, %d pool catches%s%s", NS.PoolLabel(s), s.zone or "?",
            (s.sub and s.sub ~= "") and s.sub or "-", s.pool or 0, chests, s.poolCertain and "" or " |cffaaaaaa(inferred)|r")
    end
    if #list == 0 then
        Print("  none yet. Wreckage pools are the floating planks and barrels along coastlines - cast into them.")
        if zoneOnly then Print("  /fish pools all checks every zone.") end
    end
end, "[all] pools you have found here (or everywhere)")

------------------------------------------------------------------------------------------------------------------------
-- Dashboard
------------------------------------------------------------------------------------------------------------------------
function NS.PoolLine()
    if not NS.db.poolTrack then return nil end
    local spot = NS.CurrentSpot and NS.CurrentSpot()
    if spot and NS.IsPoolSpot(spot) then
        return ("|cff44ff44Pool here:|r %s, %d catches"):format(NS.PoolLabel(spot), spot.pool or 0)
    end
    local here = PoolList(true)
    if #here == 0 then return nil end
    return ("|cff88ccffPools in this zone:|r %d known |cffaaaaaa(see map)|r"):format(#here)
end

------------------------------------------------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------------------------------------------------
local tab = NS.NewTab("Pools")
tab:Header("Pool tracking")
tab:Text("Pools are not exposed to addons, so EasyFish recognises them two ways: by name when the client tells us what your cast is aimed at (turn on keyboard fishing in Extras to make this work more often), and by spotting a run of junk-free catches from one place. Pool spots get a distinct map pin.", true)
tab:Check("Track pools", "poolTrack")
tab:Check("Announce a pool when it is recognised", "poolAlert")
tab:Slider("Clean catches before a spot counts as a pool", "poolBurst", 2, 8, 1, "%d")
tab:Button("Pools in this zone", function() SlashCmdList.EASYFISH("pools") end, 160)
tab:Button("All pools", function() SlashCmdList.EASYFISH("pools all") end, 160)
tab:Text("Wreckage and debris pools are where crates and trunks come from. Fish them out - they despawn after a few catches - then move along the coast to the next one.", true)
