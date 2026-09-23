-- EasyFish Prices: what a fish is worth.
--
-- Order of preference: Auctionator -> TradeSkillMaster -> our own AH scan cache -> vendor price.
-- Our scan runs when you open the auction house: C_AuctionHouse.ReplicateItems() hands over the whole listing
-- (the same dump Auctionator uses); we keep the cheapest per-unit buyout of every item we care about.
-- Prices can only be read while the AH window is open, so between visits the cache is what you see.

local ADDON, NS = ...
local Print, safe = NS.Print, NS.safe

NS.CopyDefaults(NS.DEFAULTS, {
    useAH      = true,     -- value fish at AH prices when known
    ahAutoScan = true,     -- scan whenever the auction house is opened (throttled)
    prices     = {},       -- [itemName] = { p = copper per unit, t = time, n = listings }
    lastScan   = 0,
})

local SCAN_INTERVAL = 15 * 60      -- Blizzard throttles ReplicateItems to roughly this anyway
local STALE         = 3 * 86400    -- cached prices older than this fall back to vendor

------------------------------------------------------------------------------------------------------------------------
-- Lookup
------------------------------------------------------------------------------------------------------------------------
local function ItemIDOf(item)
    if type(item) == "number" then return item end
    local id = type(item) == "string" and tonumber(item:match("item:(%d+)"))
    if not id then id = NS.GetItemInfoInstant(item) end
    return id
end

local function ExternalPrice(itemID)
    if not itemID then return nil end
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
        local p = safe(Auctionator.API.v1.GetAuctionPriceByItemID, ADDON, itemID)
        if p and p > 0 then return p, "Auctionator" end
    end
    if TSM_API and TSM_API.GetCustomPriceValue then
        local p = safe(TSM_API.GetCustomPriceValue, "dbmarket", "i:" .. itemID)
        if p and p > 0 then return p, "TSM" end
    end
end

-- Returns copper per unit and a source tag: "ah" (any auction source) or "v" (vendor). 0, "v" when unknown.
function NS.PriceOf(item)
    local name = NS.GetItemInfo(item) or item
    local vendor = select(11, NS.GetItemInfo(item)) or 0
    if NS.db.useAH then
        local p = ExternalPrice(ItemIDOf(item))
        if p then return p, "ah" end
        local rec = type(name) == "string" and NS.db.prices[name]
        if rec and rec.p > 0 and (time() - (rec.t or 0)) < STALE then return rec.p, "ah" end
    end
    return vendor, "v"
end

------------------------------------------------------------------------------------------------------------------------
-- Scan
------------------------------------------------------------------------------------------------------------------------
-- Items worth caching: fish we know about, anything ever fished up, chests.
local function Interesting(name)
    if NS.FISH_SKILL[name] or NS.TIMED_FISH[name] or NS.db.totals[name] then return true end
    if NS.IsTreasure(name) then return true end
    for _, items in pairs(NS.db.chestLoot or {}) do   -- anything that has ever come out of a fished-up chest
        if items[name] then return true end
    end
    return name:sub(1, 4) == "Raw " or name:find("Fish", 1, true) ~= nil
end

local scanning, ahOpen = false, false

local function ProcessReplicate()
    local n = safe(C_AuctionHouse.GetNumReplicateItems) or 0
    local best, listings = {}, 0
    for i = 0, n - 1 do
        local name, _, count, _, _, _, _, _, _, buyout = safe(C_AuctionHouse.GetReplicateItemInfo, i)
        if not name then
            -- info not cached yet; the link still carries the name
            local link = safe(C_AuctionHouse.GetReplicateItemLink, i)
            name = link and link:match("%[(.-)%]")
        end
        if type(name) == "string" and buyout and buyout > 0 and count and count > 0 and Interesting(name) then
            local unit = buyout / count
            local b = best[name]
            if not b then best[name] = { p = unit, n = 1 }
            else
                if unit < b.p then b.p = unit end
                b.n = b.n + 1
            end
            listings = listings + 1
        end
    end
    local now, updated = time(), 0
    for name, b in pairs(best) do
        NS.db.prices[name] = { p = math.floor(b.p), t = now, n = b.n }
        updated = updated + 1
    end
    NS.db.lastScan = now
    scanning = false
    Print("auction scan: %d auctions, %d fish/chest listings, %d prices updated.", n, listings, updated)
    NS.UpdateUI()
end

