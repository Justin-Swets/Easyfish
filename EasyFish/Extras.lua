-- EasyFish Extras: cast timer bar, wanted list + quest awareness, junk selling, danger swap, gold/hour,
-- keyboard fishing via Blizzard's soft-target interact.

local ADDON, NS = ...
local Print, safe = NS.Print, NS.safe

NS.CopyDefaults(NS.DEFAULTS, {
    castBar      = true,
    wantedAlert  = true,
    wanted       = {},     -- [itemName] = true (manual list)
    treasureNames = {},    -- exact chest/trunk names added with /fish chest <name>
    chestAlert   = true,
    sellJunk     = true,
    dangerSwap   = true,
    keyboard     = false,  -- soft-target interact
    savedSoft    = nil,    -- CVars before we changed them
})

------------------------------------------------------------------------------------------------------------------------
-- Cast timer bar: shows how long the current cast has left before the bobber sinks
------------------------------------------------------------------------------------------------------------------------
local bar = CreateFrame("StatusBar", "EasyFishCastBar", NS.ui, "BackdropTemplate")
bar:SetSize(292, 10)
bar:SetPoint("BOTTOMLEFT", NS.ui, "BOTTOMLEFT", 7, 30)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetStatusBarColor(0.2, 0.6, 1)
bar:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
bar:SetBackdropColor(0, 0, 0, 0.6)
bar:Hide()
NS.extraBottom = 14 -- status window leaves room for the bar
bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
bar.text:SetPoint("CENTER")

local castEnd, castStart
bar:SetScript("OnUpdate", function(self)
    if not castEnd then self:Hide() return end
    local now = GetTime()
    local left = castEnd - now
    if left <= 0 then castEnd = nil self:Hide() return end
    self:SetValue(left)
    self.text:SetText(("%.0fs"):format(left))
    if left < 4 then self:SetStatusBarColor(1, 0.4, 0.2) else self:SetStatusBarColor(0.2, 0.6, 1) end
end)

NS.On("UNIT_SPELLCAST_CHANNEL_START", function(_, _, spellID)
    if not NS.db.castBar or not NS.IsFishingSpell(spellID) then return end
    local _, _, _, startMS, endMS = safe(UnitChannelInfo, "player")
    if not endMS then return end
    castStart, castEnd = startMS / 1000, endMS / 1000
    bar:SetMinMaxValues(0, castEnd - castStart)
    bar:Show()
end)
NS.On("UNIT_SPELLCAST_CHANNEL_STOP", function() castEnd = nil bar:Hide() end)
NS.On("UNIT_SPELLCAST_INTERRUPTED", function() castEnd = nil bar:Hide() end)

------------------------------------------------------------------------------------------------------------------------
-- Wanted list: quest objectives that need fish, plus a manual list. Alerts when you catch one.
------------------------------------------------------------------------------------------------------------------------
local questWanted = {}   -- [itemName] = { have, need, quest }

local function ScanQuests()
    wipe(questWanted)
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
    local n = safe(C_QuestLog.GetNumQuestLogEntries) or 0
    for i = 1, n do
        local info = safe(C_QuestLog.GetInfo, i)
        if info and not info.isHeader and info.questID then
            local objectives = safe(C_QuestLog.GetQuestObjectives, info.questID)
            for _, obj in ipairs(objectives or {}) do
                if obj.type == "item" and type(obj.text) == "string" and not obj.finished then
                    local name = obj.text:match("^(.-):%s*%d+/%d+") or obj.text:match("^%d+/%d+%s+(.+)$")
                    if name then
                        questWanted[name] = { have = obj.numFulfilled or 0, need = obj.numRequired or 0, quest = info.title }
                    end
                end
            end
        end
    end
end

-- Only fish are listed by /fish want; the quest log is full of tusks and gems
local FISHY = { "Fish", "Snapper", "Salmon", "Eel", "Squid", "Bass", "Trout", "Catfish", "Mackerel", "Albacore",
                "Cod", "Lobster", "Sagefish", "Mightfish", "Yellowtail", "Blackmouth", "Frenzy", "Smallfish", "Redgill", "Clam" }
