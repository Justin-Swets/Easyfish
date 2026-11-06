-- EasyFish Recipes: what your catches turn into, and where to learn it.
--
-- The recipe and vendor tables live in RecipeData.lua. Which recipes you know is learned by looking at your profession
-- window whenever it opens, because the game has no way to ask without it.

local ADDON, NS = ...
local Print, safe = NS.Print, NS.safe

NS.CopyDefaults(NS.DEFAULTS, { knownRecipes = {}, recipesAll = false, vendorPins = true, fishTooltip = true })

local vendorByName = {}
for _, v in ipairs(NS.RECIPE_VENDORS) do vendorByName[v.name] = v end

local function CharKey()
    return (safe(UnitName, "player") or "?") .. "-" .. (safe(GetRealmName) or "?")
end

local function KnownList()
    local key = CharKey()
    local list = NS.db.knownRecipes[key]
    if not list then list = {} NS.db.knownRecipes[key] = list end
    return list
end

-- Only ever adds: the window shows one profession at a time, so a recipe missing from it proves nothing
local function ScanKnown()
    local list = KnownList()
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        local ids = safe(C_TradeSkillUI.GetAllRecipeIDs)
        for _, id in ipairs(type(ids) == "table" and ids or {}) do
            local info = safe(C_TradeSkillUI.GetRecipeInfo, id)
            if info and info.name and info.learned ~= false then list[info.name] = true end
        end
    end
    if GetNumTradeSkills then
        for i = 1, safe(GetNumTradeSkills) or 0 do
            local name, kind = safe(GetTradeSkillInfo, i)
            if type(name) == "string" and kind ~= "header" then list[name] = true end
        end
    end
end
NS.On("TRADE_SKILL_SHOW", function() C_Timer.After(0.2, ScanKnown) end)

-- Your skill in a profession, or nil if you don't have it
local function ProfSkill(prof)
    local ok, p1, p2, _, fish, cook = pcall(GetProfessions)
    if not ok then return nil end
    for _, idx in ipairs({ p1 or false, p2 or false, fish or false, cook or false }) do
        if idx then
            local ok2, name, _, rank = pcall(GetProfessionInfo, idx)
            if ok2 and name == prof then return tonumber(rank) or 0 end
        end
    end
    return nil
end
NS.ProfSkill = ProfSkill

local function Count(item)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    return tonumber(safe(f, item)) or 0
end

-- How many you can make right now from the fish in your bags
local function MakeableNow(recipe)
    local most
    for fish, need in pairs(recipe.reagents) do
        local n = math.floor(Count(fish) / need)
        if not most or n < most then most = n end
    end
    return most or 0
end

local function CaughtAny(recipe)
    for fish in pairs(recipe.reagents) do
        if (NS.db.totals[fish] or 0) > 0 or Count(fish) > 0 then return true end
    end
    return false
end

