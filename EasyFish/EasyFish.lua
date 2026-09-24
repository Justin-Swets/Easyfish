-- EasyFish core - fishing helper for World of Warcraft: Forever (modern 12.x-style API)
--
-- This file owns: saved variables, secure cast/lure buttons, easy cast, bite sound boost, pole swap, auto-loot,
-- the status window, the tabbed settings panel, the minimap button, the event bus used by the other modules.
-- Modules (loaded after this file, see the .toc): Data, Guide, Heatmap, Extras.
--
-- Nothing here automates the actual fishing loop (detecting the bite / clicking the bobber). The Blizzard API does
-- not allow that, and it is against the ToS. Everything is a hardware-click helper or information display.

local ADDON, NS = ...
local EF = CreateFrame("Frame", "EasyFishFrame")
EF:RegisterEvent("ADDON_LOADED")
_G.EasyFish = NS

-- Key binding labels (Bindings.xml)
BINDING_HEADER_EASYFISH_HEADER = "EasyFish"
_G["BINDING_NAME_CLICK EasyFishCastButton:LeftButton"] = "Cast fishing line"
BINDING_NAME_EASYFISH_TOGGLE_POLE = "Swap weapon / fishing pole"
BINDING_NAME_EASYFISH_OPTIONS = "Open EasyFish settings"

------------------------------------------------------------------------------------------------------------------------
-- Settings / saved variables
------------------------------------------------------------------------------------------------------------------------
NS.DEFAULTS = {
    enabled        = true,   -- double right-click to cast
    doubleClick    = 0.40,   -- seconds allowed between the two right-clicks
    clickMax       = 0.25,   -- a right press held longer than this is a camera drag, not a click
    sound          = true,   -- bite boost
    autoLoot       = true,
    lureRemind     = true,
    autoPole       = true,   -- equip a pole automatically when you try to cast without one
    showFrame      = true,
    locked         = false,
    framePos       = nil,
    minimap        = { show = true, angle = 220 },
    spellOverride  = "",     -- custom spell name if auto-detect picks the wrong one
    -- volume levels used while fishing (0..1)
    sfxVolume      = 1.0,
    musicVolume    = 0.0,
    ambienceVolume = 0.0,
    -- catch log
    totals         = {},     -- [itemName] = count
    totalCasts     = 0,
    -- outfit memory for pole swap
    savedMainHand  = nil,
    savedOffHand   = nil,
}

local db
NS.session = { catches = {}, count = 0, casts = 0, started = 0, copper = 0, activeSeconds = 0, lastActivity = nil, chests = 0, value = 0, usedAH = false, chestValue = 0 }
local session = NS.session

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
NS.CopyDefaults = CopyDefaults

-- Fishing time: gaps longer than two minutes between casts/loots are not counted
function NS.Touch()
    local now = GetTime()
    if session.lastActivity then
        session.activeSeconds = (session.activeSeconds or 0) + math.min(now - session.lastActivity, 120)
    end
    session.lastActivity = now
end

------------------------------------------------------------------------------------------------------------------------
-- Loading history
--
-- The Forever beta writes SavedVariables on logout but never reads them back, so every login would start empty.
-- Workaround: tools\Sync-EasyFish.ps1 writes the saved file as a small companion addon, EasyFish_History, which the
-- .toc loads first (OptionalDeps). It lives in its own folder so updating EasyFish never deletes it, and players
-- without the sync simply don't have it. It defines:
--   EasyFishSnapshot       - the full history (same lineage = same continuous history)
--   EasyFishOrphans[id]    - sessions that were saved while history failed to load; merged in here, once each
-- If Blizzard fixes the bug, EasyFishDB loads normally and the snapshot is only used when it is newer.
------------------------------------------------------------------------------------------------------------------------
local function NewLineage()
    return ("%x%04x"):format(time(), math.random(0, 0xffff))
end

-- Adds one session's counts into db. Settings are left alone; positions are weighted by casts.
local function MergeInto(dst, src)
    local function add(t, k, v) t[k] = (t[k] or 0) + (tonumber(v) or 0) end
    local function sub(t, k) t[k] = t[k] or {} return t[k] end

    for name, n in pairs(src.totals or {}) do add(dst.totals, name, n) end
    add(dst, "totalCasts", src.totalCasts)

    for mapID, spots in pairs(src.spots or {}) do
        local dmap = sub(dst.spots, mapID)
        for key, s in pairs(spots) do
            local d = dmap[key]
            if not d then
                dmap[key] = s
            else
                local n1, n2 = d.n or 0, s.n or 0
                if n1 + n2 > 0 and s.x and d.x then
                    d.x = (d.x * n1 + s.x * n2) / (n1 + n2)
                    d.y = (d.y * n1 + s.y * n2) / (n1 + n2)
                end
                for _, f in ipairs({ "n", "casts", "catches", "junk", "seconds", "chests", "pool" }) do
                    if s[f] then add(d, f, s[f]) end
                end
                d.poolCertain = d.poolCertain or s.poolCertain
                for h, c in pairs(s.hours or {}) do add(sub(d, "hours"), h, c) end
                for name, rec in pairs(s.items or {}) do
                    local di = sub(d, "items")[name]
                    if not di then d.items[name] = rec
                    else
                        add(di, "n", rec.n)
                        for h, c in pairs(rec.hours or {}) do add(sub(di, "hours"), h, c) end
                    end
                end
                for _, f in ipairs({ "mats", "poolNames" }) do
                    for name, c in pairs(s[f] or {}) do add(sub(d, f), name, c) end
                end
            end
        end
    end

    for zone, items in pairs(src.mats or {}) do
        local dz = sub(dst.mats, zone)
        for name, rec in pairs(items) do
            local d = dz[name]
            if not d then dz[name] = rec
            else add(d, "n", rec.n) add(d, "chest", rec.chest) d.prof = d.prof or rec.prof end
        end
    end
    for chest, items in pairs(src.chestLoot or {}) do
        local dc = sub(dst.chestLoot, chest)
        for name, c in pairs(items) do add(dc, name, c) end
    end
    for name, rec in pairs(src.prices or {}) do
        local d = dst.prices[name]
        if not d or (rec.t or 0) > (d.t or 0) then dst.prices[name] = rec end
    end
    if (src.lastScan or 0) > (dst.lastScan or 0) then dst.lastScan = src.lastScan end
    for id in pairs(src.mergedOrphans or {}) do dst.mergedOrphans[id] = true end