local function IsFishName(name)
    if NS.FISH_SKILL[name] or NS.TIMED_FISH[name] or NS.db.totals[name] then return true end
    if name:sub(1, 4) == "Raw " then return true end
    for _, word in ipairs(FISHY) do if name:find(word, 1, true) then return true end end
    return false
end

local scanPending = false
NS.On("QUEST_LOG_UPDATE", function()
    if scanPending then return end
    scanPending = true
    C_Timer.After(1, function() scanPending = false ScanQuests() end)
end)
NS.On("PLAYER_ENTERING_WORLD", ScanQuests)

local function Alert(text)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
    end
    if SOUNDKIT and SOUNDKIT.RAID_WARNING then safe(PlaySound, SOUNDKIT.RAID_WARNING) end
    Print(text)
end

NS.OnCatch(function(loot)
    for _, item in ipairs(loot) do
        if NS.IsTreasure(item.name) then
            NS.session.chests = (NS.session.chests or 0) + item.quantity
            if NS.db.chestAlert then
                Alert(("|cffffd700%s!|r  %d this session"):format(item.link or item.name, NS.session.chests))
                if SOUNDKIT and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST then safe(PlaySound, SOUNDKIT.UI_LEGENDARY_LOOT_TOAST) end
            end
        end
    end
    if not NS.db.wantedAlert then return end
    for _, item in ipairs(loot) do
        local q = questWanted[item.name]
        if NS.IsTreasure(item.name) then
            -- already announced above
        elseif q then
            Alert(("%s - %d/%d for %s"):format(item.name, math.min(q.need, q.have + item.quantity), q.need, q.quest))
        elseif NS.db.wanted[item.name] then
            Alert(("Wanted: %s x%d"):format(item.name, item.quantity))
        elseif item.quality and item.quality >= 3 then
            Alert(("Rare catch: %s"):format(item.link or item.name))
        end
    end
end)


