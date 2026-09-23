-- EasyFish Materials: fishing as a source of profession reagents.
--
-- * Classifies everything you fish up, and everything that comes out of a chest/trunk you open, by profession.
-- * Records it per zone and per heatmap spot, so "/fish find Linen Cloth" answers "where did I get that?"
-- * Tracks the professions you know (or any you tick in settings, e.g. for an alt) and calls out matching drops.
-- * Dashboard row: top materials for your professions from where you are standing.

local ADDON, NS = ...
local Print, safe = NS.Print, NS.safe

NS.CopyDefaults(NS.DEFAULTS, {
    matAlert   = true,   -- chat line when a tracked material drops
    matLoud    = false,  -- raid-warning style alert too
    profs      = {},     -- [professionName] = true/false (nil = not decided yet -> follows what you know)
    mats       = {},     -- [zone][itemName] = { n = count, chest = count from chests, prof = "Alchemy/Cooking" }
    chestLoot  = {},     -- [chestName][itemName] = count
})

------------------------------------------------------------------------------------------------------------------------
-- Classification
------------------------------------------------------------------------------------------------------------------------
-- Item class 7 = Trade Goods. Subclass -> professions that use it.
local SUBCLASS_PROFS = {
    [1]  = { "Engineering" },                     -- Parts
    [2]  = { "Engineering" },                     -- Explosives
    [3]  = { "Engineering" },                     -- Devices
    [4]  = { "Jewelcrafting" },
    [5]  = { "Tailoring", "First Aid" },          -- Cloth
    [6]  = { "Leatherworking" },                  -- Leather
    [7]  = { "Blacksmithing", "Engineering" },    -- Metal & Stone
    [8]  = { "Cooking" },
    [9]  = { "Alchemy" },                         -- Herb
    [10] = { "Alchemy", "Tailoring", "Blacksmithing" }, -- Elemental
    [11] = { "Alchemy" },                         -- Other
    [12] = { "Enchanting" },
    [16] = { "Inscription" },
}

-- Fish with a known profession use beyond cooking (Classic)
local FISH_PROFS = {
    ["Oily Blackmouth"] = { "Alchemy", "Cooking" },
    ["Firefin Snapper"] = { "Alchemy", "Cooking" },
    ["Stonescale Eel"]  = { "Alchemy" },
    ["Deviate Fish"]    = { "Cooking", "Alchemy" },
}

NS.ALL_PROFS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring",
                 "Cooking", "First Aid", "Jewelcrafting", "Inscription" }

-- Returns a list of profession names an item feeds, or nil
function NS.MatProfessions(item)
    local name = NS.GetItemInfo(item) or (type(item) == "string" and item:match("%[(.-)%]")) or item
    if type(name) == "string" then
        if FISH_PROFS[name] then return FISH_PROFS[name] end
        if name:sub(1, 4) == "Raw " then return { "Cooking" } end
    end
    local _, _, _, _, _, classID, subclassID = NS.GetItemInfoInstant(item)
    if classID == 7 then return SUBCLASS_PROFS[subclassID] end
    if classID == 5 then return { "Cooking" } end -- consumable food/drink (already cooked fish etc.)
    return nil
end

------------------------------------------------------------------------------------------------------------------------
-- Which professions matter to this character
------------------------------------------------------------------------------------------------------------------------
local known = {}
local function ScanKnown()
    wipe(known)
    local ok, p1, p2, arch, fish, cook = pcall(GetProfessions)
    if not ok then return end
    for _, idx in ipairs({ p1, p2, arch, fish, cook }) do
        if idx then
            local ok2, name = pcall(GetProfessionInfo, idx)
            if ok2 and name then known[name] = true end
        end
    end
    -- First Aid is not returned by GetProfessions on every client; treat cloth as interesting if you know Tailoring anyway
    for _, prof in ipairs(NS.ALL_PROFS) do
        if NS.db.profs[prof] == nil and known[prof] then NS.db.profs[prof] = true end
    end
end
NS.On("PLAYER_ENTERING_WORLD", ScanKnown)

-- Earlier versions recorded coin slots ("1 Silver\n42 Copper") as chest items; drop them.
NS.On("PLAYER_ENTERING_WORLD", function()
    for _, items in pairs(NS.db.chestLoot or {}) do
        for name in pairs(items) do
            if name:find("\n", 1, true) then items[name] = nil end
        end
    end
end)
NS.On("SKILL_LINES_CHANGED", ScanKnown)

local function Tracked(prof) return NS.db.profs[prof] == true end

-- First tracked profession an item is useful for, or nil
local function TrackedProf(item)
    local profs = NS.MatProfessions(item)
    if not profs then return nil end
    for _, p in ipairs(profs) do if Tracked(p) then return p end end
    return nil
end

