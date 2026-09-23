-- EasyFish status window layout: a small dashboard instead of a list of lines.
--
--   Stranglethorn Vale              Skill 180 +75
--   ~47% junk - lure +75 fixes it
--   ------------------------------------------
--   12g 40s / hr                    1h 12m fishing
--   84 fish / 97 casts (87%)        session 9g 12s
--   ------------------------------------------
--   TOP FISH HERE
--   [i] Oily Blackmouth    x31  37%   6s 78c ah
--   Firefin Snapper        x22  26%   8s 18c ea
--   Spotted Yellowtail      x9  11%   4s 44c ea
--   ------------------------------------------
--   Pole ok   Lure 8:12
--   (module lines: quest progress, timed fish)
--   [cast bar]  [Lure] [Pole] [Log] [...]

local ADDON, NS = ...
local safe = NS.safe
local ui = NS.ui
local W = 292  -- inner width

NS.CopyDefaults(NS.DEFAULTS, { showExpected = false })

local function FS(font, justify)
    local fs = ui:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Row(font)
    return { left = FS(font, "LEFT"), right = FS(font, "RIGHT") }
end

local function Rule()
    local t = ui:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 1, 1, 0.12)
    t:SetHeight(1)
    return t
end

local zoneRow   = Row("GameFontNormalSmall")
local advice    = FS("GameFontHighlightSmall")
local trainer   = FS("GameFontHighlightSmall")
local poolLine  = FS("GameFontHighlightSmall")
local rule1     = Rule()
local goldRow   = Row("GameFontNormal")
local catchRow  = Row("GameFontHighlightSmall")
local chestRow  = Row("GameFontHighlightSmall")
local rule2     = Rule()
local topHeader = FS("GameFontNormalSmall")
local fishRows  = {}
for i = 1, 3 do
    local icon = ui:CreateTexture(nil, "ARTWORK")
    icon:SetSize(12, 12)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    fishRows[i] = { icon = icon, name = FS("GameFontHighlightSmall", "LEFT"), count = FS("GameFontHighlightSmall", "RIGHT"),
                    value = FS("GameFontHighlightSmall", "RIGHT") }
end
local matsLine  = FS("GameFontHighlightSmall")
matsLine:SetWordWrap(true)
matsLine:SetWidth(W)
local expected  = FS("GameFontHighlightSmall")
expected:SetWordWrap(true)
expected:SetWidth(W)
local rule3     = Rule()
local gearRow   = Row("GameFontHighlightSmall")

local function Place(obj, y, x, width)
    obj:ClearAllPoints()
    obj:SetPoint("TOPLEFT", ui, "TOPLEFT", 8 + (x or 0), y)
    if width then obj:SetWidth(width) end
    obj:Show()
    return y
end

local function PlaceRow(row, y, height)
    Place(row.left, y, 0, W * 0.6)
    Place(row.right, y, W * 0.4, W * 0.4)
    return y - (height or 13)
end

local function PlaceRule(rule, y)
    rule:ClearAllPoints()
    rule:SetPoint("TOPLEFT", ui, "TOPLEFT", 8, y - 2)
    rule:SetWidth(W)
    rule:Show()
    return y - 7
end

local function Clock(seconds)
    seconds = math.floor(seconds or 0)
    if seconds >= 3600 then return ("%dh %02dm"):format(seconds / 3600, (seconds % 3600) / 60) end
    return ("%dm"):format(seconds / 60)
end

local function Short(name) return (name:gsub("^Raw ", "")) end

