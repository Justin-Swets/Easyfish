-- EasyFish data tables.
--
-- Zone minimum fishing skill, Classic Era values (El's Anglin' / Wowhead Classic). Classic rule of thumb:
-- below the minimum you catch nothing; junk chance falls linearly and reaches zero at minimum + 95.
-- WoW: Forever is Classic+ and may tune these or add zones - unknown zones simply show "no data".
-- Keys are English zone names as returned by GetRealZoneText(); add a translation table if you play localised.

local ADDON, NS = ...

NS.JUNK_FREE_OFFSET = 95

NS.ZONES = {
    -- Starter zones and capitals
    ["Dun Morogh"]            = 1,
    ["Elwynn Forest"]         = 1,
    ["Teldrassil"]            = 1,
    ["Durotar"]               = 1,
    ["Mulgore"]               = 1,
    ["Tirisfal Glades"]       = 1,
    ["Stormwind City"]        = 1,
    ["Ironforge"]             = 1,
    ["Darnassus"]             = 1,
    ["Orgrimmar"]             = 1,
    ["Thunder Bluff"]         = 1,
    ["Undercity"]             = 1,
    -- 55
    ["Darkshore"]             = 55,
    ["Loch Modan"]            = 55,
    ["Silverpine Forest"]     = 55,
    ["Westfall"]              = 55,
    ["The Barrens"]           = 55,
    -- 130
    ["Ashenvale"]             = 130,
    ["Duskwood"]              = 130,
    ["Hillsbrad Foothills"]   = 130,
    ["Redridge Mountains"]    = 130,
    ["Stonetalon Mountains"]  = 130,
    ["Wetlands"]              = 130,
    ["Stranglethorn Vale"]    = 130,
    -- 205
    ["Alterac Mountains"]     = 205,
    ["Arathi Highlands"]      = 205,
    ["Desolace"]              = 205,
    ["Dustwallow Marsh"]      = 205,
    ["Swamp of Sorrows"]      = 205,
    ["Thousand Needles"]      = 205,
    ["Feralas"]               = 205,
    ["Tanaris"]               = 205,
    ["The Hinterlands"]       = 205,
    ["Badlands"]              = 205,
    -- 330
    ["Azshara"]               = 330,
    ["Felwood"]               = 330,
    ["Un'Goro Crater"]        = 330,
    ["Western Plaguelands"]   = 330,
    ["Eastern Plaguelands"]   = 330,
    ["Winterspring"]          = 330,
    ["Burning Steppes"]       = 330,
    ["Blasted Lands"]         = 330,
    ["Silithus"]              = 330,
    ["Moonglade"]             = 330,
    ["Deadwind Pass"]         = 330,
    ["Searing Gorge"]         = 330,
}

-- Zone level bands, so the guide can suggest zones that are survivable at your character level.
NS.ZONE_LEVELS = {
    ["Dun Morogh"] = 1, ["Elwynn Forest"] = 1, ["Teldrassil"] = 1, ["Durotar"] = 1, ["Mulgore"] = 1, ["Tirisfal Glades"] = 1,
    ["Stormwind City"] = 1, ["Ironforge"] = 1, ["Darnassus"] = 1, ["Orgrimmar"] = 1, ["Thunder Bluff"] = 1, ["Undercity"] = 1,
    ["Darkshore"] = 10, ["Loch Modan"] = 10, ["Silverpine Forest"] = 10, ["Westfall"] = 10, ["The Barrens"] = 10,
    ["Ashenvale"] = 18, ["Duskwood"] = 18, ["Hillsbrad Foothills"] = 20, ["Redridge Mountains"] = 15,
    ["Stonetalon Mountains"] = 15, ["Wetlands"] = 20, ["Stranglethorn Vale"] = 30,
    ["Alterac Mountains"] = 30, ["Arathi Highlands"] = 30, ["Desolace"] = 30, ["Dustwallow Marsh"] = 35,
    ["Swamp of Sorrows"] = 35, ["Thousand Needles"] = 25, ["Feralas"] = 40, ["Tanaris"] = 40, ["The Hinterlands"] = 40,
    ["Badlands"] = 35, ["Azshara"] = 45, ["Felwood"] = 48, ["Un'Goro Crater"] = 48, ["Western Plaguelands"] = 51,
    ["Eastern Plaguelands"] = 53, ["Winterspring"] = 53, ["Burning Steppes"] = 50, ["Blasted Lands"] = 45,
    ["Silithus"] = 55, ["Moonglade"] = 1, ["Deadwind Pass"] = 55, ["Searing Gorge"] = 43,
}