------------------------------------------------------------------------------------------------------------------------
-- Recording
------------------------------------------------------------------------------------------------------------------------
local function Record(name, quantity, fromChest, prof)
    local zone = GetRealZoneText() or "?"
    local z = NS.db.mats[zone]
    if not z then z = {} NS.db.mats[zone] = z end
    local rec = z[name]
    if not rec then rec = { n = 0, chest = 0 } z[name] = rec end
    rec.n = rec.n + quantity
    if fromChest then rec.chest = rec.chest + quantity end
    if prof then rec.prof = prof end
    -- Per spot, so pins can say what a spot yields
    local spot = NS.CurrentSpot and NS.CurrentSpot()
    if spot then
        spot.mats = spot.mats or {}
        spot.mats[name] = (spot.mats[name] or 0) + quantity
    end
end

local function Announce(prof, name, quantity, fromChest)
    if not NS.db.matAlert then return end
    local text = ("|cff88ff88%s:|r %s x%d%s"):format(prof, name, quantity, fromChest and " (from chest)" or "")
    Print(text)
    if NS.db.matLoud and RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
    end
end

-- Fishing loot
NS.OnCatch(function(loot)
    for _, item in ipairs(loot) do
        local prof = TrackedProf(item.link or item.name)
        local anyProf = NS.MatProfessions(item.link or item.name)
        if anyProf then Record(item.name, item.quantity, false, prof or anyProf[1]) end
        if prof and not NS.IsTreasure(item.name) then Announce(prof, item.name, item.quantity, false) end
    end
end)

-- Chest loot: the Blizzard UI opens a container through C_Container.UseContainerItem; remember which one,
-- then the next non-fishing loot window whose source is an item is that chest's contents.
local lastOpened, lastOpenedAt = nil, 0
if C_Container and C_Container.UseContainerItem and hooksecurefunc then
    hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
        local itemID = safe(C_Container.GetContainerItemID, bag, slot)
        local name = itemID and NS.GetItemInfo(itemID)
        if name and NS.IsTreasure(name) then lastOpened, lastOpenedAt = name, GetTime() end
    end)
end

NS.On("LOOT_OPENED", function()
    if safe(IsFishingLoot) then return end
    local guid = safe(GetLootSourceInfo, 1)
    if type(guid) ~= "string" or not guid:find("^Item%-") then return end
    local chest = (GetTime() - lastOpenedAt < 5) and lastOpened or nil
    if not chest then return end -- some other container (lockbox from a mob, etc.)
    local bucket = NS.db.chestLoot[chest]
    if not bucket then bucket = {} NS.db.chestLoot[chest] = bucket end
    NS.WatchMoney("chest")   -- coins inside are counted from the change in your money
    NS.session.chestsOpened = (NS.session.chestsOpened or 0) + 1
    local before = NS.session.chestValue or 0
    C_Timer.After(3, function()
        local worth = (NS.session.chestValue or 0) - before
        if worth > 0 then Print("%s was worth %s.", chest, NS.FormatMoney(worth)) end
    end)
    local n = safe(GetNumLootItems) or 0
    for i = 1, n do
        local _, name, quantity = safe(GetLootSlotInfo, i)
        local link = safe(GetLootSlotLink, i)
        if type(name) == "string" and not NS.IsMoneySlot(i) then
            quantity = tonumber(quantity) or 1
            bucket[name] = (bucket[name] or 0) + quantity
            NS.AddLootValue(link or name, quantity, "chest")
            local prof = TrackedProf(link or name)
            local anyProf = NS.MatProfessions(link or name)
            if anyProf then Record(name, quantity, true, prof or anyProf[1]) end
            if prof then Announce(prof, name, quantity, true) end
            if NS.db.wantedAlert and NS.db.wanted[name] then Print("|cffffff00Wanted:|r %s x%d (from %s)", name, quantity, chest) end
        end
    end
    lastOpened = nil
end)

