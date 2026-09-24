-- A small simulated WoW API, enough to load EasyFish outside the game.
--
-- Anything not defined here falls back to a "dummy": callable, indexable, arithmetic-safe, and it records the
-- global name so tests can list every WoW API the addon touched that the stub doesn't know.
-- Getter-style methods on dummies (Get*/Is*/Has*/Can*) return 0 / false so layout maths keeps working.

local unknownGlobals = {}
STUB_UNKNOWN = unknownGlobals

-- One shared dummy (plus two shared getters) so the stub itself allocates nothing per call; memory measured in the
-- tests is then EasyFish's own.
local mt = {}
local DUMMY = setmetatable({}, mt)
local function dummy() return DUMMY end
local function getZero() return 0 end
local function getFalse() return false end
mt.__index = function(_, k)
    if type(k) == "string" then
        if k:match("^Get") then return getZero end
        if k:match("^Is") or k:match("^Has") or k:match("^Can") then return getFalse end
    end
    return DUMMY
end
mt.__call = function() return DUMMY end
mt.__newindex = function() end   -- writes to the shared dummy are dropped
mt.__add = function() return 0 end; mt.__sub = mt.__add; mt.__mul = mt.__add; mt.__div = mt.__add
mt.__unm = function() return 0 end
mt.__concat = function() return "" end
mt.__lt = function() return false end; mt.__le = mt.__lt
setmetatable(_G, { __index = function(_, k) unknownGlobals[k] = true return dummy() end })

-- World state the tests can change
S = { pole = true, mouseover = false, combat = false, t = 1000, zone = "Stranglethorn Vale", mapID = 1434,
      x = 0.3, y = 0.3, facing = 0, skill = 180, modifier = 0, maxSkill = 225, lures = { [6532] = 5 },
      armedWith = nil, equipped = {}, queue = {} }

-- Frames answer WoW's methods (Capitalised) with dummies, but the addon's own fields (self.t, self.spot, ...) start
-- out nil like on a real frame.
local frameMt = {}
for k, v in pairs(mt) do frameMt[k] = v end
frameMt.__newindex = nil   -- frames keep what the addon stores on them
frameMt.__index = function(t, k)
    if type(k) == "string" and k:match("^%u") then return mt.__index(t, k) end
    return nil
end

frames, STUB_FRAMES = {}, {}
local function Frame(name)
    local f = setmetatable({ scripts = {}, hooks = {}, attrs = {}, shown = true, name = name }, frameMt)
    table.insert(STUB_FRAMES, f)
    rawset(f, "SetScript", function(self, k, fn) self.scripts[k] = fn end)
    rawset(f, "HookScript", function(self, k, fn) self.hooks[k] = self.hooks[k] or {}; table.insert(self.hooks[k], fn) end)
    rawset(f, "SetAttribute", function(self, k, v) self.attrs[k] = v end)
    rawset(f, "GetAttribute", function(self, k) return self.attrs[k] end)
    rawset(f, "Show", function(self) self.shown = true end)
    rawset(f, "Hide", function(self) self.shown = false end)
    rawset(f, "IsShown", function(self) return self.shown end)
    if name then frames[name] = f end
    return f
end
CreateFrame = function(_, name) return Frame(name) end
WorldFrame, UIParent, Minimap = Frame("WorldFrame"), Frame("UIParent"), Frame("Minimap")
rawset(Minimap, "GetWidth", function() return 140 end)
rawset(Minimap, "GetZoom", function() return 0 end)
GameTooltip = Frame("GameTooltip"); GameTooltip.shown = false

InCombatLockdown = function() return S.combat end
UnitAffectingCombat = function() return S.combat end
UnitExists = function(u) return u == "mouseover" and S.mouseover end
UnitLevel = function() return 40 end
UnitFactionGroup = function() return "Horde" end
GetTime = function() return S.t end
GetGameTime = function() return 20, 0 end
GetPlayerFacing = function() return S.facing end
GetRealZoneText = function() return S.zone end
GetSubZoneText = function() return "The Savage Coast" end
GetMinimapShape = function() return "ROUND" end
C_Timer = { After = function(_, fn) table.insert(S.queue, fn) end,
            NewTimer = function() return { Cancel = function() end } end }