-- Lures: itemID -> skill bonus. Ordered list is strongest first.
NS.LURES = {
    { id = 68049, bonus = 150, name = "Heat-Treated Spinning Lure" },
    { id = 46006, bonus = 100, name = "Glow Worm" },
    { id = 34861, bonus = 100, name = "Sharpened Fish Hook" },
    { id = 62673, bonus = 100, name = "Feathered Lure" },
    { id = 6811,  bonus = 100, name = "Aquadynamic Fish Attractor" },
    { id = 6532,  bonus = 75,  name = "Bright Baubles" },
    { id = 6533,  bonus = 75,  name = "Flesh Eating Worm" },
    { id = 7307,  bonus = 50,  name = "Aquadynamic Fish Lens" },
    { id = 6530,  bonus = 50,  name = "Nightcrawlers" },
    { id = 6529,  bonus = 25,  name = "Shiny Bauble" },
}

-- Fish that only bite at certain server hours (Classic). Ranges are [from, to) in 24h, wrapping past midnight.
NS.TIMED_FISH = {
    ["Nightfin Snapper"] = { from = 18, to = 6,  label = "night (18:00-06:00)" },
    ["Sunscale Salmon"]  = { from = 6,  to = 18, label = "day (06:00-18:00)" },
    ["Stonescale Eel"]   = { from = 18, to = 6,  label = "night (18:00-06:00)" },
    ["Darkclaw Lobster"] = { from = 18, to = 6,  label = "night (18:00-06:00)" },
}
-- Loot names carry the "Raw " prefix; look up both spellings
setmetatable(NS.TIMED_FISH, { __index = function(t, k)
    if type(k) == "string" and k:sub(1, 4) == "Raw " then return rawget(t, k:sub(5)) end
end })

-- Grey items that come out of the water. Anything of Poor quality that you have ever fished up is also treated as junk.
NS.JUNK = {
    ["Driftwood"] = true, ["Tangled Fishing Line"] = true, ["Empty Rum Bottle"] = true, ["Sturdy Locked Chest"] = false,
    ["Rusty Old Key"] = true, ["Weathered Treasure Map"] = false, ["Broken Fishing Rod"] = true,
    ["Torn Shoe"] = true, ["Tattered Cloth Sack"] = true, ["Rusted Anchor"] = true,
}

-- Open-water fish by zone skill tier, Classic Era. "fresh" = lakes/rivers, "coast" = ocean shoreline.
-- Each entry: name, optional note (time/season/where). Pools (schools) are not listed - that is what the heatmap is for.
NS.FISH_TIERS = {
    [1] = {
        fresh = { { "Raw Brilliant Smallfish" }, { "Raw Longjaw Mud Snapper" } },
        coast = { { "Raw Slitherskin Mackerel" }, { "Raw Rainbow Fin Albacore" } },
    },
    [55] = {
        fresh = { { "Raw Longjaw Mud Snapper" }, { "Raw Bristle Whisker Catfish" } },
        coast = { { "Raw Rainbow Fin Albacore" }, { "Oily Blackmouth" } },
    },
    [130] = {
        fresh = { { "Raw Bristle Whisker Catfish" }, { "Raw Sagefish" } },
        coast = { { "Raw Rockscale Cod" }, { "Oily Blackmouth" }, { "Firefin Snapper" } },
    },
    [205] = {
        fresh = { { "Raw Mithril Head Trout" }, { "Raw Greater Sagefish" } },
        coast = { { "Raw Spotted Yellowtail" }, { "Raw Glossy Mightfish" }, { "Firefin Snapper" }, { "Oily Blackmouth" } },
    },
    [330] = {
        fresh = { { "Raw Redgill" }, { "Raw Whitescale Salmon" }, { "Raw Nightfin Snapper", "night" }, { "Raw Sunscale Salmon", "day" } },
        coast = { { "Large Raw Mightfish" }, { "Darkclaw Lobster", "night" }, { "Stonescale Eel", "night" },
                  { "Raw Summer Bass", "summer" }, { "Winter Squid", "winter" }, { "Lightning Eel" } },
    },
}