-- Top fish where you stand: this map's heatmap data, falling back to the whole session
local function TopFish()
    local totals, source = {}, "here"
    local mapID = C_Map and safe(C_Map.GetBestMapForUnit, "player")
    local spots = mapID and NS.db.spots and NS.db.spots[mapID]
    if spots then
        for _, spot in pairs(spots) do
            for name, rec in pairs(spot.items) do totals[name] = (totals[name] or 0) + rec.n end
        end
    end
    if not next(totals) then
        source = "session"
        for name, n in pairs(NS.session.catches) do
            if not NS.IsJunk({ name = name, quality = 1 }) and not NS.JUNK[name] then totals[name] = n end
        end
    end
    local list, sum = {}, 0
    for name, n in pairs(totals) do list[#list + 1] = { name = name, n = n } sum = sum + n end
    table.sort(list, function(a, b) return a.n > b.n end)
    return list, sum, source
end

local function ExpectedLine()
    local fish = NS.ExpectedFish()
    if not fish then return nil end
    local skill, mod = NS.GetFishingSkill()
    local eff = skill and (skill + (mod or 0)) or 0
    local seen, list = {}, {}
    for _, group in ipairs({ fish.fresh or {}, fish.coast or {}, fish.extra or {} }) do
        for _, f in ipairs(group) do
            if not seen[f[1]] then
                seen[f[1]] = true
                list[#list + 1] = f[1]
            end
        end
    end
    table.sort(list, function(a, b) return (NS.FISH_SKILL[a] or 0) < (NS.FISH_SKILL[b] or 0) end)
    local out = {}
    for _, name in ipairs(list) do
        local req = NS.FISH_SKILL[name] or 0
        out[#out + 1] = Short(name) .. (eff >= req and " |cff44ff44" or " |cffff4444") .. req .. "|r"
    end
    return "|cff88ccffExpected:|r " .. table.concat(out, ", ")
end

-- Called by the core layout; draws the fixed block starting at y and returns the next free y.
function NS.StatusHeader(y)
    local db, session = NS.db, NS.session

    -- Zone + skill
    local r = NS.ZoneReport()
    zoneRow.left:SetText(r.zone or GetRealZoneText() or "")
    if r.skill then
        zoneRow.right:SetText(("Skill %d%s"):format(r.skill, r.mod > 0 and (" |cff44ff44+" .. r.mod .. "|r") or ""))
    else
        zoneRow.right:SetText("")
    end
    y = PlaceRow(zoneRow, y, 13)

    local adv
    if r.status == "clean" then adv = ("|cff44ff44Junk-free|r (needs %d)"):format(r.junkFree)
    elseif r.status == "junk" then
        local _, bonus, need = NS.ChooseLure()
        if NS.LureTimeLeft() > 0 then
            adv = ("|cffffaa00~%d%% junk|r with lure - need %d skill"):format(r.junkPct, r.junkFree)
        elseif bonus and bonus >= (need or 0) then
            adv = ("|cffffaa00~%d%% junk|r - lure +%d fixes it"):format(r.junkPct, bonus)
        else
            adv = ("|cffffaa00~%d%% junk|r - need %d skill"):format(r.junkPct, r.junkFree)
        end
    elseif r.status == "toolow" then adv = ("|cffff4444Too low|r - needs %d here"):format(r.min)
    elseif r.status == "nodata" then adv = "|cff888888No skill data for this zone|r"
    else adv = "|cff888888Learn Fishing to see zone advice|r" end
    advice:SetText(adv)
    y = Place(advice, y, 0, W) - 13
    local tl = NS.TrainerLine and NS.TrainerLine()
    if tl then
        trainer:SetText(tl)
        y = Place(trainer, y, 0, W) - 13
    else trainer:Hide() end
    local pl = NS.PoolLine and NS.PoolLine()
    if pl then
        poolLine:SetText(pl)
        y = Place(poolLine, y, 0, W) - 13
    else poolLine:Hide() end
    y = PlaceRule(rule1, y)

    -- Money and rate
    local active = math.max(session.activeSeconds or 0, 1)
    local total = (NS.db.useAH and session.value or session.copper) or 0
    local perHour = active >= 60 and (total / active * 3600) or 0
    goldRow.left:SetText(perHour > 0 and (NS.FormatMoney(perHour) .. (session.usedAH and NS.db.useAH and " |cffaaaaaa/ hr AH|r" or " |cffaaaaaa/ hr|r")) or "|cff888888-- / hr|r")
    goldRow.right:SetText(("|cffaaaaaa%s fishing|r"):format(Clock(session.activeSeconds)))
    y = PlaceRow(goldRow, y, 15)
    local pct = session.casts > 0 and math.floor(session.count / session.casts * 100 + 0.5) or 0
    catchRow.left:SetText(("%d fish / %d casts |cffaaaaaa(%d%%)|r"):format(session.count, session.casts, pct))
    catchRow.right:SetText(total > 0 and ("|cffaaaaaasession|r " .. NS.FormatMoney(total)) or "")
    y = PlaceRow(catchRow, y, 13)
    local here = NS.ChestsHere and NS.ChestsHere() or 0
    if (session.chests or 0) > 0 or here > 0 then
        local worth = session.chestValue or 0
        chestRow.left:SetText(("|cffffd700Chests|r %d%s"):format(session.chests or 0,
            worth > 0 and ("  |cffaaaaaa(" .. NS.FormatMoney(worth) .. " inside)|r") or ""))
        chestRow.right:SetText(here > 0 and ("|cffaaaaaa%d in this zone|r"):format(here) or "")
        y = PlaceRow(chestRow, y, 13)
    else
        chestRow.left:Hide() chestRow.right:Hide()
    end
    y = PlaceRule(rule2, y)

    -- Top fish
    local list, sum, source = TopFish()
    topHeader:SetText(source == "here" and "TOP FISH HERE" or (#list > 0 and "TOP FISH THIS SESSION" or "TOP FISH HERE"))
    y = Place(topHeader, y, 0, W) - 13
    for i = 1, 3 do
        local row, it = fishRows[i], list[i]
        if it then
            local req = NS.FISH_SKILL[it.name]
            row.name:SetText(Short(it.name) .. (req and (" |cff777777" .. req .. "|r") or ""))
            row.count:SetText(("x%d |cffaaaaaa%d%%|r"):format(it.n, sum > 0 and it.n / sum * 100 or 0))
            local v, src = NS.PriceOf(it.name)
            row.value:SetText(v > 0 and (NS.FormatMoney(v) .. (src == "ah" and " |cff777777ah|r" or " |cff777777v|r")) or "")
            local _, _, _, _, tex = NS.GetItemInfoInstant(it.name)
            if tex then row.icon:SetTexture(tex) Place(row.icon, y, 0) else row.icon:Hide() end
            Place(row.name, y, tex and 15 or 0, W * 0.55 - (tex and 15 or 0))
            Place(row.count, y, W * 0.55, W * 0.17)
            Place(row.value, y, W * 0.72, W * 0.28)
            y = y - 13
        else
            row.name:Hide() row.count:Hide() row.value:Hide() row.icon:Hide()
            if i == 1 then
                row.name:SetText("|cff888888nothing caught here yet|r")
                Place(row.name, y, 0, W)
                y = y - 13
            end
        end
    end
    local mats = NS.MatsHereLine and NS.MatsHereLine()
    if mats then
        matsLine:SetText(mats)
        Place(matsLine, y, 0, W)
        y = y - math.max(12, matsLine:GetStringHeight()) - 1
    else matsLine:Hide() end
    if db.showExpected then
        local text = ExpectedLine()
        if text then
            expected:SetText(text)
            Place(expected, y, 0, W)
            y = y - math.max(12, expected:GetStringHeight()) - 1
        else expected:Hide() end
    else expected:Hide() end
    y = PlaceRule(rule3, y)

    -- Gear
    gearRow.left:SetText(NS.PoleEquipped() and "Pole |cff44ff44ok|r" or "Pole |cffff4444missing|r")
    local left = NS.LureTimeLeft()
    if left > 0 then
        NS.lureWarned = false
        gearRow.right:SetText(("Lure |cff44ff44%d:%02d|r"):format(left / 60, left % 60))
    else
        local have = NS.ChooseLure and NS.ChooseLure()
        gearRow.right:SetText(have and "Lure |cffffaa00none on|r" or "Lure |cff888888none|r")
    end
    y = PlaceRow(gearRow, y, 13)
    return y
end

-- Settings: General tab already exists; add the toggle there via the options API
local tab = NS.NewTab("Window")
tab:Header("Status window")
tab:Check("Show status window", "showFrame", NS.UpdateUI)
tab:Check("Lock status window", "locked")
tab:Check("Also list every expected fish for the zone", "showExpected", NS.UpdateUI,
    "Adds a line with the Classic tier fish for this zone and the skill each needs. Top 3 comes from what you actually catch.")
tab:Text("Gold/hr counts only time spent fishing (gaps over 2 minutes are ignored). Values use auction prices when known (see the Prices tab) - 'ah' after a price means auction, 'v' means vendor.", true)