local function StartScan(manual)
    if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
        if manual then Print("this client has no auction scan API - install Auctionator or TSM for AH prices.") end
        return
    end
    if not ahOpen then if manual then Print("open the auction house first.") end return end
    if scanning then return end
    if not manual and (time() - (NS.db.lastScan or 0)) < SCAN_INTERVAL then return end
    scanning = true
    safe(C_AuctionHouse.ReplicateItems)
    if manual then Print("scanning the auction house...") end
    -- Blizzard silently ignores the call when throttled; give up after a while
    C_Timer.After(30, function() if scanning then scanning = false Print("auction scan timed out (throttled?) - try again in a few minutes.") end end)
end

NS.On("AUCTION_HOUSE_SHOW", function()
    ahOpen = true
    if NS.db.ahAutoScan then C_Timer.After(1, function() StartScan(false) end) end
end)
NS.On("AUCTION_HOUSE_CLOSED", function() ahOpen = false end)
NS.On("REPLICATE_ITEM_LIST_UPDATE", function() if scanning then ProcessReplicate() end end)

NS.AddCommand("scan", function() StartScan(true) end, "scan the auction house for fish prices (AH must be open)")
NS.AddCommand("price", function(rest)
    rest = strtrim(rest or "")
    if rest == "" then
        local list = {}
        for name, rec in pairs(NS.db.prices) do list[#list + 1] = { name, rec } end
        table.sort(list, function(a, b) return a[2].p > b[2].p end)
        Print("cached AH prices (%d), scanned %s:", #list, NS.db.lastScan > 0 and date("%Y-%m-%d %H:%M", NS.db.lastScan) or "never")
        for i = 1, math.min(#list, 15) do Print("  %s - %s (%d listings)", list[i][1], NS.FormatMoney(list[i][2].p), list[i][2].n) end
        return
    end
    local p, src = NS.PriceOf(rest)
    Print("%s: %s (%s)", rest, NS.FormatMoney(p), src == "ah" and "auction" or "vendor")
end, "[item] show cached prices, or the price used for one item")

------------------------------------------------------------------------------------------------------------------------
-- Session value (replaces the vendor-only tally)
------------------------------------------------------------------------------------------------------------------------
-- Adds a looted item to the session's value. kind = "chest" also counts it toward what chests were worth.
-- Item info is often not cached the first time an item is seen (the price comes back nil), so retry briefly.
function NS.AddLootValue(link, quantity, kind, tries)
    local session = NS.session
    local name = NS.GetItemInfo(link)
    if not name then
        tries = (tries or 0) + 1
        if tries <= 5 then C_Timer.After(0.5 * tries, function() NS.AddLootValue(link, quantity, kind, tries) end) end
        return
    end
    local vendor = select(11, NS.GetItemInfo(link)) or 0
    local best, src = NS.PriceOf(link)
    local each = (best and best > 0) and best or vendor
    session.copper = session.copper + vendor * quantity
    session.value  = (session.value or 0) + each * quantity
    if src == "ah" then session.usedAH = true end
    if kind == "chest" then session.chestValue = (session.chestValue or 0) + each * quantity end
    NS.UpdateUI()
end

NS.OnCatch(function(loot)
    for _, item in ipairs(loot) do
        -- A chest is worth what is inside it; that is counted when it is opened, so the box itself adds nothing.
        if not NS.IsTreasure(item.name) then
            NS.AddLootValue(item.link or item.name, item.quantity, "fish")
        end
    end
end)

------------------------------------------------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------------------------------------------------
local tab = NS.NewTab("Prices")
tab:Header("Auction house prices")
tab:Text("Fish are valued at the cheapest per-unit buyout seen at the auction house, falling back to vendor price when unknown. Prices can only be read while the AH window is open, so visit an auctioneer now and then. Auctionator and TSM are used automatically when installed.", true)
tab:Check("Use auction prices when known", "useAH", NS.UpdateUI)
tab:Check("Scan automatically when the auction house opens", "ahAutoScan", nil, "Throttled to once every 15 minutes.")
local status = tab:Text("", true, 30)
tab:Refresh(function()
    local n = 0
    for _ in pairs(NS.db.prices) do n = n + 1 end
    status:SetText(("%d cached prices. Last scan: %s."):format(n,
        NS.db.lastScan > 0 and date("%Y-%m-%d %H:%M", NS.db.lastScan) or "never"))
end)
tab:Button("Scan now (AH must be open)", function() StartScan(true) end, 200)
tab:Button("Clear price cache", function() wipe(NS.db.prices) NS.db.lastScan = 0 Print("price cache cleared") end, 160)