end

local function InitDB()
    local loaded = type(EasyFishDB) == "table" and next(EasyFishDB) ~= nil
    local snap = type(EasyFishSnapshot) == "table" and EasyFishSnapshot or nil
    NS.loadSource = loaded and "saved" or "none"
    if snap then
        if not loaded then
            EasyFishDB, NS.loadSource = snap, "snapshot"
        elseif snap.lineage and snap.lineage == EasyFishDB.lineage and (snap.saves or 0) > (EasyFishDB.saves or 0) then
            EasyFishDB, NS.loadSource = snap, "snapshot"
        end
    end
    if type(EasyFishDB) ~= "table" then EasyFishDB = {} end
    db = EasyFishDB
    CopyDefaults(db, NS.DEFAULTS)
    NS.db = db
    db.lineage = db.lineage or NewLineage()
    db.saves = db.saves or 0
    db.mergedOrphans = db.mergedOrphans or {}

    NS.mergedCount = 0
    if type(EasyFishOrphans) == "table" then
        for id, orphan in pairs(EasyFishOrphans) do
            if type(orphan) == "table" and id ~= db.lineage and not db.mergedOrphans[id] then
                MergeInto(db, orphan)
                db.mergedOrphans[id] = true
                NS.mergedCount = NS.mergedCount + 1
            end
        end
    end
    EasyFishSnapshot, EasyFishOrphans = nil, nil
end

