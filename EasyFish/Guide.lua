-- EasyFish Guide: skill-aware zone advice and smart lure choice.

local ADDON, NS = ...
local Print, safe = NS.Print, NS.safe

NS.CopyDefaults(NS.DEFAULTS, {
    smartLure   = true,   -- pick the cheapest lure that reaches junk-free, not always the strongest
    autoLure    = true,   -- apply a lure automatically on the next cast when one is needed
    junkTarget  = 0,      -- accept this much junk % before bothering with a lure (0 = always junk-free)
})

------------------------------------------------------------------------------------------------------------------------
-- Zone math
------------------------------------------------------------------------------------------------------------------------
-- Returns a table describing the current zone: min, junkFree, skill, mod, effective, junkPct (0..100), status
function NS.ZoneReport(zone)
    local min, name = NS.ZoneMinSkill(zone)
    local skill, mod = NS.GetFishingSkill()
    local r = { zone = name, min = min, skill = skill, mod = mod or 0 }
    if not skill then r.status = "noskill" return r end
    r.effective = skill + (mod or 0)
    if not min then r.status = "nodata" return r end
    r.junkFree = min + NS.JUNK_FREE_OFFSET
    if r.effective < min then
        r.status = "toolow"
        r.junkPct = 100
    else
        r.junkPct = math.max(0, math.min(100, (r.junkFree - r.effective) / NS.JUNK_FREE_OFFSET * 100))
        r.status = r.junkPct > 0 and "junk" or "clean"
    end
    return r
end

-- Skill bonus you would need from a lure to reach the junk target in this zone (0 if none needed).
local function NeededBonus(r)
    if not r or not r.junkFree or not r.skill then return 0 end
    local base = r.skill + (r.mod or 0) - NS.CurrentLureBonus()
    local target = r.junkFree - (NS.db.junkTarget or 0) / 100 * NS.JUNK_FREE_OFFSET
    return math.max(0, math.ceil(target - base))
end

-- Bonus of the lure currently on the pole (best guess from enchant ID is unreliable, so we track what we applied).
local appliedBonus = 0
function NS.CurrentLureBonus()
    if NS.LureTimeLeft() > 0 then
        if appliedBonus > 0 then return appliedBonus end
        local _, mod = NS.GetFishingSkill()
        return mod or 0
    end
    appliedBonus = 0
    return 0
end

