-- EasyFish Rarity: the rare and trophy fish worth watching for where you stand.
-- The list lives in RarityData.lua. "Caught" comes from your all-time catch log.

local ADDON, NS = ...
local Print, safe = NS.Print, NS.safe

NS.CopyDefaults(NS.DEFAULTS, { showRare = true, rareAll = false })

local TIERS = {
    trophy   = { order = 1, label = "Trophy",   color = "|cffff8000" },
    rare     = { order = 2, label = "Rare",     color = "|cff0070dd" },
    uncommon = { order = 3, label = "Uncommon", color = "|cff1eff00" },
}

local byName = {}
for _, fish in ipairs(NS.RARE_FISH) do byName[fish.name] = fish end

local function InZone(fish, zone)
    if fish.zones == "any" then return true end
    for _, z in ipairs(fish.zones or {}) do if z == zone then return true end end
    return false
end

local function ByTier(a, b)
    local ta, tb = TIERS[a.tier].order, TIERS[b.tier].order
    if ta ~= tb then return ta < tb end
    return a.name < b.name
end

-- Fish for a zone, best first. nil zone means every fish.
function NS.RareFishList(zone)
    local list = {}
    for _, fish in ipairs(NS.RARE_FISH) do
        if not zone or InZone(fish, zone) then list[#list + 1] = fish end
    end
    table.sort(list, ByTier)
    return list
end

-- The heading for a catch alert, or nil when this fish isn't special enough to interrupt you
function NS.RareAlert(name)
    local fish = byName[name]
    if fish and fish.tier ~= "uncommon" then return TIERS[fish.tier].label .. " catch" end
end

-- How special a fish is: our list knows catch rarity (a white-quality fish can still be hard to find); anything else
-- goes by the game's item quality. Returns label, r, g, b.
local QUALITY = {
    [0] = { "Poor", 0.62, 0.62, 0.62 }, [1] = { "Common", 1, 1, 1 }, [2] = { "Uncommon", 0.12, 1, 0 },
    [3] = { "Rare", 0, 0.44, 0.87 }, [4] = { "Epic", 0.64, 0.21, 0.93 }, [5] = { "Legendary", 1, 0.5, 0 },
}
local TIER_LOOK = {
    trophy = { "Trophy fish", 1, 0.5, 0 }, rare = { "Rare catch", 0, 0.44, 0.87 }, uncommon = { "Uncommon catch", 0.12, 1, 0 },
}
function NS.FishRarity(name)
    local fish = byName[name]
    if fish then return unpack(TIER_LOOK[fish.tier]) end
    local _, _, quality = NS.GetItemInfo(name)
    return unpack(QUALITY[quality] or QUALITY[1])
end

local function Caught(fish) return NS.db.totals[fish.name] or 0 end

local function Tag(fish) return TIERS[fish.tier].color .. fish.name .. "|r" end

-- Dashboard: named zones only, since "anywhere" fish would sit on every screen, and only fish known to be on Forever
NS.RareHereLine = NS.Memo(function()
    if not NS.db.showRare then return nil end
    local zone, names, extra = GetRealZoneText(), {}, 0
    for _, fish in ipairs(NS.RareFishList(zone)) do
        if fish.zones ~= "any" and not fish.unconfirmed then
            if #names < 2 then names[#names + 1] = Tag(fish) else extra = extra + 1 end
        end
    end
    if #names == 0 then return nil end
    return ("|cffaaaaaaRare here:|r %s%s"):format(table.concat(names, ", "), extra > 0 and (" +" .. extra) or "")
end)

local function Detail(fish)
    local parts = {}
    if fish.where then parts[#parts + 1] = fish.where end
    if fish.chance then parts[#parts + 1] = fish.chance end
    if fish.note then parts[#parts + 1] = fish.note end
    return table.concat(parts, " - ")
end

NS.AddCommand("rare", function(rest)
    local everywhere = strtrim(rest or "") == "all"
    local zone = GetRealZoneText()
    local list = NS.RareFishList(not everywhere and zone or nil)
    Print(everywhere and "Rare and trophy fish:" or ("Rare and trophy fish in %s:"):format(zone or "?"))
    for _, fish in ipairs(list) do
        Print("  %s [%s] x%d caught - %s", Tag(fish), TIERS[fish.tier].label, Caught(fish), Detail(fish))
    end
    if #list == 0 then Print("  none known here") end
end, "[all] rare and trophy fish here (or everywhere)")

------------------------------------------------------------------------------------------------------------------------
-- Tab
------------------------------------------------------------------------------------------------------------------------
local tab = NS.NewTab("Rare")
tab:Header("Rare and trophy fish")
local heading = tab:Text("", true, 16)
local list = tab:List(300)
local function Fill()
    local zone = GetRealZoneText()
    local fishes = NS.RareFishList(not NS.db.rareAll and zone or nil)
    heading:SetText(NS.db.rareAll and "Everywhere" or (zone or "?"))
    local items = {}
    for _, fish in ipairs(fishes) do
        local n = Caught(fish)
        items[#items + 1] = {
            icon = NS.ItemIcon(fish.itemID),
            text = Tag(fish),
            right = n > 0 and ("|cff44ff44Caught x" .. n .. "|r") or (TIERS[fish.tier].color .. TIERS[fish.tier].label .. "|r"),
            sub = Detail(fish),
            tip = fish.why,
        }
    end
    if #items == 0 then items[1] = { text = "|cff888888None known in this zone.|r", sub = "Tick the box below to see them all." } end
    list:Set(items)
end
tab:Refresh(Fill)
tab:Check("Show every zone", "rareAll", Fill)
tab:Check("Show rare fish for this zone on the status window", "showRare", NS.UpdateUI)