local function ReportLoad()
    if NS.loadSource == "none" then
        NS.Print("|cffff8800history did not load|r - this is the Forever beta SavedVariables bug. This session is still saved " ..
              "and will be merged back in: run |cffffff00tools\\Sync-EasyFish.ps1|r (or install the background sync) before your next login.")
    elseif NS.mergedCount > 0 then
        NS.Print("history restored, and %d session%s saved while it was missing merged back in.",
            NS.mergedCount, NS.mergedCount == 1 and "" or "s")
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Event bus: modules register with NS.On(event, fn) and NS.OnCatch(fn)
------------------------------------------------------------------------------------------------------------------------
local handlers = {}
function NS.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        if event:match("^UNIT_") then EF:RegisterUnitEvent(event, "player") else EF:RegisterEvent(event) end
    end
    handlers[event][#handlers[event] + 1] = fn
end

local catchHandlers = {}
function NS.OnCatch(fn) catchHandlers[#catchHandlers + 1] = fn end

------------------------------------------------------------------------------------------------------------------------
-- Small helpers (API compat shims: Forever uses the retail-style C_* namespaces)
------------------------------------------------------------------------------------------------------------------------
local function Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff33bbffEasyFish:|r " .. tostring(msg))
end
NS.Print = Print

local function safe(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k end
    return nil
end
NS.safe = safe

function NS.GetItemCount(itemID)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return safe(f, itemID) or 0
end

function NS.GetItemInfoInstant(itemID)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    return safe(f, itemID)
end

function NS.GetItemInfo(item)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return safe(f, item)
end

function NS.EquipItem(itemID)
    local f = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    if InCombatLockdown() then Print("Can't swap gear in combat.") return false end
    safe(f, itemID)
    return true
end

function NS.GetCVar(name)
    local f = (C_CVar and C_CVar.GetCVar) or GetCVar
    return safe(f, name)
end

function NS.SetCVar(name, value)
    local f = (C_CVar and C_CVar.SetCVar) or SetCVar
    safe(f, name, tostring(value))
end

function NS.FormatMoney(copper)
    copper = math.floor(copper or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    if g > 0 then return ("%d|cffffd700g|r %d|cffc7c7cfs|r"):format(g, s) end
    if s > 0 then return ("%d|cffc7c7cfs|r %d|cffeda55fc|r"):format(s, c) end
    return ("%d|cffeda55fc|r"):format(c)
end

local FISHING_POLE_CLASS, FISHING_POLE_SUBCLASS = 2, 20 -- Weapon / Fishing Poles

function NS.IsFishingPole(itemID)
    if not itemID then return false end
    local _, _, _, _, _, classID, subclassID = NS.GetItemInfoInstant(itemID)
    return classID == FISHING_POLE_CLASS and subclassID == FISHING_POLE_SUBCLASS
end

function NS.PoleEquipped()
    return NS.IsFishingPole(GetInventoryItemID("player", 16))
end

-- Iterates every bag slot: fn(bag, slot, itemID)
function NS.ForEachBagItem(fn)
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = safe(C_Container.GetContainerNumSlots, bag) or 0
        for slot = 1, slots do
            local itemID = safe(C_Container.GetContainerItemID, bag, slot)
            if itemID then fn(bag, slot, itemID) end
        end
    end
end

-- Finds the highest item-level fishing pole in bags. Returns itemID or nil.
function NS.FindBestPole()
    local best, bestLevel
    NS.ForEachBagItem(function(_, _, itemID)
        if NS.IsFishingPole(itemID) then
            local level = safe(C_Item and C_Item.GetDetailedItemLevelInfo, itemID) or 0
            if not best or level > bestLevel then best, bestLevel = itemID, level end
        end
    end)
    return best
end

function NS.LureTimeLeft()
    local has, expiration = safe(GetWeaponEnchantInfo)
    if has and type(expiration) == "number" then return expiration / 1000 end
    return 0
end

-- Fishing skill: base, modifier (lure + gear), max. All nil if the profession is unknown.
function NS.GetFishingSkill()
    local ok, _, _, _, fish = pcall(GetProfessions)
    if not ok or not fish then return nil end
    local ok2, _, _, skill, maxSkill, _, _, _, modifier = pcall(GetProfessionInfo, fish)
    if not ok2 then return nil end
    return tonumber(skill) or 0, tonumber(modifier) or 0, tonumber(maxSkill) or 0
end

------------------------------------------------------------------------------------------------------------------------
-- Locate the Fishing spell name. We cast by name through a macro because that is the most robust path across
-- clients; the ID is only used to recognise our own channel in spellcast events.
------------------------------------------------------------------------------------------------------------------------
local fishingSpellID, fishingSpellName = nil, "Fishing"
local KNOWN_FISHING_IDS = { 131474, 7620, 7731, 7732, 18248, 33095, 51294, 88868, 110410 }

local function ResolveFishingSpell()
    fishingSpellID = nil
    if db.spellOverride and db.spellOverride ~= "" then
        fishingSpellName = db.spellOverride
    else
        -- Modern spellbook: GetProfessions() -> prof1, prof2, archaeology, fishing, cooking
        local ok, _, _, _, fish = pcall(GetProfessions)
        if ok and fish then
            local ok2, name = pcall(GetProfessionInfo, fish)
            if ok2 and type(name) == "string" and name ~= "" then fishingSpellName = name end
        end
    end
    for _, id in ipairs(KNOWN_FISHING_IDS) do
        local name = C_Spell and safe(C_Spell.GetSpellName, id)
        if name and name == fishingSpellName then fishingSpellID = id break end
    end
    NS.fishingSpellName = fishingSpellName
end

function NS.IsFishingSpell(spellID)
    if not spellID then return false end
    if fishingSpellID and spellID == fishingSpellID then return true end
    local name = C_Spell and safe(C_Spell.GetSpellName, spellID)
    return name ~= nil and name == fishingSpellName
end

------------------------------------------------------------------------------------------------------------------------
-- Secure buttons (must be clicked by hardware input; we only set their attributes out of combat).
-- Registered for both down and up: the client decides which one acts based on ActionButtonUseKeyDown.
------------------------------------------------------------------------------------------------------------------------
local castButton = CreateFrame("Button", "EasyFishCastButton", UIParent, "SecureActionButtonTemplate")
castButton:RegisterForClicks("AnyDown", "AnyUp")
castButton:SetSize(1, 1)
castButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10) -- off-screen, but must be shown to receive clicks
castButton:SetAlpha(0)
NS.castButton = castButton

local function ConfigureCastButton()
    if InCombatLockdown() then return end
    castButton:SetAttribute("type", "macro")
    castButton:SetAttribute("macrotext", "/cast " .. fishingSpellName)
end
NS.ConfigureCastButton = ConfigureCastButton

-- Modules can claim the next click (e.g. Guide applies a lure first). Return macrotext or nil.
local preClickHooks = {}
function NS.OnPreCast(fn) preClickHooks[#preClickHooks + 1] = fn end

-- button is "EasyCast" when the click came from a double right-click, "LeftButton" from the Cast key binding
castButton:SetScript("PreClick", function(_, button)
    if InCombatLockdown() or not db then return end
    castButton:SetAttribute("type", "macro")
    if button == "EasyCast" then
        -- Double right-click: fish only. Never equips gear, and does nothing if a creature, NPC or object is
        -- under the mouse or you have entered combat since the first click.
        if not NS.EasyCastAllowed() then
            castButton:SetAttribute("type", nil)   -- swallow this click
            return
        end
    elseif not NS.PoleEquipped() and db.autoPole then
        local pole = NS.FindBestPole()
        if pole then
            -- Equip now; the cast this click will fail, the next one will work.
            db.savedMainHand = GetInventoryItemID("player", 16)
            db.savedOffHand  = GetInventoryItemID("player", 17)
            NS.EquipItem(pole)
            Print("Equipped your fishing pole - cast again.")
        else
            Print("No fishing pole equipped or in bags.")
        end
        return
    end
    local macro
    for _, fn in ipairs(preClickHooks) do macro = fn() if macro then break end end
    castButton:SetAttribute("macrotext", macro or ("/cast " .. fishingSpellName))
end)

-- A swallowed click cleared the action; put it back for the next one
castButton:SetScript("PostClick", function()
    if not InCombatLockdown() then castButton:SetAttribute("type", "macro") end
end)

local lureButton = CreateFrame("Button", "EasyFishLureButton", UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
lureButton:RegisterForClicks("AnyDown", "AnyUp")
lureButton:SetSize(56, 20)
lureButton:SetText("Lure")
NS.lureButton = lureButton

local function ConfigureLureButton()
    if InCombatLockdown() then return end
    local lure = NS.ChooseLure and NS.ChooseLure() or nil
    if lure then
        lureButton:SetAttribute("type", "macro")
        lureButton:SetAttribute("macrotext", ("/use item:%d\n/use 16"):format(lure))
        lureButton:Enable()
    else
        lureButton:SetAttribute("type", nil)
        lureButton:Disable()
    end
end
NS.ConfigureLureButton = ConfigureLureButton

------------------------------------------------------------------------------------------------------------------------
-- Easy Cast (double right-click)
--
-- A right press on the world is left completely alone: camera drag, bobber loot, NPC interaction all work.
-- When that press is RELEASED quickly (a click, not a drag) we bind BUTTON2 to the cast button for a short window.
-- A second right-click inside the window is therefore routed to the cast button. Then the binding is removed.
------------------------------------------------------------------------------------------------------------------------
local bindOwner = CreateFrame("Frame")
local armed, armTimer, pressStart = false, nil, nil

local function Disarm()
    armed = false
    if armTimer then armTimer:Cancel() armTimer = nil end
    if not InCombatLockdown() then ClearOverrideBindings(bindOwner) end
end
NS.Disarm = Disarm

local function Arm()
    if InCombatLockdown() then return end
    SetOverrideBindingClick(bindOwner, true, "BUTTON2", "EasyFishCastButton", "EasyCast")
    armed = true
    if armTimer then armTimer:Cancel() end
    armTimer = C_Timer.NewTimer(db.doubleClick or 0.4, Disarm)
end

WorldFrame:HookScript("OnMouseDown", function(_, button)
    if button ~= "RightButton" or not db or not db.enabled then return end
    pressStart = GetTime()
end)

-- True when the cursor is over a world object (bobber, node, NPC): the game shows its tooltip owned by UIParent.
local function OverWorldObject()
    return GameTooltip:IsShown() and GameTooltip:GetOwner() == UIParent
end

-- Double right-click is for fishing only. It never equips gear, and it stays out of the way of everything else a
-- right-click does: attacking, looting, talking to NPCs, and anything during combat.
local function EasyCastAllowed()
    return NS.PoleEquipped()
        and not InCombatLockdown() and not UnitAffectingCombat("player")
        and not UnitExists("mouseover")
        and not OverWorldObject()
        and not NS.fishingNow   -- while the line is out, a right-click is for the bobber
end
NS.EasyCastAllowed = EasyCastAllowed

WorldFrame:HookScript("OnMouseUp", function(_, button)
    if button ~= "RightButton" or not db or not db.enabled or not pressStart then return end
    local held = GetTime() - pressStart
    pressStart = nil
    if armed then
        Disarm() -- this was the second click and has already been delivered to the cast button
    elseif held <= (db.clickMax or 0.25) and EasyCastAllowed() then
        -- Wait a frame so the engine finishes handling this release before the right button is rebound
        C_Timer.After(0, function() if not armed and EasyCastAllowed() then Arm() end end)
    end
end)

------------------------------------------------------------------------------------------------------------------------
-- Bite boost: remember the player's sound CVars while the line is out and restore afterwards
------------------------------------------------------------------------------------------------------------------------
local SOUND_CVARS = {
    "Sound_EnableAllSound", "Sound_EnableSFX", "Sound_EnableMusic", "Sound_EnableAmbience",
    "Sound_MasterVolume", "Sound_SFXVolume", "Sound_MusicVolume", "Sound_AmbienceVolume",
    "Sound_EnableSoundWhenGameIsInBG",
}
local savedSound, boosted = nil, false

local function BoostSound()
    if boosted or not db.sound then return end
    savedSound = {}
    for _, cv in ipairs(SOUND_CVARS) do savedSound[cv] = NS.GetCVar(cv) end
    NS.SetCVar("Sound_EnableAllSound", 1)
    NS.SetCVar("Sound_EnableSFX", 1)
    NS.SetCVar("Sound_EnableSoundWhenGameIsInBG", 1)
    NS.SetCVar("Sound_MasterVolume", 1)
    NS.SetCVar("Sound_SFXVolume", db.sfxVolume)
    NS.SetCVar("Sound_MusicVolume", db.musicVolume)
    NS.SetCVar("Sound_AmbienceVolume", db.ambienceVolume)
    boosted = true
end

local function RestoreSound()
    if not boosted then return end
    for cv, val in pairs(savedSound or {}) do
        if val ~= nil then NS.SetCVar(cv, val) end
    end
    savedSound, boosted = nil, false
end
NS.RestoreSound = RestoreSound

------------------------------------------------------------------------------------------------------------------------
-- Pole swap
------------------------------------------------------------------------------------------------------------------------
function NS.RestoreWeapon(quiet)
    if InCombatLockdown() then return false end
    if not db.savedMainHand then
        if not quiet then Print("No saved weapon to restore - swap it back by hand.") end
        return false
    end
    NS.EquipItem(db.savedMainHand)
    if db.savedOffHand then
        local off = db.savedOffHand
        C_Timer.After(0.5, function() NS.EquipItem(off) end)
    end
    db.savedMainHand, db.savedOffHand = nil, nil
    if not quiet then Print("Weapon restored.") end
    return true
end

local function TogglePole()
    if InCombatLockdown() then Print("Can't swap gear in combat.") return end
    if NS.PoleEquipped() then
        NS.RestoreWeapon()
    else
        local pole = NS.FindBestPole()
        if not pole then Print("No fishing pole in your bags.") return end
        db.savedMainHand = GetInventoryItemID("player", 16)
        db.savedOffHand  = GetInventoryItemID("player", 17)
        NS.EquipItem(pole)
        Print("Fishing pole equipped. Use the Pole button again to restore your weapon.")
    end
end
NS.TogglePole = TogglePole
EasyFish_TogglePole = TogglePole -- for the key binding

------------------------------------------------------------------------------------------------------------------------
-- Catch log
------------------------------------------------------------------------------------------------------------------------
-- Coin slots show up in the loot window as "1 Silver<newline>42 Copper"; they are money, not items.
function NS.IsMoneySlot(i)
    local money = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or LOOT_SLOT_MONEY or 2
    if safe(GetLootSlotType, i) == money then return true end
    local _, name = safe(GetLootSlotInfo, i)
    return type(name) == "string" and name:find("\n", 1, true) ~= nil
end

-- Coins: measured as the change in your money while the loot window is open, so nothing is guessed from text.
local moneyWatch
function NS.WatchMoney(kind)
    moneyWatch = { before = safe(GetMoney) or 0, kind = kind }
end

local function SettleMoney()
    local w = moneyWatch
    moneyWatch = nil
    if not w then return end
    C_Timer.After(0.5, function()
        local delta = (safe(GetMoney) or 0) - w.before
        if delta <= 0 then return end
        session.copper = session.copper + delta
        session.value  = (session.value or 0) + delta
        if w.kind == "chest" then session.chestValue = (session.chestValue or 0) + delta end
        NS.UpdateUI()
    end)
end

local function RecordLoot()
    local n = safe(GetNumLootItems) or 0
    local loot = {}
    for i = 1, n do
        local _, name, quantity, _, quality = safe(GetLootSlotInfo, i)
        if type(name) == "string" and not NS.IsMoneySlot(i) then
            quantity = tonumber(quantity) or 1
            session.catches[name] = (session.catches[name] or 0) + quantity
            session.count = session.count + quantity
            db.totals[name] = (db.totals[name] or 0) + quantity
            loot[#loot + 1] = { name = name, quantity = quantity, quality = tonumber(quality) or 1,
                                link = safe(GetLootSlotLink, i) }
        end
    end
    for _, fn in ipairs(catchHandlers) do safe(fn, loot) end
end

local function ShowStats()
    local function dump(label, tbl)
        local list = {}
        for name, count in pairs(tbl) do list[#list + 1] = { name, count } end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        Print("%s (%d kinds):", label, #list)
        for i = 1, math.min(#list, 15) do Print("  %s x%d", list[i][1], list[i][2]) end
        if #list == 0 then Print("  nothing yet") end
    end
    dump("This session", session.catches)
    dump(("All-time - %d casts"):format(db.totalCasts or 0), db.totals)
end
NS.ShowStats = ShowStats

------------------------------------------------------------------------------------------------------------------------
-- Status window. Modules add lines with NS.AddStatusLine(fn) where fn returns text or nil (hidden).
------------------------------------------------------------------------------------------------------------------------
local ui = CreateFrame("Frame", "EasyFishStatus", UIParent, "BackdropTemplate")
ui:SetSize(308, 96)
ui:SetPoint("CENTER", UIParent, "CENTER", 300, 150)
ui:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
ui:SetBackdropColor(0, 0, 0, 0.75)
ui:SetMovable(true)
ui:EnableMouse(true)
ui:SetClampedToScreen(true)
ui:RegisterForDrag("LeftButton")
ui:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
ui:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    db.framePos = { point, relPoint, x, y }
end)
ui:Hide()
NS.ui = ui

local title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 8, -6)
title:SetText("|cff33bbffEasyFish|r")

local statusLines = {}   -- { fs = FontString, fn = function }
function NS.AddStatusLine(fn)
    local fs = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWidth(292)
    fs:SetWordWrap(true)
    fs:SetNonSpaceWrap(false)
    statusLines[#statusLines + 1] = { fs = fs, fn = fn }
end

lureButton:SetParent(ui)
lureButton:SetPoint("BOTTOMLEFT", 6, 6)

local poleButton = CreateFrame("Button", "EasyFishPoleButton", ui, "UIPanelButtonTemplate")
poleButton:SetSize(56, 20)
poleButton:SetPoint("BOTTOMLEFT", lureButton, "BOTTOMRIGHT", 4, 0)
poleButton:SetText("Pole")
poleButton:SetScript("OnClick", TogglePole)

local statsButton = CreateFrame("Button", "EasyFishStatsButton", ui, "UIPanelButtonTemplate")
statsButton:SetSize(40, 20)
statsButton:SetPoint("BOTTOMLEFT", poleButton, "BOTTOMRIGHT", 4, 0)
statsButton:SetText("Log")
statsButton:SetScript("OnClick", ShowStats)

NS.lureWarned = false

local cfgButton = CreateFrame("Button", "EasyFishCfgButton", ui, "UIPanelButtonTemplate")
cfgButton:SetSize(26, 20)
cfgButton:SetPoint("BOTTOMLEFT", statsButton, "BOTTOMRIGHT", 4, 0)
cfgButton:SetText("...")


local function UpdateUI()
    if not db then return end
    if not db.showFrame then ui:Hide() return end
    ui:Show()
    local y = -22
    if NS.StatusHeader then
        local ok, ny = pcall(NS.StatusHeader, y)
        if ok and ny then y = ny end
    end
    for _, line in ipairs(statusLines) do
        local text = safe(line.fn)
        if text then
            line.fs:SetText(text)
            line.fs:ClearAllPoints()
            line.fs:SetPoint("TOPLEFT", 8, y)
            line.fs:Show()
            y = y - math.max(12, line.fs:GetStringHeight()) - 2
        else
            line.fs:Hide()
        end
    end
    ui:SetHeight(-y + 34 + (NS.extraBottom or 0))
end
NS.UpdateUI = UpdateUI

ui:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t > 1 then self.t = 0 UpdateUI() end
end)

------------------------------------------------------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------------------------------------------------------
local minimapButton = CreateFrame("Button", "EasyFishMinimapButton", Minimap)
minimapButton:SetSize(31, 31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton")
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local mmOverlay = minimapButton:CreateTexture(nil, "OVERLAY")
mmOverlay:SetSize(53, 53)
mmOverlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmOverlay:SetPoint("TOPLEFT")

local mmIcon = minimapButton:CreateTexture(nil, "BACKGROUND")
mmIcon:SetSize(20, 20)
mmIcon:SetTexture("Interface\\Icons\\Trade_Fishing")
mmIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
mmIcon:SetPoint("TOPLEFT", 7, -6)

local function PositionMinimapButton()
    local angle = math.rad(db.minimap.angle or 220)
    local radius = (Minimap:GetWidth() / 2) + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function UpdateMinimapButton()
    if db.minimap.show then minimapButton:Show() else minimapButton:Hide() end
end

local function DragMinimapButton()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
    PositionMinimapButton()
end

minimapButton:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", DragMinimapButton)
end)
minimapButton:SetScript("OnDragStop", function(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil)
end)
minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("EasyFish")
    GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
    GameTooltip:AddLine("Right-click: show/hide status window", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

------------------------------------------------------------------------------------------------------------------------
-- Settings panel (tabbed). Modules create their own tab with NS.NewTab(name).
------------------------------------------------------------------------------------------------------------------------
local options = CreateFrame("Frame", "EasyFishOptions", UIParent, "BackdropTemplate")
options:SetSize(500, 560)
options:SetPoint("CENTER")
options:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
options:SetMovable(true)
options:EnableMouse(true)
options:SetClampedToScreen(true)
options:SetFrameStrata("DIALOG")
options:RegisterForDrag("LeftButton")
options:SetScript("OnDragStart", options.StartMoving)
options:SetScript("OnDragStop", options.StopMovingOrSizing)
options:Hide()
tinsert(UISpecialFrames, "EasyFishOptions") -- Escape closes it
NS.options = options

local optTitle = options:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
optTitle:SetPoint("TOP", 0, -18)
optTitle:SetText("EasyFish Settings")

local closeBtn = CreateFrame("Button", nil, options, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -6, -6)

local hint = options:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("BOTTOM", 0, 18)
hint:SetText("/fish opens this panel. The addon never detects the bite or clicks the bobber for you.")

local tabs = {}
local function SelectTab(index)
    for i, tab in ipairs(tabs) do
        if i == index then
            tab.frame:Show()
            tab.button:Disable()
            tab.button:SetAlpha(1)
            for _, fn in ipairs(tab.refreshers) do safe(fn) end
        else
            tab.frame:Hide()
            tab.button:Enable()
            tab.button:SetAlpha(0.7)
        end
    end
end

local function ShowTip(self)
    if self.tooltipText then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end
end

-- Returns a tab object with helpers: Check, Slider, Header, Button, Edit, Text; all stack downward automatically.
function NS.NewTab(name)
    local frame = CreateFrame("Frame", nil, options)
    frame:SetPoint("TOPLEFT", 16, -96)
    frame:SetPoint("BOTTOMRIGHT", -16, 36)
    frame:Hide()

    local index = #tabs + 1
    local button = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    button:SetSize(84, 22)
    button:SetPoint("TOPLEFT", 16 + ((index - 1) % 5) * 90, -42 - math.floor((index - 1) / 5) * 24)
    button:SetText(name)
    button:SetScript("OnClick", function() SelectTab(index) end)

    local tab = { frame = frame, button = button, refreshers = {}, y = -4 }
    tabs[index] = tab

    function tab:Header(text)
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", 8, self.y - 4)
        fs:SetText(text)
        self.y = self.y - 22
    end

    -- height reserves space for text that is filled in later (by a Refresh function)
    function tab:Text(text, small, height)
        local fs = frame:CreateFontString(nil, "OVERLAY", small and "GameFontHighlightSmall" or "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 12, self.y - 2)
        fs:SetWidth(450)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetText(text)
        if height then fs:SetHeight(height) end
        self.y = self.y - (height or fs:GetStringHeight()) - 8
        return fs
    end

    -- get/set functions so nested settings work; (key) shorthand uses db[key]
    function tab:Check(label, getOrKey, set, tooltip)
        local get = getOrKey
        if type(getOrKey) == "string" then
            local key, onChange = getOrKey, set
            get = function() return db[key] end
            set = function(v) db[key] = v if onChange then onChange(v) end end
        end
        local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 8, self.y)
        cb:SetSize(26, 26)
        cb.Text:SetText(label)
        cb.Text:SetFontObject("GameFontHighlight")
        cb.tooltipText = tooltip
        cb:SetScript("OnClick", function(cbself) set(cbself:GetChecked() and true or false) end)
        cb:SetScript("OnEnter", ShowTip)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.refreshers[#self.refreshers + 1] = function() cb:SetChecked(get()) end
        self.y = self.y - 26
        return cb
    end

    function tab:Slider(label, key, minV, maxV, step, fmt, onChange)
        local s = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", 16, self.y - 16)
        s:SetWidth(420)
        s:SetMinMaxValues(minV, maxV)
        s:SetValueStep(step)
        s:SetObeyStepOnDrag(true)
        s.Low:SetText(fmt:format(minV))
        s.High:SetText(fmt:format(maxV))
        s:SetScript("OnValueChanged", function(sself, value)
            value = math.floor(value / step + 0.5) * step
            db[key] = value
            sself.Text:SetText(label .. ": " .. fmt:format(value))
            if onChange then onChange(value) end
        end)
        self.refreshers[#self.refreshers + 1] = function()
            s:SetValue(db[key])
            s.Text:SetText(label .. ": " .. fmt:format(db[key]))
        end
        self.y = self.y - 50
        return s
    end

    function tab:Button(label, onClick, width)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetPoint("TOPLEFT", 10, self.y - 2)
        b:SetSize(width or 140, 22)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        self.y = self.y - 28
        return b
    end

    function tab:Edit(label, get, set, width)
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", 8, self.y - 4)
        fs:SetText(label)
        local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        box:SetPoint("TOPLEFT", 16, self.y - 22)
        box:SetSize(width or 220, 20)
        box:SetAutoFocus(false)
        box:SetScript("OnEnterPressed", function(bself) set(strtrim(bself:GetText() or "")) bself:ClearFocus() end)
        box:SetScript("OnEscapePressed", function(bself) bself:ClearFocus() end)
        self.refreshers[#self.refreshers + 1] = function() box:SetText(get() or "") end
        self.y = self.y - 50
        return box
    end

    function tab:Refresh(fn) self.refreshers[#self.refreshers + 1] = fn end

    return tab
end

local function ToggleOptions()
    if options:IsShown() then options:Hide() else options:Show() end
end
NS.ToggleOptions = ToggleOptions
EasyFish_ToggleOptions = ToggleOptions -- for the key binding
options:SetScript("OnShow", function()
    local current = 1
    for i, tab in ipairs(tabs) do if tab.frame:IsShown() then current = i end end
    SelectTab(current)
end)
cfgButton:SetScript("OnClick", ToggleOptions)

minimapButton:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        db.showFrame = not db.showFrame
        UpdateUI()
    else
        ToggleOptions()
    end
end)

-- General tab
local general = NS.NewTab("General")
general:Header("Casting")
general:Check("Double right-click to cast", "enabled", Disarm,
    "Two quick right-clicks on the world cast your fishing line - only while a fishing pole is equipped, never over a creature or NPC, and never in combat. It never equips anything. Right-drag to turn the camera still works.\n\nYou can also bind a key under Key Bindings > EasyFish.")
general:Check("Auto-equip fishing pole with the Cast key", "autoPole", nil,
    "If you press the Cast fishing line key without a pole, the best pole in your bags is equipped for you. Double right-click never equips anything.")
general:Slider("Double-click window", "doubleClick", 0.2, 1.0, 0.05, "%.2fs")
general:Header("Fishing")
general:Check("Bite sound boost", "sound", function(v) if not v then RestoreSound() end end,
    "Raises sound effects and mutes music/ambience while your line is out, and keeps sound on when alt-tabbed.")
general:Check("Auto-loot catches", "autoLoot")
general:Check("Remind me when my lure runs out", "lureRemind")
general:Slider("Music while fishing", "musicVolume", 0, 1, 0.1, "%.0f")
general:Header("Display")
general:Check("Show status window", "showFrame", UpdateUI)
general:Check("Lock status window", "locked")
general:Header("Display")
general:Check("Show minimap button",
    function() return db.minimap.show end,
    function(v) db.minimap.show = v UpdateMinimapButton() end)
general:Edit("Fishing spell name (blank = auto-detect)",
    function() return db.spellOverride end,
    function(v) db.spellOverride = v ResolveFishingSpell() ConfigureCastButton() Print("casting with: /cast %s", fishingSpellName) end)
general:Button("Key bindings", function()
    options:Hide()
    if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
        pcall(Settings.OpenToCategory, Settings.KEYBINDINGS_CATEGORY_ID)
    elseif SettingsPanel then
        ShowUIPanel(SettingsPanel)
    elseif KeyBindingFrame_LoadUI then
        KeyBindingFrame_LoadUI() ShowUIPanel(KeyBindingFrame)
    end
end)

-- Also register under Options > AddOns so it is discoverable there
local function RegisterSettingsCategory()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16) t:SetText("EasyFish")
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", 16, -48) b:SetSize(180, 24) b:SetText("Open EasyFish settings")
    b:SetScript("OnClick", function() if SettingsPanel then HideUIPanel(SettingsPanel) end options:Show() end)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "EasyFish")
    if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end

------------------------------------------------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------------------------------------------------
NS.fishingNow = false

EF:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        InitDB()
        C_Timer.After(3, ReportLoad)
        if db.framePos then
            ui:ClearAllPoints()
            ui:SetPoint(db.framePos[1], UIParent, db.framePos[2], db.framePos[3], db.framePos[4])
        end
        PositionMinimapButton()
        UpdateMinimapButton()
        RegisterSettingsCategory()
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_LOGOUT")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("LOOT_OPENED")
        self:RegisterEvent("LOOT_CLOSED")
        self:RegisterEvent("LOOT_BIND_CONFIRM")
        self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        self:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        for _, fn in ipairs(handlers.ADDON_LOADED or {}) do safe(fn) end
        Print("loaded. /fish or click the minimap button for settings.")
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        RestoreSound()
        ResolveFishingSpell()
        ConfigureCastButton()
        ConfigureLureButton()
        if session.started == 0 then session.started = GetTime() end
        UpdateUI()

    elseif event == "PLAYER_LOGOUT" then
        RestoreSound()
        db.saves = (db.saves or 0) + 1   -- lets the sync script tell a newer save of this history from an older one
        db.savedAt = time()

    elseif event == "PLAYER_REGEN_ENABLED" then
        ConfigureCastButton()  -- re-apply anything we could not touch during combat
        ConfigureLureButton()

    elseif event == "BAG_UPDATE_DELAYED" then
        ConfigureLureButton()

    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        local _, _, spellID = ...
        if NS.IsFishingSpell(spellID) then
            NS.fishingNow = true
            NS.Touch()
            session.casts = session.casts + 1
            db.totalCasts = (db.totalCasts or 0) + 1
            BoostSound()
            if db.lureRemind and NS.LureTimeLeft() <= 0 and not NS.lureWarned then
                NS.lureWarned = true
                if NS.ChooseLure and NS.ChooseLure() then
                    Print("No lure on your pole - hit the |cffffff00Lure|r button.")
                else
                    Print("No lure on your pole (and none in your bags).")
                end
            end
            UpdateUI()
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local _, _, spellID = ...
        if NS.fishingNow and (NS.IsFishingSpell(spellID) or event == "UNIT_SPELLCAST_INTERRUPTED") then
            NS.fishingNow = false
            NS.Touch()
            -- Small delay so the splash/loot sound still plays at full volume
            C_Timer.After(1.0, function() if not NS.fishingNow then RestoreSound() end end)
        end

    elseif event == "LOOT_CLOSED" then
        SettleMoney()

    elseif event == "LOOT_OPENED" then
        if safe(IsFishingLoot) then
            NS.WatchMoney("fish")
            NS.Touch()
            RecordLoot()
            UpdateUI()
            if db.autoLoot then
                for i = (safe(GetNumLootItems) or 0), 1, -1 do safe(LootSlot, i) end
            end
        end

    elseif event == "LOOT_BIND_CONFIRM" then
        if db.autoLoot and safe(IsFishingLoot) then
            safe(ConfirmLootSlot, (...))
        end
    end

    for _, fn in ipairs(handlers[event] or {}) do safe(fn, ...) end
end)

------------------------------------------------------------------------------------------------------------------------
-- Slash commands. Modules add their own with NS.AddCommand(name, fn, help).
------------------------------------------------------------------------------------------------------------------------
local function OnOff(v) return v and "|cff44ff44on|r" or "|cffff4444off|r" end
NS.OnOff = OnOff

local commands, commandHelp = {}, {}
function NS.AddCommand(name, fn, help)
    commands[name] = fn
    commandHelp[#commandHelp + 1] = ("  /fish %s - %s"):format(name, help)
end

NS.AddCommand("status", function()
    Print("easy cast %s | bite sound %s | auto-loot %s | lure reminder %s",
        OnOff(db.enabled), OnOff(db.sound), OnOff(db.autoLoot), OnOff(db.lureRemind))
    Print("casting with: /cast %s%s", fishingSpellName, fishingSpellID and (" (#" .. fishingSpellID .. ")") or "")
    local skill, mod, max = NS.GetFishingSkill()
    Print("skill: %s | pole equipped: %s | best pole in bags: %s | lure choice: %s",
        skill and ("%d+%d/%d"):format(skill, mod, max) or "unknown", tostring(NS.PoleEquipped()),
        tostring(NS.FindBestPole() or "none"), tostring(NS.ChooseLure and NS.ChooseLure() or "none"))
end, "what the addon detected (spell, skill, pole, lure)")
NS.AddCommand("toggle", function() db.enabled = not db.enabled Disarm() Print("double right-click cast %s", OnOff(db.enabled)) end, "double right-click cast on/off")
NS.AddCommand("sound", function() db.sound = not db.sound Print("bite sound boost %s", OnOff(db.sound)) if not db.sound then RestoreSound() end end, "bite sound boost on/off")
NS.AddCommand("loot", function() db.autoLoot = not db.autoLoot Print("auto-loot %s", OnOff(db.autoLoot)) end, "auto-loot on/off")
NS.AddCommand("pole", TogglePole, "swap weapon <-> fishing pole")
NS.AddCommand("show", function() db.showFrame = not db.showFrame UpdateUI() end, "status window on/off")
NS.AddCommand("minimap", function() db.minimap.show = not db.minimap.show UpdateMinimapButton() end, "minimap button on/off")
NS.AddCommand("spell", function(rest)
    db.spellOverride = rest or ""
    ResolveFishingSpell() ConfigureCastButton()
    Print("casting with: /cast %s", fishingSpellName)
end, "<name> override the fishing spell name (blank = auto)")
NS.AddCommand("stats", ShowStats, "catch log")
NS.AddCommand("reset", function(rest)
    if rest == "all" then wipe(db.totals) db.totalCasts = 0 Print("all-time log cleared")
    else
        wipe(session.catches) session.count, session.casts, session.copper = 0, 0, 0
        session.activeSeconds, session.lastActivity, session.chests, session.value, session.usedAH = 0, nil, 0, 0, false
        session.chestValue = 0
        Print("session log cleared")
    end
    UpdateUI()
end, "[all] clear the session (or all-time) catch log")

SLASH_EASYFISH1 = "/fish"
SLASH_EASYFISH2 = "/easyfish"
SlashCmdList.EASYFISH = function(input)
    input = strtrim(input or "")
    local cmd, rest = input:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "options" or cmd == "config" then
        ToggleOptions()
    elseif commands[cmd] then
        commands[cmd](rest)
    else
        Print("commands:")
        Print("  /fish - open settings")
        for _, line in ipairs(commandHelp) do Print(line) end
    end
end