------------------------------------------------------------------------------------------------------------------------
-- Reports
------------------------------------------------------------------------------------------------------------------------
local function SortedMats(zoneFilter, profFilter)
    local totals = {}
    for zone, items in pairs(NS.db.mats) do
        if not zoneFilter or zone == zoneFilter then
            for name, rec in pairs(items) do
                if not profFilter or rec.prof == profFilter or (TrackedProf(name) ~= nil and profFilter == "tracked") then
                    local t = totals[name]
                    if not t then t = { name = name, n = 0, chest = 0, prof = rec.prof, zones = {} } totals[name] = t end
                    t.n = t.n + rec.n
                    t.chest = t.chest + rec.chest
                    t.zones[zone] = (t.zones[zone] or 0) + rec.n
                end
            end
        end
    end
    local list = {}
    for _, t in pairs(totals) do list[#list + 1] = t end
    table.sort(list, function(a, b) return a.n > b.n end)
    return list
end

local function ReportMats(rest)
    rest = strtrim(rest or "")
    local zone = GetRealZoneText()
    local list = SortedMats(rest == "all" and nil or zone, "tracked")
    Print("Materials for your professions %s:", rest == "all" and "(everywhere)" or ("in " .. zone))
    for i = 1, math.min(#list, 12) do
        local m = list[i]
        Print("  %s x%d |cffaaaaaa(%s%s)|r", m.name, m.n, m.prof or "?",
            m.chest > 0 and (", " .. m.chest .. " from chests") or "")
    end
    if #list == 0 then Print("  nothing yet - fish, open chests, and it fills in. /fish mats all for every zone.") end
end
NS.AddCommand("mats", ReportMats, "[all] materials for your professions from here (or everywhere)")

NS.AddCommand("find", function(rest)
    rest = strtrim(rest or "")
    if rest == "" then Print("usage: /fish find <item name>") return end
    local lower = rest:lower()
    local hits = {}
    for zone, items in pairs(NS.db.mats) do
        for name, rec in pairs(items) do
            if name:lower():find(lower, 1, true) then
                hits[#hits + 1] = { zone = zone, name = name, n = rec.n, chest = rec.chest }
            end
        end
    end
    -- chests that contained it
    local chests = {}
    for chest, items in pairs(NS.db.chestLoot) do
        for name, n in pairs(items) do
            if name:lower():find(lower, 1, true) then chests[#chests + 1] = { chest = chest, n = n } end
        end
    end
    table.sort(hits, function(a, b) return a.n > b.n end)
    table.sort(chests, function(a, b) return a.n > b.n end)
    if #hits == 0 and #chests == 0 then Print("never seen '%s' from fishing or chests.", rest) return end
    Print("Where you got '%s':", rest)
    for i = 1, math.min(#hits, 8) do
        local h = hits[i]
        Print("  %s - %s x%d%s", h.zone, h.name, h.n, h.chest > 0 and (" (" .. h.chest .. " from chests)") or "")
    end
    for i = 1, math.min(#chests, 5) do Print("  inside %s: x%d", chests[i].chest, chests[i].n) end
    -- best spots for it
    local spots = {}
    for _, map in pairs(NS.db.spots) do
        for _, spot in pairs(map) do
            if spot.mats then
                for name, n in pairs(spot.mats) do
                    if name:lower():find(lower, 1, true) then spots[#spots + 1] = { spot = spot, n = n } end
                end
            end
        end
    end
    table.sort(spots, function(a, b) return a.n > b.n end)
    for i = 1, math.min(#spots, 3) do
        local s = spots[i].spot
        Print("  spot: %s / %s x%d (%d casts)", s.zone or "?", s.sub ~= "" and s.sub or "-", spots[i].n, s.casts)
    end
end, "<item> where you have fished up or opened that item")

NS.AddCommand("chests", function()
    local list = {}
    for chest, items in pairs(NS.db.chestLoot) do
        local total, top, topN = 0, nil, 0
        for name, n in pairs(items) do total = total + n if n > topN then top, topN = name, n end end
        list[#list + 1] = { chest = chest, total = total, top = top, topN = topN }
    end
    table.sort(list, function(a, b) return a.total > b.total end)
    Print("Chest contents recorded:")
    for _, c in ipairs(list) do Print("  %s - %d items, mostly %s x%d", c.chest, c.total, c.top or "?", c.topN) end
    if #list == 0 then Print("  open a fished-up chest and its contents get recorded.") end
end, "what your fished-up chests have contained")

------------------------------------------------------------------------------------------------------------------------
-- Dashboard row: top materials here for your professions
------------------------------------------------------------------------------------------------------------------------
function NS.MatsHereLine()
    local list = SortedMats(GetRealZoneText(), "tracked")
    if #list == 0 then return nil end
    local out = {}
    for i = 1, math.min(#list, 3) do
        out[#out + 1] = ("%s x%d"):format(list[i].name:gsub("^Raw ", ""), list[i].n)
    end
    return "|cff88ff88Mats here:|r " .. table.concat(out, ", ")
end

------------------------------------------------------------------------------------------------------------------------
-- Heatmap pin tooltip: what a spot yields for you
------------------------------------------------------------------------------------------------------------------------
function NS.SpotMatsLines(spot)
    if not spot.mats then return nil end
    local list = {}
    for name, n in pairs(spot.mats) do
        local prof = TrackedProf(name)
        if prof then list[#list + 1] = { name = name, n = n, prof = prof } end
    end
    table.sort(list, function(a, b) return a.n > b.n end)
    return list
end

------------------------------------------------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------------------------------------------------
local tab = NS.NewTab("Mats")
tab:Header("Professions to track")
tab:Text("Ticked professions get call-outs when a reagent for them comes out of the water or a chest. Your own professions are ticked automatically; tick others to farm for an alt.", true)
for _, prof in ipairs(NS.ALL_PROFS) do
    tab:Check(prof, function() return NS.db.profs[prof] == true end, function(v) NS.db.profs[prof] = v NS.UpdateUI() end)
end
tab:Header("Alerts")
tab:Check("Chat line when a tracked material drops", "matAlert")
tab:Check("Also flash it on screen", "matLoud")
tab:Button("Materials here", function() ReportMats("") end, 130)
tab:Button("Chest contents", function() SlashCmdList.EASYFISH("chests") end, 130)
