-- EasyFish Heatmap: learns YOUR fishing spots.
--
-- Every cast and every catch is recorded with map position and server hour. Spots are grid cells (~2% of the map)
-- so the data stays small. The result is drawn as pins on the world map and the minimap, coloured by how good the
-- spot has been for you: catches per hour, junk rate, and which fish come out of it at which times of day.
-- No bundled database - it is built from your own sessions, so it is right for your server.

local ADDON, NS = ...
local Print, safe = NS.Print, NS.safe

NS.CopyDefaults(NS.DEFAULTS, {
    heatmap      = true,   -- record spots
    worldPins    = true,
    minimapPins  = true,
    pinMinCasts  = 3,      -- do not show a spot until it has this many casts
    spots        = {},     -- [mapID] = { [cellKey] = spot }
})

local CELL = 50 -- cells per map axis (2%)

------------------------------------------------------------------------------------------------------------------------
-- Recording
------------------------------------------------------------------------------------------------------------------------
local function PlayerPos()
    local mapID = C_Map and safe(C_Map.GetBestMapForUnit, "player")
    if not mapID then return nil end
    local pos = safe(C_Map.GetPlayerMapPosition, mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or not y or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

local function ServerHour()
    local h = safe(GetGameTime)
    return tonumber(h) or tonumber(date("%H")) or 0
end

local function GetSpot(create)
    local mapID, x, y = PlayerPos()
    if not mapID then return nil end
    local key = ("%d:%d"):format(math.floor(x * CELL), math.floor(y * CELL))
    local map = NS.db.spots[mapID]
    if not map then
        if not create then return nil end
        map = {} NS.db.spots[mapID] = map
    end
    local spot = map[key]
    if not spot and create then
        spot = { x = x, y = y, n = 0, casts = 0, catches = 0, junk = 0, items = {}, hours = {}, seconds = 0,
                 zone = GetRealZoneText(), sub = GetSubZoneText() }
        map[key] = spot
    end
    return spot, mapID, key
end

local currentSpot, castStart
-- The spot of the current/last cast. Never creates one: spots only come from actually fishing somewhere.
function NS.CurrentSpot() return currentSpot or GetSpot(false) end
-- The spot where you are standing, if you have fished there
function NS.SpotHere() return (GetSpot(false)) end

-- Earlier versions created an empty spot wherever the status window looked while you walked around. Remove spots
-- that were never fished (no casts, nothing caught, no chests) so they stop taking up space.
local function PruneEmptySpots()
    for mapID, spots in pairs(NS.db.spots) do
        for key, spot in pairs(spots) do
            if (spot.casts or 0) == 0 and not next(spot.items or {}) and (spot.chests or 0) == 0 then
                spots[key] = nil
            end
        end
        if not next(spots) then NS.db.spots[mapID] = nil end
    end
end
NS.On("UNIT_SPELLCAST_CHANNEL_START", function(_, _, spellID)
    if not NS.db.heatmap or not NS.IsFishingSpell(spellID) then return end
    local spot = GetSpot(true)
    if not spot then return end
    currentSpot, castStart = spot, GetTime()
    spot.casts = spot.casts + 1
    -- running mean position so the pin sits where you actually stand
    local _, x, y = PlayerPos()
    spot.n = spot.n + 1
    spot.x = spot.x + (x - spot.x) / spot.n
    spot.y = spot.y + (y - spot.y) / spot.n
    spot.sub = GetSubZoneText() ~= "" and GetSubZoneText() or spot.sub
    local h = ServerHour()
    spot.hours[h] = (spot.hours[h] or 0) + 1
end)

NS.On("UNIT_SPELLCAST_CHANNEL_STOP", function()
    if currentSpot and castStart then currentSpot.seconds = currentSpot.seconds + (GetTime() - castStart) end
    castStart = nil
end)

local function IsJunk(item)
    if NS.IsTreasure(item.name) then return false end
    if NS.JUNK[item.name] then return true end
    return item.quality == 0
end
NS.IsJunk = IsJunk

NS.OnCatch(function(loot)
    if not NS.db.heatmap then return end
    local spot = currentSpot or GetSpot(true)
    if not spot then return end
    for _, item in ipairs(loot) do
        if NS.IsTreasure(item.name) then spot.chests = (spot.chests or 0) + item.quantity end
        if IsJunk(item) then
            spot.junk = spot.junk + item.quantity
        else
            spot.catches = spot.catches + item.quantity
            local rec = spot.items[item.name]
            if not rec then rec = { n = 0, hours = {} } spot.items[item.name] = rec end
            rec.n = rec.n + item.quantity
            local h = ServerHour()
            rec.hours[h] = (rec.hours[h] or 0) + item.quantity
        end
    end
end)

------------------------------------------------------------------------------------------------------------------------
-- Scoring and tooltips
------------------------------------------------------------------------------------------------------------------------
-- 0..1 quality: catches per cast weighted by junk rate
local function Score(spot)
    if spot.casts == 0 then return 0 end
    local hit = spot.catches / spot.casts
    local total = spot.catches + spot.junk
    local clean = total > 0 and (spot.catches / total) or 1
    return math.min(1, hit * 0.7 + clean * 0.3)
end

local function ScoreColor(s)
    if s >= 0.75 then return 0.2, 1, 0.2 end
    if s >= 0.45 then return 1, 0.8, 0.2 end
    return 1, 0.3, 0.3
end

local function BestHours(hours)
    local best, bestN = nil, 0
    for h, n in pairs(hours) do if n > bestN then best, bestN = h, n end end
    return best
end

local function SpotTooltip(tooltip, spot)
    if NS.IsPoolSpot and NS.IsPoolSpot(spot) then
        tooltip:AddLine(("|cff44ff44%s|r - %s"):format(NS.PoolLabel(spot), (spot.sub and spot.sub ~= "") and spot.sub or spot.zone or "?"))
        tooltip:AddLine(("%d pool catches%s"):format(spot.pool or 0, spot.poolCertain and "" or " (inferred)"), 1, 1, 1)
    else
        tooltip:AddLine(("Fishing spot: %s"):format((spot.sub and spot.sub ~= "") and spot.sub or spot.zone or "?"))
    end
    local total = spot.catches + spot.junk
    local junkPct = total > 0 and (spot.junk / total * 100) or 0
    local perHour = spot.seconds > 60 and (spot.catches / (spot.seconds / 3600)) or nil
    tooltip:AddLine(("%d casts, %d fish, %d%% junk%s"):format(spot.casts, spot.catches, junkPct,
        perHour and (", %.0f fish/hr"):format(perHour) or ""), 1, 1, 1)
    if (spot.chests or 0) > 0 then tooltip:AddLine(("|cffffd700%d chests|r pulled here"):format(spot.chests), 1, 1, 1) end
    local list = {}
    for name, rec in pairs(spot.items) do list[#list + 1] = { name = name, n = rec.n, hours = rec.hours } end
    table.sort(list, function(a, b) return a.n > b.n end)
    for i = 1, math.min(#list, 6) do
        local it = list[i]
        local pct = spot.catches > 0 and it.n / spot.catches * 100 or 0
        local timed = NS.TIMED_FISH[it.name]
        local note = timed and (" |cffaaaaaa" .. timed.label .. "|r") or ""
        tooltip:AddLine(("  %s x%d (%d%%)%s"):format(it.name, it.n, pct, note), 0.9, 0.9, 0.9)
    end
    local mats = NS.SpotMatsLines and NS.SpotMatsLines(spot)
    if mats and #mats > 0 then
        tooltip:AddLine("Materials for you:", 0.5, 1, 0.5)
        for i = 1, math.min(#mats, 4) do
            tooltip:AddLine(("  %s x%d |cff777777%s|r"):format(mats[i].name, mats[i].n, mats[i].prof), 0.9, 0.9, 0.9)
        end
    end
    local h = BestHours(spot.hours)
    if h then tooltip:AddLine(("Most fished around %02d:00 server time"):format(h), 0.6, 0.6, 0.6) end
end

------------------------------------------------------------------------------------------------------------------------
-- World map pins (Blizzard MapCanvas data provider)
------------------------------------------------------------------------------------------------------------------------
EasyFishMapPinMixin = CreateFromMixins(MapCanvasPinMixin or {})

function EasyFishMapPinMixin:OnLoad()
    if MapCanvasPinMixin and MapCanvasPinMixin.OnLoad then MapCanvasPinMixin.OnLoad(self) end
    if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.3) end
    if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_AREA_POI") end
end

function EasyFishMapPinMixin:OnAcquired(spot)
    self.spot = spot
    self:SetPosition(spot.x, spot.y)
    if NS.IsPoolSpot and NS.IsPoolSpot(spot) then
        self.Icon:SetTexture("Interface\\Icons\\INV_Crate_04")
        self.Glow:SetVertexColor(0.3, 1, 0.4, 1)
        self:SetSize(22, 22)
    else
        self.Icon:SetTexture("Interface\\Icons\\INV_Misc_Fish_02")
        local r, g, b = ScoreColor(Score(spot))
        self.Glow:SetVertexColor(r, g, b, 0.8)
        self:SetSize(18, 18)
    end
    self.Icon:SetVertexColor(1, 1, 1)
end

function EasyFishMapPinMixin:OnMouseEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    SpotTooltip(GameTooltip, self.spot)
    GameTooltip:Show()
end

function EasyFishMapPinMixin:OnMouseLeave() GameTooltip:Hide() end

local WorldProvider = CreateFromMixins(MapCanvasDataProviderMixin or {})

function WorldProvider:OnAdded(map)
    MapCanvasDataProviderMixin.OnAdded(self, map)
    -- Tell the canvas what our template is so its pin pool creates the right frame type
    if map.SetPinTemplateType then pcall(map.SetPinTemplateType, map, "EasyFishMapPinTemplate", "FRAME") end
end

function WorldProvider:RemoveAllData()
    pcall(self:GetMap().RemoveAllPinsByTemplate, self:GetMap(), "EasyFishMapPinTemplate")
end

-- Everything here runs inside Blizzard's map refresh; an error would break the map for the player.
-- So: protected, and on the first failure the world-map pins switch themselves off.
local pinsBroken = false
function WorldProvider:RefreshAllData()
    self:RemoveAllData()
    if pinsBroken or not NS.db or not NS.db.worldPins then return end
    local map = self:GetMap()
    local mapID = map:GetMapID()
    local spots = NS.db.spots[mapID]
    if not spots then return end
    for _, spot in pairs(spots) do
        if spot.casts >= (NS.db.pinMinCasts or 3) then
            local ok, err = pcall(map.AcquirePin, map, "EasyFishMapPinTemplate", spot)
            if not ok then
                pinsBroken = true
                self:RemoveAllData()
                Print("world map pins disabled - the map API rejected our pin (%s). Minimap pins still work; please report this.",
                    tostring(err):sub(1, 120))
                return
            end
        end
    end
end

local provider
local function InstallWorldProvider()
    if provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider then return end
    provider = CreateFromMixins(WorldProvider)
    local ok = pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, provider)
    if not ok then provider = nil end
end

local function RefreshWorldPins()
    if provider and WorldMapFrame:IsShown() then safe(provider.RefreshAllData, provider) end
end

------------------------------------------------------------------------------------------------------------------------
-- Minimap pins (own maths: yards from player -> pixels on the minimap)
------------------------------------------------------------------------------------------------------------------------
local OUTDOOR_RADIUS = { 233 + 1/3, 200, 166 + 2/3, 133 + 1/3, 100, 66 + 2/3 }
local INDOOR_RADIUS  = { 300, 240, 180, 120, 80, 50 }

local mmPins, mmPool = {}, {}
local function AcquireMinimapPin()
    local pin = table.remove(mmPool)
    if not pin then
        pin = CreateFrame("Button", nil, Minimap)
        pin:SetSize(12, 12)
        pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)
        pin.Icon = pin:CreateTexture(nil, "ARTWORK")
        pin.Icon:SetAllPoints()
        pin.Icon:SetTexture("Interface\\Icons\\INV_Misc_Fish_02")
        pin.Icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        pin.Ring = pin:CreateTexture(nil, "BACKGROUND")
        pin.Ring:SetSize(18, 18)
        pin.Ring:SetPoint("CENTER")
        pin.Ring:SetTexture("Interface\\Minimap\\UI-Minimap-Ping-Center")
        pin.Ring:SetBlendMode("ADD")
        pin:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            SpotTooltip(GameTooltip, self.spot)
            GameTooltip:Show()
        end)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    pin:Show()
    mmPins[#mmPins + 1] = pin
    return pin
end

local function ReleaseMinimapPins()
    for _, pin in ipairs(mmPins) do pin:Hide() mmPool[#mmPool + 1] = pin end
    wipe(mmPins)
end

local function MinimapRadiusYards()
    local zoom = Minimap:GetZoom() or 0
    local indoors = NS.GetCVar("minimapZoom") ~= tostring(zoom) -- Blizzard keeps separate zoom levels in/outdoors
    local t = indoors and INDOOR_RADIUS or OUTDOOR_RADIUS
    return t[zoom + 1] or t[1]
end

local mmMapID, mmSpots, mmW, mmH = nil, nil, nil, nil
local function UpdateMinimapPins()
    if not NS.db or not NS.db.minimapPins then ReleaseMinimapPins() return end
    local mapID, px, py = PlayerPos()
    if not mapID then ReleaseMinimapPins() return end
    if mapID ~= mmMapID then
        mmMapID = mapID
        mmSpots = NS.db.spots[mapID]
        mmW, mmH = safe(C_Map.GetMapWorldSize, mapID)
    end
    ReleaseMinimapPins()
    if not mmSpots or not mmW or mmW == 0 then return end

    local radiusYards = MinimapRadiusYards()
    local half = Minimap:GetWidth() / 2
    local pxPerYard = half / radiusYards
    local rotate = NS.GetCVar("rotateMinimap") == "1"
    local facing = rotate and (GetPlayerFacing() or 0) or 0
    local cosF, sinF = math.cos(facing), math.sin(facing)
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"

    for _, spot in pairs(mmSpots) do
        if spot.casts >= (NS.db.pinMinCasts or 3) then
            local dx = (spot.x - px) * mmW   -- yards east
            local dy = (py - spot.y) * mmH   -- yards north (map y grows downward)
            if rotate then dx, dy = dx * cosF - dy * sinF, dx * sinF + dy * cosF end
            local sx, sy = dx * pxPerYard, dy * pxPerYard
            local dist = math.sqrt(sx * sx + sy * sy)
            local limit = half - 6
            if dist > limit then -- clamp to the edge so far spots still point the way
                sx, sy = sx / dist * limit, sy / dist * limit
            end
            if shape == "ROUND" or dist <= limit then
                local pin = AcquireMinimapPin()
                pin.spot = spot
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", Minimap, "CENTER", sx, sy)
                if NS.IsPoolSpot and NS.IsPoolSpot(spot) then
                    pin.Icon:SetTexture("Interface\\Icons\\INV_Crate_04")
                    pin.Ring:SetVertexColor(0.3, 1, 0.4, 1)
                else
                    pin.Icon:SetTexture("Interface\\Icons\\INV_Misc_Fish_02")
                    local r, g, b = ScoreColor(Score(spot))
                    pin.Ring:SetVertexColor(r, g, b, 0.9)
                end
                pin:SetAlpha(dist > limit and 0.5 or 1)
            end
        end
    end
end

local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.5 then return end
    self.t = 0
    UpdateMinimapPins()
end)

NS.ChestsHere = NS.Memo(function()
    local mapID = C_Map and safe(C_Map.GetBestMapForUnit, "player")
    local spots = mapID and NS.db.spots[mapID]
    local n = 0
    if spots then for _, spot in pairs(spots) do n = n + (spot.chests or 0) end end
    return n
end)

------------------------------------------------------------------------------------------------------------------------
-- Reports
------------------------------------------------------------------------------------------------------------------------
local function BestSpots()
    local list = {}
    for mapID, spots in pairs(NS.db.spots) do
        for _, spot in pairs(spots) do
            if spot.casts >= (NS.db.pinMinCasts or 3) then list[#list + 1] = spot end
        end
    end
    table.sort(list, function(a, b) return Score(a) > Score(b) end)
    Print("Your best spots (%d recorded):", #list)
    for i = 1, math.min(#list, 8) do
        local s = list[i]
        local total = s.catches + s.junk
        local junk = total > 0 and s.junk / total * 100 or 0
        local top
        for name, rec in pairs(s.items) do if not top or rec.n > s.items[top].n then top = name end end
        Print("  %s / %s - %d casts, %d fish, %d%% junk%s", s.zone or "?", s.sub ~= "" and s.sub or "-",
            s.casts, s.catches, junk, top and (", mostly " .. top) or "")
    end
    if #list == 0 then Print("  fish somewhere first!") end
end
NS.AddCommand("spots", BestSpots, "your best recorded fishing spots")
NS.AddCommand("clearspots", function() wipe(NS.db.spots) mmMapID = nil RefreshWorldPins() Print("spot history cleared") end,
    "forget all recorded spots")

------------------------------------------------------------------------------------------------------------------------
-- Timed fish hint for the status window
------------------------------------------------------------------------------------------------------------------------
NS.AddStatusLine(function()
    local h = ServerHour()
    local out = {}
    for name, spec in pairs(NS.TIMED_FISH) do
        if NS.db.totals[name] then -- only mention fish you have actually caught somewhere
            out[#out + 1] = NS.IsTimeActive(spec, h) and ("|cff44ff44" .. name .. "|r") or ("|cff888888" .. name .. "|r")
        end
    end
    if #out == 0 then return nil end
    return "Timed: " .. table.concat(out, ", ")
end)

------------------------------------------------------------------------------------------------------------------------
-- Settings tab
------------------------------------------------------------------------------------------------------------------------
local tab = NS.NewTab("Map")
tab:Header("Personal heatmap")
tab:Text("Every cast and catch is recorded with your position. Pins are coloured green / yellow / red by how well the spot has fished for you. Hover a pin for the details.", true)
tab:Check("Record fishing spots", "heatmap")
tab:Check("Show pins on the world map", "worldPins", RefreshWorldPins)
tab:Check("Show pins on the minimap", "minimapPins")
tab:Slider("Minimum casts before a spot is shown", "pinMinCasts", 1, 20, 1, "%d", RefreshWorldPins)
tab:Button("Best spots", BestSpots, 120)
tab:Button("Clear spot history", function() wipe(NS.db.spots) mmMapID = nil RefreshWorldPins() Print("spot history cleared") end, 140)

NS.On("ADDON_LOADED", function() PruneEmptySpots() InstallWorldProvider() end)
NS.On("PLAYER_ENTERING_WORLD", function() mmMapID = nil InstallWorldProvider() end)
NS.OnCatch(function() mmMapID = nil end) -- new spot may have been created