-- Zone-specific extras that the tier table does not cover
NS.ZONE_FISH = {
    ["Loch Modan"]       = { { "Raw Loch Frenzy" } },
    ["The Barrens"]      = { { "Deviate Fish", "oases" } },
    ["Un'Goro Crater"]   = { { "Raw Greater Sagefish", "schools" } },
}

-- Which kinds of water a zone has. Zones not listed are assumed freshwater only.
NS.ZONE_WATER = {
    ["Darkshore"] = "coast", ["Westfall"] = "both", ["Durotar"] = "both", ["Teldrassil"] = "both",
    ["Tirisfal Glades"] = "both", ["Wetlands"] = "both", ["Stranglethorn Vale"] = "both", ["Desolace"] = "both",
    ["Dustwallow Marsh"] = "both", ["Feralas"] = "both", ["Tanaris"] = "both", ["The Hinterlands"] = "both",
    ["Azshara"] = "both", ["Silverpine Forest"] = "both", ["Ashenvale"] = "both", ["Swamp of Sorrows"] = "both",
    ["Blasted Lands"] = "coast", ["Eastern Plaguelands"] = "both", ["Arathi Highlands"] = "both",
    ["Hillsbrad Foothills"] = "both", ["The Barrens"] = "both",
}

-- Minimum skill per fish = the lowest zone tier it appears in (Classic: the water decides, not the fish).
NS.FISH_SKILL = {
    ["Raw Loch Frenzy"] = 55,
    ["Deviate Fish"]    = 55,
}
do
    local tiers = {}
    for min in pairs(NS.FISH_TIERS) do tiers[#tiers + 1] = min end
    table.sort(tiers)
    for _, min in ipairs(tiers) do
        for _, list in pairs(NS.FISH_TIERS[min]) do
            for _, f in ipairs(list) do
                if not NS.FISH_SKILL[f[1]] then NS.FISH_SKILL[f[1]] = min end
            end
        end
    end
end

-- Expected fish for a zone: returns { fresh = {...}, coast = {...}, extra = {...} } or nil when unknown
function NS.ExpectedFish(zone)
    zone = zone or GetRealZoneText()
    local min = NS.ZONES[zone]
    local tier = min and NS.FISH_TIERS[min]
    if not tier then return nil end
    local water = NS.ZONE_WATER[zone] or "fresh"
    return {
        fresh = (water == "fresh" or water == "both") and tier.fresh or nil,
        coast = (water == "coast" or water == "both") and tier.coast or nil,
        extra = NS.ZONE_FISH[zone],
    }
end

-- Chests / trunks fished up from wreckage. Keyword match plus exact names added with /fish chest <name>.
NS.TREASURE_WORDS = { "Trunk", "Chest", "Crate", "Strongbox", "Lockbox", "Coffer", "Cache", "Footlocker" }
function NS.IsTreasure(name)
    if type(name) ~= "string" then return false end
    if NS.db and NS.db.treasureNames and NS.db.treasureNames[name] then return true end
    for _, word in ipairs(NS.TREASURE_WORDS) do
        if name:find(word, 1, true) then return true end
    end
    return false
end

function NS.ZoneMinSkill(zone)
    zone = zone or GetRealZoneText()
    return NS.ZONES[zone], zone
end

function NS.IsTimeActive(spec, hour)
    if spec.from < spec.to then return hour >= spec.from and hour < spec.to end
    return hour >= spec.from or hour < spec.to
end