NS.AddCommand("want", function(rest)
    rest = strtrim(rest or "")
    if rest == "" then
        local names = {}
        for name in pairs(NS.db.wanted) do names[#names + 1] = name end
        for name, q in pairs(questWanted) do
            if IsFishName(name) then names[#names + 1] = ("%s (%d/%d, %s)"):format(name, q.have, q.need, q.quest) end
        end
        table.sort(names)
        Print("wanted: %s", #names > 0 and table.concat(names, ", ") or "nothing")
        return
    end
    if NS.db.wanted[rest] then NS.db.wanted[rest] = nil Print("no longer wanted: %s", rest)
    else NS.db.wanted[rest] = true Print("wanted: %s", rest) end
end, "[fish name] list or toggle a wanted fish (alerts when caught)")

NS.AddCommand("chest", function(rest)
    rest = strtrim(rest or "")
    if rest == "" then
        local names = {}
        for name in pairs(NS.db.treasureNames) do names[#names + 1] = name end
        table.sort(names)
        Print("chest names: keywords %s%s", table.concat(NS.TREASURE_WORDS, ", "),
            #names > 0 and ("; exact: " .. table.concat(names, ", ")) or "")
        return
    end
    if NS.db.treasureNames[rest] then NS.db.treasureNames[rest] = nil Print("no longer counted as a chest: %s", rest)
    else NS.db.treasureNames[rest] = true Print("counted as a chest: %s", rest) end
end, "[item name] list or toggle an exact item name counted as a chest")

------------------------------------------------------------------------------------------------------------------------
-- Junk selling: sells Poor-quality items you have ever fished up when you open a vendor
------------------------------------------------------------------------------------------------------------------------
NS.On("MERCHANT_SHOW", function()
    if not NS.db.sellJunk then return end
    local sold, copper = 0, 0
    NS.ForEachBagItem(function(bag, slot, itemID)
        local info = safe(C_Container.GetContainerItemInfo, bag, slot)
        if not info then return end
        local name = info.itemName or NS.GetItemInfo(itemID)
        local poor = info.quality == 0 and not info.hasNoValue
        if name and poor and (NS.db.totals[name] or NS.JUNK[name]) then
            local _, _, _, _, _, _, _, _, _, _, price = NS.GetItemInfo(itemID)
            copper = copper + (price or 0) * (info.stackCount or 1)
            sold = sold + (info.stackCount or 1)
            safe(C_Container.UseContainerItem, bag, slot)
        end
    end)
    if sold > 0 then Print("sold %d fishing junk for %s", sold, NS.FormatMoney(copper)) end
end)

------------------------------------------------------------------------------------------------------------------------
-- Danger swap: put your weapon back the moment you target something hostile (before combat locks gear)
------------------------------------------------------------------------------------------------------------------------
NS.On("PLAYER_TARGET_CHANGED", function()
    if not NS.db.dangerSwap or InCombatLockdown() or not NS.PoleEquipped() then return end
    if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
        and not safe(UnitIsTrivial, "target") then
        if NS.RestoreWeapon(true) then Print("Hostile target - weapon restored. Use the Pole button to fish again.") end
    end
end)



------------------------------------------------------------------------------------------------------------------------
-- Keyboard fishing: Blizzard's soft-target interact lets a bound key "click" the bobber. Purely a game setting.
------------------------------------------------------------------------------------------------------------------------
local SOFT_CVARS = { "SoftTargetInteract", "SoftTargetInteractArc", "SoftTargetInteractRange",
                     "SoftTargetIconInteract", "SoftTargetIconGameObject" }

local function ApplyKeyboard(enable)
    if enable then
        if not NS.db.savedSoft then
            NS.db.savedSoft = {}
            for _, cv in ipairs(SOFT_CVARS) do NS.db.savedSoft[cv] = NS.GetCVar(cv) end
        end
        NS.SetCVar("SoftTargetInteract", 3)       -- always soft-target interactables
        NS.SetCVar("SoftTargetInteractArc", 2)    -- 360 degrees
        NS.SetCVar("SoftTargetInteractRange", 30) -- bobber lands up to ~25 yards out
        NS.SetCVar("SoftTargetIconInteract", 1)
        NS.SetCVar("SoftTargetIconGameObject", 1)
        local key = GetBindingKey and GetBindingKey("INTERACTTARGET")
        if key then
            Print("Keyboard fishing on: cast, then press |cffffff00%s|r (Interact With Target) when the bobber splashes.", key)
        else
            Print("Keyboard fishing on - now bind 'Interact With Target' under Key Bindings > Targeting.")
        end
    elseif NS.db.savedSoft then
        for cv, val in pairs(NS.db.savedSoft) do if val ~= nil then NS.SetCVar(cv, val) end end
        NS.db.savedSoft = nil
        Print("Keyboard fishing off - soft-target settings restored.")
    end
end

NS.On("PLAYER_ENTERING_WORLD", function() if NS.db.keyboard then ApplyKeyboard(true) end end)
NS.AddCommand("keyboard", function() NS.db.keyboard = not NS.db.keyboard ApplyKeyboard(NS.db.keyboard) end,
    "soft-target interact so a key can grab the bobber")

------------------------------------------------------------------------------------------------------------------------
-- Settings tab
------------------------------------------------------------------------------------------------------------------------
local tab = NS.NewTab("Extras")
tab:Header("While fishing")
tab:Check("Cast timer bar", "castBar", nil, "Counts down the time left on your cast so you recast promptly.")
tab:Check("Alert and count chests / trunks", "chestAlert", nil,
    "Anything with Trunk, Chest, Crate, Strongbox, Lockbox, Coffer, Cache or Footlocker in the name. Add exact names with /fish chest <name>.")
tab:Check("Alert on quest, wanted and rare catches", "wantedAlert", nil,
    "Reads your quest log for fish objectives. Add your own with /fish want <name>.")
tab:Check("Swap weapon back when you target an enemy", "dangerSwap", nil,
    "Gear can't change in combat, so this happens the instant you target something hostile, before it hits you.")
tab:Header("Vendors")
tab:Check("Sell fishing junk automatically", "sellJunk", nil, "Grey items you have fished up are sold when you open any vendor.")
tab:Header("Keyboard fishing")
tab:Text("Uses Blizzard's own soft-target system: after a cast, the bobber becomes your interact target and the 'Interact With Target' key grabs it. Bind that key under Key Bindings > Targeting. Test on Forever - if the client ignores it, nothing breaks.", true)
tab:Check("Enable soft-target interact for the bobber", "keyboard", ApplyKeyboard)