SetOverrideBindingClick = function(_, _, _, _, mouse) S.armedWith = mouse end
ClearOverrideBindings = function() S.armedWith = nil end
GetInventoryItemID = function(_, slot) if slot == 16 and S.pole then return 101 end return nil end
GetWeaponEnchantInfo = function() return false end
GetProfessions = function() return nil, nil, nil, 5, nil end
GetProfessionInfo = function(i) if i == 5 then return "Fishing", 0, S.skill, S.maxSkill, 1, 0, 356, S.modifier end end

-- Items: a small catalogue; anything else is a generic trade good worth 1s
ITEMS = {
    [101] = { "Strong Fishing Pole", 2, 20, 0 },
    [6532] = { "Bright Baubles", 7, 11, 25 },
}
local function itemRec(item)
    if type(item) == "number" then return ITEMS[item] and item, ITEMS[item] end
    for id, rec in pairs(ITEMS) do if rec[1] == item then return id, rec end end
    if type(item) == "string" then return 900, { item:match("%[(.-)%]") or item, 7, 8, 100 } end
end
local function info(item)
    local id, rec = itemRec(item)
    if not rec then return nil end
    return rec[1], "link", 1, 1, 1, "Trade Goods", "Meat", 20, "", 134400, rec[4], rec[2], rec[3]
end
local function instant(item)
    local id, rec = itemRec(item)
    if not rec then return nil end
    return id, "Type", "Sub", "", 134400, rec[2], rec[3]
end
C_Item = {
    GetItemInfo = info, GetItemInfoInstant = instant,
    GetItemCount = function(id) return S.lures[id] or 0 end,
    EquipItemByName = function(id) table.insert(S.equipped, id) end,
    GetDetailedItemLevelInfo = function() return 10 end,
    GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id][1] end,
}
GetItemInfo, GetItemInfoInstant = info, instant
C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
                GetContainerItemID = function(bag, slot) if bag == 0 and slot == 1 then return 101 end end,
                GetContainerItemInfo = function() return nil end }
C_Spell = { GetSpellName = function(id) if id == 7620 or id == 131474 then return "Fishing" end end }
C_CVar = { GetCVar = function() return "0" end, SetCVar = function() end }
GetCVar, SetCVar = C_CVar.GetCVar, C_CVar.SetCVar

C_Map = {
    GetBestMapForUnit = function() return S.mapID end,
    GetPlayerMapPosition = function() return setmetatable({}, { __index = { GetXY = function() return S.x, S.y end } }) end,
    GetMapWorldSize = function() return 3000, 2000 end,
    GetMapChildrenInfo = function() return {} end,
}
C_QuestLog = { GetNumQuestLogEntries = function() return 0 end }

-- Loot window: S.loot = { { name = "...", quantity = 1, quality = 1 }, ... }; S.fishingLoot says whether it's a catch
S.loot, S.fishingLoot = {}, true
IsFishingLoot = function() return S.fishingLoot end
GetNumLootItems = function() return #S.loot end
GetLootSlotInfo = function(i) local l = S.loot[i] if l then return 134400, l.name, l.quantity or 1, nil, l.quality or 1 end end
GetLootSlotLink = function() return nil end
GetLootSlotType = function() return 1 end
GetLootSourceInfo = function() return "Creature-0" end
LootSlot, ConfirmLootSlot = function() end, function() end
UnitChannelInfo = function() return nil end
GetMoney = function() return 0 end
IsSpellKnown = function() return true end
GetBindingKey = function() return nil end            -- nothing bound
Auctionator, TSM_API = false, false                   -- optional addons not installed
C_AuctionHouse = { ReplicateItems = function() end, GetNumReplicateItems = function() return 0 end }

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
tinsert, tremove = table.insert, table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
time, date = os.time, os.date
UISpecialFrames, SlashCmdList, NUM_BAG_SLOTS = {}, {}, 4
MapCanvasPinMixin, MapCanvasDataProviderMixin = {}, {}
CreateFromMixins = function(...) local t = {} for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end return t end
EasyFishDB, EasyFishSnapshot, EasyFishOrphans = false, false, false   -- "not loaded" (nil would hit the catch-all)

function flushTimers() local q = S.queue; S.queue = {}; for _, fn in ipairs(q) do fn() end end
function fire(ev, ...) frames.EasyFishFrame.scripts.OnEvent(frames.EasyFishFrame, ev, ...) end
