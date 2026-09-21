-- EasyFish Trainers: where to learn the next fishing rank.
--
-- Classic rules: Apprentice 1-75 and Journeyman 75-150 from any fishing trainer; Expert 150-225 from the book
-- "Expert Fishing - The Bass and You" sold by Old Man Heming in Booty Bay; Artisan 225-300 from Nat Pagle's quest
-- in Dustwallow Marsh. Forever may change this - the data is a plain table below.
-- Coordinates are approximate (zone %), enough to set a waypoint. Corrections welcome.

local ADDON, NS = ...
local Print, safe = NS.Print, NS.safe

NS.RANKS = {
    { cap = 75,  name = "Apprentice", next = "Journeyman", level = 10, how = "any fishing trainer" },
    { cap = 150, name = "Journeyman", next = "Expert",     level = 20, how = "book from Old Man Heming, Booty Bay (skill 125)" },
    { cap = 225, name = "Expert",     next = "Artisan",    level = 35, how = "quest 'Nat Pagle, Angler Extreme' - Nat Pagle, Dustwallow Marsh (skill 225)" },
    { cap = 300, name = "Artisan",    next = nil },
}

-- faction: "Alliance", "Horde" or "Neutral"
NS.TRAINERS = {
    -- Alliance
    { name = "Arnold Leland",     zone = "Stormwind City",   x = 55, y = 68, faction = "Alliance", note = "canal by the Cathedral Square docks" },
    { name = "Grimnur Stonebrand",zone = "Ironforge",        x = 48, y = 27, faction = "Alliance", note = "The Forlorn Cavern" },
    { name = "Androl Oakhand",    zone = "Darnassus",        x = 60, y = 15, faction = "Alliance", note = "by the water, north side" },
    { name = "Lee Brown",         zone = "Elwynn Forest",    x = 46, y = 62, faction = "Alliance", note = "Crystal Lake, east of Goldshire" },
    { name = "Paxton Ganter",     zone = "Dun Morogh",       x = 53, y = 47, faction = "Alliance", note = "Iceflow Lake, north of Kharanos" },
    { name = "Astaia",            zone = "Teldrassil",       x = 55, y = 94, faction = "Alliance", note = "Rut'theran Village" },
    { name = "Warg Deepwater",    zone = "Westfall",         x = 26, y = 47, faction = "Alliance", note = "Longshore, north of Moonbrook" },
    { name = "Harold Riggs",      zone = "Darkshore",        x = 38, y = 42, faction = "Alliance", note = "Auberdine docks" },
    -- Horde
    { name = "Lumak",             zone = "Orgrimmar",        x = 66, y = 44, faction = "Horde", note = "Valley of Honor pond" },
    { name = "Armand Cromwell",   zone = "Undercity",        x = 81, y = 31, faction = "Horde", note = "Magic Quarter canal" },
    { name = "Kah Mistrunner",    zone = "Thunder Bluff",    x = 57, y = 47, faction = "Horde", note = "the pond on the middle rise" },
    { name = "Lau'Tiki",          zone = "Durotar",          x = 58, y = 43, faction = "Horde", note = "coast east of Razor Hill" },
    { name = "Uthan Stillwater",  zone = "Mulgore",          x = 48, y = 54, faction = "Horde", note = "Bloodhoof Village pond" },
    { name = "Clyde Kellen",      zone = "Tirisfal Glades",  x = 66, y = 57, faction = "Horde", note = "Brightwater Lake, east of Brill" },
    -- Neutral
    { name = "Myizz Luckycatch",  zone = "Stranglethorn Vale", x = 27, y = 77, faction = "Neutral", note = "Booty Bay docks" },
    { name = "Old Man Heming",    zone = "Stranglethorn Vale", x = 27, y = 76, faction = "Neutral", note = "Booty Bay - sells the Expert Fishing book", book = true },
    { name = "Nat Pagle",         zone = "Dustwallow Marsh",   x = 59, y = 60, faction = "Neutral", note = "island south-west of Theramore - Artisan quest", artisan = true },
}

------------------------------------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------------------------------------
local function MyFaction() return UnitFactionGroup("player") or "Neutral" end

local function Usable(t)
    return t.faction == "Neutral" or t.faction == MyFaction()
end