local function BestVendor(recipe)
    if not recipe.vendors then return nil end
    local list = {}
    for _, name in ipairs(recipe.vendors) do
        if vendorByName[name] then list[#list + 1] = vendorByName[name] end
    end
    return NS.NearestNPC(list)
end
NS.BestRecipeVendor = BestVendor

-- Cooking recipes each vendor sells, for the minimap
local cookingAt = {}
for _, recipe in ipairs(NS.RECIPES) do
    if recipe.prof == "Cooking" then
        for _, name in ipairs(recipe.vendors or {}) do
            cookingAt[name] = cookingAt[name] or {}
            table.insert(cookingAt[name], recipe)
        end
    end
end

-- Vendors in this zone worth a minimap pin: they sell a fish cooking recipe, your faction can use them, and we know where
NS.RecipeVendorsHere = NS.Memo(function()
    local zone, list = GetRealZoneText(), {}
    for _, v in ipairs(NS.RECIPE_VENDORS) do
        if v.zone == zone and v.x and v.y and cookingAt[v.name] and NS.UsableNPC(v) then list[#list + 1] = v end
    end
    return list
end)

function NS.VendorTooltip(tooltip, vendor)
    local known = KnownList()
    tooltip:SetText(vendor.name)
    tooltip:AddLine("Sells fish cooking recipes", 1, 0.82, 0)
    for _, recipe in ipairs(cookingAt[vendor.name] or {}) do
        local have = known[recipe.name]
        tooltip:AddDoubleLine(recipe.name, have and "known" or ("Cooking " .. (recipe.skill or 0)), 1, 1, 1,
            have and 0.3 or 0.7, have and 1 or 0.7, have and 0.3 or 0.7)
    end
    if vendor.limited then tooltip:AddLine("Limited stock", 0.7, 0.7, 0.7) end
end

local function SourceText(recipe)
    local vendor = BestVendor(recipe)
    if vendor then
        return ("Vendor: %s, %s%s"):format(vendor.name, vendor.zone, vendor.limited and " (limited stock)" or "")
    end
    if recipe.source == "vendor" then return "Vendor: none for your faction" end
    if recipe.source == "trainer" then return "Learn from a " .. recipe.prof:lower() .. " trainer" end
    if recipe.source == "starter" then return "Known from the start" end
    return recipe.sourceNote or (recipe.source and ("From a " .. recipe.source)) or "Source unknown"
end

-- Everything worth showing, best first: makeable now, then what you know, then by skill.
-- allRecipes also lists fish you've never caught and professions you don't have.
local function Rows(allRecipes, onlyFish)
    local known, rows = KnownList(), {}
    for _, recipe in ipairs(NS.RECIPES) do
        local skill = ProfSkill(recipe.prof)
        local relevant
        if onlyFish then relevant = recipe.reagents[onlyFish] ~= nil
        else relevant = allRecipes or (CaughtAny(recipe) and (skill ~= nil or recipe.prof == "Cooking")) end
        if relevant then
            rows[#rows + 1] = { recipe = recipe, skill = skill, known = known[recipe.name] or recipe.source == "starter",
                                now = MakeableNow(recipe), reachable = skill and skill >= (recipe.skill or 0) }
        end
    end
    table.sort(rows, function(a, b)
        if (a.now > 0) ~= (b.now > 0) then return a.now > 0 end
        if (a.known and true or false) ~= (b.known and true or false) then return a.known and true or false end
        if (a.recipe.skill or 0) ~= (b.recipe.skill or 0) then return (a.recipe.skill or 0) < (b.recipe.skill or 0) end
        return a.recipe.name < b.recipe.name
    end)
    return rows
end
NS.RecipeRows = Rows

local function ReagentText(recipe, icons)
    local parts = {}
    for fish, need in pairs(recipe.reagents) do
        parts[#parts + 1] = ("%s%d %s (have %d)"):format(icons and (NS.IconText(NS.FISH_IDS[fish]) .. " ") or "", need,
            (fish:gsub("^Raw ", "")), Count(fish))
    end
    table.sort(parts)
    if recipe.otherReagents then parts[#parts + 1] = "+ " .. recipe.otherReagents end
    return table.concat(parts, "  ")
end

-- Which section of the list a recipe sits in, and the badge on its row
local SECTIONS = { "Ready to make", "Recipes you know", "You can learn", "Higher skill needed", "Other professions" }
local function Section(row)
    if row.known then
        if row.now > 0 then return 1, ("|cff44ff44Make %d|r"):format(row.now) end
        return 2, "|cff44ff44Known|r"
    end
    if not row.skill then return 5, "|cff888888No " .. row.recipe.prof:lower() .. "|r" end
    if row.reachable then return 3, "|cffffd100Can learn|r" end
    return 4, ("|cffff8800Needs %d|r"):format(row.recipe.skill or 0)
end

local function Go(recipe)
    local vendor = BestVendor(recipe)
    if vendor then NS.Waypoint(vendor) else Print("%s: %s.", recipe.name, SourceText(recipe)) end
end
NS.GoToRecipe = Go

local function ListInChat(rows, heading)
    Print(heading)
    for i = 1, math.min(#rows, 15) do
        local row = rows[i]
        Print("  %s (%s %d) - %s - %s%s", row.recipe.name, row.recipe.prof, row.recipe.skill or 0,
            ReagentText(row.recipe), SourceText(row.recipe), row.now > 0 and (" - can make " .. row.now) or "")
    end
    if #rows == 0 then Print("  nothing yet") end
    if #rows > 15 then Print("  ...and %d more on the Recipes tab", #rows - 15) end
end

local function FindFish(text)
    text = text:lower()
    for _, recipe in ipairs(NS.RECIPES) do
        for fish in pairs(recipe.reagents) do
            if fish:lower():find(text, 1, true) then return fish end
        end
    end
end

NS.AddCommand("recipes", function(rest)
    rest = strtrim(rest or "")
    if rest == "" then ListInChat(Rows(false), "Recipes for fish you've caught:")
    elseif rest == "all" then ListInChat(Rows(true), "Every fish recipe:")
    else
        local fish = FindFish(rest)
        if fish then ListInChat(Rows(false, fish), ("Recipes using %s:"):format(fish))
        else Print("no recipe uses '%s'.", rest) end
    end
end, "[all|fish] what your fish make and where to learn it")

NS.AddCommand("make", function()
    local rows = {}
    for _, row in ipairs(Rows(false)) do if row.now > 0 then rows[#rows + 1] = row end end
    ListInChat(rows, "You can make these from the fish in your bags:")
end, "what the fish in your bags can make right now")

------------------------------------------------------------------------------------------------------------------------
-- Fish tooltip: what it sells for and the best things to make with it
------------------------------------------------------------------------------------------------------------------------
local byFish = {}
NS.RECIPE_PRODUCTS = {}   -- the auction scan prices these too, so recipes can be compared
for _, recipe in ipairs(NS.RECIPES) do
    NS.RECIPE_PRODUCTS[recipe.name] = true
    for fish in pairs(recipe.reagents) do
        byFish[fish] = byFish[fish] or {}
        table.insert(byFish[fish], recipe)
    end
end

-- What one fish earns through a recipe, and whether that's an auction price
local function ValuePerFish(recipe, fish)
    local price, source = NS.PriceOf(recipe.itemID or recipe.name)
    return (tonumber(price) or 0) / recipe.reagents[fish], source
end

-- Best first: what you can make, then cooking over other professions, then what sells highest
function NS.BestRecipes(fish)
    local known, list = KnownList(), {}
    for _, recipe in ipairs(byFish[fish] or {}) do
        local skill = ProfSkill(recipe.prof)
        local value, source = ValuePerFish(recipe, fish)
        list[#list + 1] = { recipe = recipe, value = value, source = source,
                            usable = (known[recipe.name] or (skill and skill >= (recipe.skill or 0))) and true or false }
    end
    table.sort(list, function(a, b)
        if a.usable ~= b.usable then return a.usable end
        if (a.recipe.prof == "Cooking") ~= (b.recipe.prof == "Cooking") then return a.recipe.prof == "Cooking" end
        if a.value ~= b.value then return a.value > b.value end
        return (a.recipe.skill or 0) > (b.recipe.skill or 0)
    end)
    return list
end

function NS.FishTooltip(tooltip, name)
    if not NS.db.fishTooltip or not (byFish[name] or NS.FISH_SKILL[name]) then return end
    local price, source = NS.PriceOf(name)
    tooltip:AddLine(" ")
    if (tonumber(price) or 0) > 0 then
        tooltip:AddDoubleLine(source == "ah" and "Auction price" or "Vendor price", NS.FormatMoney(price), 0.31, 0.82, 0.77, 1, 1, 1)
    else
        tooltip:AddLine("No price yet - scan at the auction house", 0.31, 0.82, 0.77)
    end
    local list = NS.BestRecipes(name)
    if #list == 0 then
        tooltip:AddLine("No known recipe uses this fish", 0.6, 0.6, 0.6)
    else
        tooltip:AddLine("You can make", 0.31, 0.82, 0.77)
    end
    for i, best in ipairs(list) do
        if i > 3 then break end
        local recipe = best.recipe
        local parts = {}
        local now = best.usable and MakeableNow(recipe) or 0
        if now > 0 then parts[#parts + 1] = "x" .. now end
        if best.value > 0 then parts[#parts + 1] = NS.FormatMoney(best.value) .. (best.source == "ah" and " ah" or " v") end
        local g = best.usable and 1 or 0.7
        tooltip:AddDoubleLine(("%s %s"):format(NS.IconText(recipe.itemID), recipe.name), table.concat(parts, "  "),
            best.usable and 0.3 or 0.7, g, best.usable and 0.3 or 0.7, 1, 1, 1)
        if not best.usable then
            tooltip:AddLine(("   %s %d - %s"):format(recipe.prof, recipe.skill or 0, SourceText(recipe)), 0.6, 0.6, 0.6)
        end
    end
    tooltip:Show()
end

local function OnItemTooltip(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local item = data and data.id
    if not item and tooltip.GetItem then
        local _, link = tooltip:GetItem()
        item = link
    end
    local name = item and NS.GetItemInfo(item)
    if type(name) == "string" then safe(NS.FishTooltip, tooltip, name) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
else
    GameTooltip:HookScript("OnTooltipSetItem", OnItemTooltip)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", OnItemTooltip) end
end

------------------------------------------------------------------------------------------------------------------------
-- Tab
------------------------------------------------------------------------------------------------------------------------
local tab = NS.NewTab("Recipes")
tab:Header("What your fish make")
tab:Text("Click a recipe for a waypoint to its nearest vendor. Open your Cooking window once so EasyFish knows your recipes.", true, 28)
local list = tab:List(274)
local function Fill()
    local buckets = {}
    for _, row in ipairs(Rows(NS.db.recipesAll)) do
        local recipe = row.recipe
        local section, badge = Section(row)
        buckets[section] = buckets[section] or {}
        table.insert(buckets[section], {
            icon = NS.ItemIcon(recipe.itemID),
            text = recipe.name,
            right = badge,
            sub = ReagentText(recipe, true),
            sub2 = ("%s %d - %s"):format(recipe.prof, recipe.skill or 0, SourceText(recipe)),
            tip = recipe.effect,
            onClick = function() Go(recipe) end,
        })
    end
    local items = {}
    for i, heading in ipairs(SECTIONS) do
        if buckets[i] then
            items[#items + 1] = { header = heading }
            for _, item in ipairs(buckets[i]) do items[#items + 1] = item end
        end
    end
    if #items == 0 then
        items[1] = { text = "|cff888888Nothing yet.|r", sub = "Catch some fish, or tick the box below to see every recipe." }
    end
    list:Set(items)
end
tab:Refresh(Fill)
tab:Check("Show every recipe, not just fish I've caught", "recipesAll", Fill)
tab:Check("Add price and best recipes to fish tooltips", "fishTooltip")
tab:Check("Mark recipe vendors on the minimap", "vendorPins", nil,
    "Gold food icons show vendors in this zone who sell fish cooking recipes. Hover one to see what they sell.")