-- Which lure to use now. Smart mode: weakest lure in bags whose bonus covers the need; otherwise the strongest.
function NS.ChooseLure()
    local db = NS.db
    local available = {}
    for _, lure in ipairs(NS.LURES) do
        if NS.GetItemCount(lure.id) > 0 then available[#available + 1] = lure end
    end
    if #available == 0 then return nil end
    if not db.smartLure then return available[1].id, available[1].bonus end
    local need = NeededBonus(NS.ZoneReport())
    local pick = available[1]
    for i = #available, 1, -1 do -- weakest first
        if available[i].bonus >= need then pick = available[i] break end
    end
    return pick.id, pick.bonus, need
end

-- Human readable one-liner for the status window
local function AdviceLine()
    local r = NS.ZoneReport()
    if r.status == "noskill" then return "Skill: |cff888888learn Fishing first|r" end
    if r.status == "nodata" then return ("Zone: |cff888888%s - no data|r"):format(r.zone or "?") end
    if r.status == "toolow" then
        return ("|cffff4444Too low:|r need %d here, you have %d"):format(r.min, r.effective)
    end
    if r.status == "clean" then
        return ("|cff44ff44Junk-free|r here (%d/%d)"):format(r.effective, r.junkFree)
    end
    local _, bonus, need = NS.ChooseLure()
    if bonus and bonus >= need then
        return ("|cffffaa00~%d%% junk|r - lure +%d fixes it"):format(r.junkPct, bonus)
    end
    return ("|cffffaa00~%d%% junk|r - need +%d more skill"):format(r.junkPct, r.junkFree - r.effective)
end


------------------------------------------------------------------------------------------------------------------------
-- Auto-lure: when a cast is requested and a lure would help, spend this click applying it instead.
------------------------------------------------------------------------------------------------------------------------
NS.OnPreCast(function()
    local db = NS.db
    if not db.autoLure or NS.LureTimeLeft() > 0 then return nil end
    local r = NS.ZoneReport()
    if r.status ~= "junk" and r.status ~= "toolow" and r.status ~= "nodata" then return nil end
    local id, bonus = NS.ChooseLure()
    if not id then return nil end
    appliedBonus = bonus or 0
    Print("Applying %s (+%d). Cast again once it is on.", NS.GetItemInfo(id) or "lure", bonus or 0)
    return ("/use item:%d\n/use 16"):format(id)
end)

-- Remember the bonus when the Lure button is used too
NS.lureButton:HookScript("PreClick", function()
    local _, bonus = NS.ChooseLure()
    appliedBonus = bonus or 0
end)

------------------------------------------------------------------------------------------------------------------------
-- "Where should I fish?"
------------------------------------------------------------------------------------------------------------------------
local function WhereToFish()
    local skill, mod = NS.GetFishingSkill()
    if not skill then Print("Learn Fishing first.") return end
    local eff = skill + (mod or 0)
    local level = UnitLevel("player") or 60
    local list = {}
    for zone, min in pairs(NS.ZONES) do
        local zl = NS.ZONE_LEVELS[zone] or 1
        if eff >= min and zl <= level + 5 then
            local junk = math.max(0, (min + NS.JUNK_FREE_OFFSET - eff) / NS.JUNK_FREE_OFFSET * 100)
            list[#list + 1] = { zone = zone, min = min, junk = junk, level = zl }
        end
    end
    -- Highest minimum you can fish cleanly gives the best fish; sort by min desc, then junk asc
    table.sort(list, function(a, b) if a.min ~= b.min then return a.min > b.min end return a.junk < b.junk end)
    Print("Where to fish at skill %d (level %d):", eff, level)
    local shown = 0
    for _, z in ipairs(list) do
        if shown >= 8 then break end
        local color = z.junk == 0 and "|cff44ff44" or (z.junk < 40 and "|cffffaa00" or "|cffff4444")
        Print("  %s%s|r - min %d, ~%d%% junk, zone level %d+", color, z.zone, z.min, z.junk, z.level)
        shown = shown + 1
    end
    if shown == 0 then Print("  nothing reachable - try your starting zone.") end
    -- Next tier
    local nextMin
    for _, min in pairs(NS.ZONES) do
        if min > eff and (not nextMin or min < nextMin) then nextMin = min end
    end
    if nextMin then Print("  next tier opens at skill %d (%d to go, lures count).", nextMin, nextMin - eff) end
end
NS.AddCommand("where", WhereToFish, "zones you can fish cleanly right now")

------------------------------------------------------------------------------------------------------------------------
-- Settings tab
------------------------------------------------------------------------------------------------------------------------
local tab = NS.NewTab("Guide")
tab:Header("Lures")
tab:Check("Smart lure choice", "smartLure", function() NS.ConfigureLureButton() end,
    "Use the weakest lure in your bags that still makes this zone junk-free, instead of always burning the strongest one.")
tab:Check("Auto-apply lure when casting", "autoLure", nil,
    "If you cast without a lure and this zone would give junk, the click applies a lure first. Cast again to fish.")
tab:Slider("Acceptable junk before using a lure", "junkTarget", 0, 50, 5, "%d%%", function() NS.ConfigureLureButton() end)
tab:Header("Zone guide")
local info = tab:Text("", true, 96)
tab:Refresh(function()
    local r = NS.ZoneReport()
    local lines = {}
    if r.status == "noskill" then
        lines[1] = "You do not know Fishing yet."
    else
        lines[1] = ("Your skill: %d (+%d from lure/gear) = %d"):format(r.skill, r.mod, r.effective)
        if r.status == "nodata" then
            lines[2] = ("No skill data for '%s'. Forever may have changed this zone."):format(r.zone or "?")
        else
            lines[2] = ("%s: minimum %d, junk-free at %d."):format(r.zone, r.min, r.junkFree)
            lines[3] = AdviceLine():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Classic rule: junk chance drops to zero 95 skill above the zone minimum. Lures count toward it."
    info:SetText(table.concat(lines, "\n"))
end)
tab:Button("Where should I fish?", WhereToFish, 160)