-- Current rank info from the max skill: returns rank table and skill/max
local function RankInfo()
    local skill, _, max = NS.GetFishingSkill()
    if not skill then return nil end
    for _, r in ipairs(NS.RANKS) do
        if max <= r.cap then return r, skill, max end
    end
    return NS.RANKS[#NS.RANKS], skill, max
end

-- Zone name -> uiMapID, resolved at runtime so it works whatever IDs Forever uses
local mapByName
local function MapIDFor(zone)
    if not mapByName then
        mapByName = {}
        local list = C_Map and safe(C_Map.GetMapChildrenInfo, 946, nil, true) -- 946 = Cosmic, all descendants
        for _, info in ipairs(list or {}) do
            if info.name and not mapByName[info.name] then mapByName[info.name] = info.mapID end
        end
    end
    if zone == GetRealZoneText() then
        local here = C_Map and safe(C_Map.GetBestMapForUnit, "player")
        if here then return here end
    end
    return mapByName[zone]
end

local function Waypoint(t)
    local mapID = MapIDFor(t.zone)
    if not mapID then Print("can't resolve a map for %s - head for %s, %s.", t.zone, t.zone, t.note) return end
    if TomTom and TomTom.AddWaypoint then
        safe(TomTom.AddWaypoint, TomTom, mapID, t.x / 100, t.y / 100, { title = t.name .. " (fishing)", persistent = false })
        Print("TomTom waypoint set: %s, %s.", t.name, t.zone)
        return
    end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and C_Map.CanSetUserWaypointOnMap and safe(C_Map.CanSetUserWaypointOnMap, mapID) then
        local point = safe(UiMapPoint.CreateFromCoordinates, mapID, t.x / 100, t.y / 100)
        if point and safe(C_Map.SetUserWaypoint, point) then
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then safe(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
            Print("map pin set: %s, %s (%d, %d). Open the map to see it.", t.name, t.zone, t.x, t.y)
            return
        end
    end
    Print("%s: %s, %s (%d, %d).", t.name, t.zone, t.note, t.x, t.y)
end

-- The trainer you should go to now: rank-specific NPC if the next rank needs one, else nearest usable trainer
local function Recommended()
    local r = RankInfo()
    if not r then return nil end
    if r.next == "Expert" then
        for _, t in ipairs(NS.TRAINERS) do if t.book then return t, r end end
    elseif r.next == "Artisan" then
        for _, t in ipairs(NS.TRAINERS) do if t.artisan then return t, r end end
    elseif r.next == nil then
        return nil, r
    end
    local zone = GetRealZoneText()
    local fallback
    for _, t in ipairs(NS.TRAINERS) do
        if Usable(t) and not t.book and not t.artisan then
            if t.zone == zone then return t, r end
            fallback = fallback or t
        end
    end
    return fallback, r
end

------------------------------------------------------------------------------------------------------------------------
-- Command and dashboard
------------------------------------------------------------------------------------------------------------------------
NS.AddCommand("trainer", function(rest)
    rest = strtrim(rest or "")
    local r, skill, max = RankInfo()
    if r then
        Print("Fishing %d/%d - %s rank.%s", skill, max, r.name,
            r.next and (" Next: " .. r.next .. " at level " .. r.level .. ", " .. r.how .. ".") or " You are at the top rank.")
    end
    if rest == "go" then
        local t = Recommended()
        if t then Waypoint(t) else Print("nothing to learn right now.") end
        return
    end
    Print("Fishing trainers for %s:", MyFaction())
    for _, t in ipairs(NS.TRAINERS) do
        if Usable(t) then Print("  %s - %s (%d, %d), %s", t.name, t.zone, t.x, t.y, t.note) end
    end
    Print("  /fish trainer go - set a waypoint to the one you need now")
end, "[go] fishing trainers and rank requirements")

-- Dashboard: nag when within 5 points of the cap, or already capped
function NS.TrainerLine()
    local r, skill, max = RankInfo()
    if not r or not r.next then return nil end
    if skill < max - 5 then return nil end
    local t = Recommended()
    local level = UnitLevel("player") or 1
    if level < r.level then
        return ("|cffffaa00Capped at %d|r - %s needs level %d"):format(max, r.next, r.level)
    end
    if skill >= max then
        return ("|cffff4444Capped at %d|r - see %s (%s)"):format(max, t and t.name or "a trainer", t and t.zone or "?")
    end
    return ("|cffffaa00%d to cap|r - next: %s, %s"):format(max - skill, t and t.name or "trainer", t and t.zone or "?")
end

-- Guide tab additions
local tab = NS.NewTab("Trainers")
tab:Header("Fishing trainers")
local info = tab:Text("", true, 44)
tab:Refresh(function()
    local r, skill, max = RankInfo()
    if not r then info:SetText("You do not know Fishing yet - any fishing trainer teaches Apprentice.") return end
    local t = Recommended()
    info:SetText(("Fishing %d/%d (%s).\n%s"):format(skill, max, r.name,
        r.next and ("Next rank %s: level %d, %s."):format(r.next, r.level, r.how) or "Top rank reached."))
end)
tab:Button("Waypoint to the trainer I need", function() local t = Recommended() if t then Waypoint(t) else Print("nothing to learn right now.") end end, 220)
tab:Button("List all trainers", function() SlashCmdList.EASYFISH("trainer") end, 140)
