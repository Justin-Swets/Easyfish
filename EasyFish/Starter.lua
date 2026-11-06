-- EasyFish Starter guide: where a new fisher goes first, and the quickest way from 1 to 300.
-- The steps live in StarterData.lua. Your current step follows your fishing skill, so it never needs ticking off.

local ADDON, NS = ...
local Print, safe = NS.Print, NS.safe

NS.CopyDefaults(NS.DEFAULTS, { starterHinted = false })

local function Route()
    return NS.STARTER.route[UnitFactionGroup("player") or ""] or NS.STARTER.route.Alliance
end

-- The step for your skill; nil once you are past the last one
function NS.StarterStep()
    local skill = NS.GetFishingSkill() or 0
    for i, step in ipairs(Route()) do
        if skill < step.to then return step, i end
    end
end

local function PoleVendor() return NS.NearestNPC(NS.STARTER.poleVendors) end

local function HasPole() return NS.PoleEquipped() or NS.FindBestPole() ~= nil end

-- The route's first stop is one faction's starter zone; any starter zone does the same job
local function StayHere(step)
    return step.from == 1 and NS.ZONES[GetRealZoneText()] == 1
end

local function GoToStep(step)
    NS.Waypoint({ name = step.spot or step.zone, zone = step.zone, x = step.x, y = step.y, note = step.spot or "" })
end

-- What to do next, in order of what's stopping you
local function NextAction()
    local skill = NS.GetFishingSkill()
    if not skill then return "Learn Fishing from any fishing trainer. Use /fish trainer go for a waypoint." end
    if not HasPole() then
        local vendor = PoleVendor()
        return ("Buy a Fishing Pole%s."):format(vendor and (" from " .. vendor.name .. ", " .. vendor.zone) or "")
    end
    local step = NS.StarterStep()
    if not step then return "You've finished the route. Fish wherever pays best." end
    if StayHere(step) then return ("Skill %d: fish right here until %d. Any water in a starter zone works."):format(skill, step.to) end
    local text = ("Skill %d: fish in %s until %d. %s"):format(skill, step.zone, step.to, step.why or "")
    if step.level and (UnitLevel("player") or 1) < step.level then
        text = text .. (" |cffffaa00Dangerous below level %d.|r"):format(step.level)
    end
    if step.todo then text = text .. "\n|cffffd100To do:|r " .. step.todo end
    return text
end

local function Go()
    if NS.GetFishingSkill() and not HasPole() then
        local vendor = PoleVendor()
        if vendor then NS.Waypoint(vendor) return end
    end
    local step = NS.GetFishingSkill() and NS.StarterStep()
    if step and StayHere(step) then Print("You're in the right place: any water here will do.")
    elseif step then GoToStep(step)
    else SlashCmdList.EASYFISH("trainer go") end
end

local tab = NS.NewTab("Start")

NS.AddCommand("start", function(rest)
    if strtrim(rest or "") == "go" then Go() return end
    NS.OpenTab(tab)
end, "[go] starter guide; go sets a waypoint to your next stop")

-- A single nudge for someone who has never cast; settled once they have seen it
NS.On("PLAYER_ENTERING_WORLD", function()
    if NS.db.starterHinted then return end
    NS.db.starterHinted = true
    if (NS.db.totalCasts or 0) == 0 then Print("New to fishing? |cffffff00/fish start|r shows you where to begin.") end
end)

tab:Header("Your next step")
local nextText = tab:Text("", true, 56)
tab:Button("Set a waypoint", Go, 140)
tab:Header("The route")
local list = tab:List(246)
tab:Refresh(function()
    nextText:SetText(NextAction())
    local _, current = NS.StarterStep()
    local items = {}
    for i, step in ipairs(Route()) do
        local color = "|cff888888"   -- done
        if i == current then color = "|cff44ff44" elseif current and i > current then color = "|cffffffff" end
        items[#items + 1] = {
            text = ("%s%d-%d  %s|r"):format(color, step.from, step.to, step.zone),
            right = (i == current) and "|cff44ff44You are here|r" or nil,
            sub = ("%s%s"):format(step.spot or "", step.level and (" - level " .. step.level .. "+") or ""),
            tip = step.why,
            onClick = function() GoToStep(step) end,
        }
    end
    items[#items + 1] = { header = "The basics" }
    local faction = UnitFactionGroup("player")
    for _, basic in ipairs(NS.STARTER.basics) do
        if not basic.faction or basic.faction == faction then
            items[#items + 1] = { text = basic.title, sub = basic.text, tip = basic.text }
        end
    end
    list:Set(items)
end)
