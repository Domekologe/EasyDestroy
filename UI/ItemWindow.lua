-- EasyDestroy/UI/ItemWindow.lua

EasyDestroy.UI.ItemWindowFrame = EasyDestroyItems
EasyDestroy.UI.ItemWindow      = EasyDestroyItemsFrame

local ItemWindow  = EasyDestroy.UI.ItemWindow
ItemWindow.name   = "EasyDestroy.UI.ItemWindow"

local initialized = false
local protected   = {}

-- Optional quality mapping (fallback for older clients)
local EIQ = Enum and Enum.ItemQuality or {}
local QUALITY = {
  POOR     = EIQ.Poor     or 0,
  COMMON   = EIQ.Common   or EIQ.Standard  or (rawget(_G, "LE_ITEM_QUALITY_COMMON")   or 1),
  UNCOMMON = EIQ.Uncommon or EIQ.Good      or (rawget(_G, "LE_ITEM_QUALITY_UNCOMMON") or 2),
  RARE     = EIQ.Rare     or EIQ.Superior  or (rawget(_G, "LE_ITEM_QUALITY_RARE")     or 3),
  EPIC     = EIQ.Epic     or (rawget(_G, "LE_ITEM_QUALITY_EPIC")     or 4),
}

function ItemWindow.__init()
    if initialized then return end

    EasyDestroy.RegisterCallback(ItemWindow, "ED_BLACKLIST_UPDATED",         protected.Update)
    EasyDestroy.RegisterCallback(ItemWindow, "ED_INVENTORY_UPDATED_DELAYED", protected.Update)
    EasyDestroy.RegisterCallback(ItemWindow, "ED_FILTER_CRITERIA_CHANGED",   protected.Update)
    EasyDestroy.RegisterCallback(ItemWindow, "ED_FILTER_LOADED",             protected.Update)

    ItemWindow:Initialize(protected.FindWhitelistItems, 8, 24, protected.ItemOnClick)

    initialized = true
end

function protected.Update(_, _arg)
    if ItemWindow:IsVisible(ItemWindow.name) then
        EasyDestroy.UI.ItemWindow:ItemListUpdate(EasyDestroy.UI.Filters.GenerateFilter())
        EasyDestroy.UI.ItemWindow:ScrollUpdate()
        EasyDestroy.UI.ItemCounter:SetText(EasyDestroy.UI.ItemWindow.ItemCount .. " Item(s) Found")
    end
end

function protected.FindWhitelistItems(activeFilter)
    if activeFilter == nil then return end

    local filter         = activeFilter:ToTable()
    filter.filter        = EasyDestroy.UI.Filters.GetCriteria()
    local filterRegistry = EasyDestroy.CriteriaRegistry

    local items      = {}
    local matchfound = nil
    local typematch  = false

    -- Cache player spells and options each call (reacts immediately to changes)
	local HAS_DE   = IsPlayerSpell and IsSpellKnown(13262)   -- Disenchant
	local HAS_MILL = IsPlayerSpell and IsSpellKnown(51005)   -- Milling
	local HAS_PROS = IsPlayerSpell and IsSpellKnown(31252)   -- Prospecting
	
	local ACT      = EasyDestroy.Data and EasyDestroy.Data.Options and EasyDestroy.Data.Options.Actions or 0
	
    local DO_DE, DO_MILL, DO_PROS = HAS_DE, HAS_MILL, HAS_PROS

    -- Numeric constants (robust against localization issues)
    local CLASS_WEAPON, CLASS_ARMOR, CLASS_TRADEGOODS = 2, 4, 7
    local TG_HERB, TG_METAL_STONE = 9, 7

    for _, item in ipairs(EasyDestroy.Inventory.GetInventory()) do
        matchfound = nil
        typematch  = false

        if item:GetStaticBackingItem() then
            while true do
                matchfound = true

                local cls, sub = item.classID, item.subclassID

                -- Only allow disenchant if spell is known and option is checked
                if (cls == CLASS_ARMOR or cls == CLASS_WEAPON) and not (HAS_DE and DO_DE) then
                    matchfound = false; break
                end

                -- Skip empty stacks for non-DE items
                if (cls ~= CLASS_ARMOR and cls ~= CLASS_WEAPON) and item.count and item.count <= 0 then
                    matchfound = false; break
                end

                -- Quality check only for DE-relevant items (Common..Epic == 1..4)
                if (cls == CLASS_ARMOR or cls == CLASS_WEAPON) then
                    local q = item.quality
                    if q == nil then
                        local _, _, qi = (C_Item and C_Item.GetItemInfo or GetItemInfo)(item.itemLink or item.itemID)
                        if not qi then matchfound = false; break end
                        q = qi
                    end
                    if q < 1 or q > 4 then
                        matchfound = false; break
                    end
                end

                -- Milling requires spell, option, and at least 5 herbs
                if HAS_MILL and DO_MILL and cls == CLASS_TRADEGOODS and sub == TG_HERB and (item.count or 0) < 5 then
                    matchfound = false; break
                end

                -- Prospecting requires spell, option, and at least 5 ores/stones
                if HAS_PROS and DO_PROS and cls == CLASS_TRADEGOODS and sub == TG_METAL_STONE and (item.count or 0) < 5 then
                    matchfound = false; break
                end

                -- Filter out cosmetic armor
                local ARMOR_COSMETIC = Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Cosmetic
                if cls == CLASS_ARMOR and ARMOR_COSMETIC and sub == ARMOR_COSMETIC then
                    matchfound = false; break
                end

                -- Criteria filters (whitelist/blacklist logic)
                for k, v in pairs(EasyDestroy.UI.Filters.GetCriteria()) do
                    local reg = filterRegistry[k]
                    if not reg then
                        print("Unsupported filter:", k or "UNK")
                        matchfound = false; break
                    end
                    if activeFilter:GetType() == ED_FILTER_TYPE_BLACKLIST
                       and type(reg.Blacklist) == "function" then
                        if not reg:Blacklist(v, item) then matchfound = false; break end
                    elseif not reg:Check(v, item) then
                        matchfound = false; break
                    end
                end
                if not matchfound then break end

				typematch = true
				
                -- Skip session-blacklisted items
                if EasyDestroy.Blacklist.HasSessionItem(item) then
                    matchfound = false; break
                end

                if not typematch then break end

                -- Skip permanent blacklisted items (unless blacklist view is active)
                if filter.properties.type ~= ED_FILTER_TYPE_BLACKLIST and EasyDestroy.Blacklist.HasItem(item) then
                    matchfound = false; break
                end
                if filter.properties.type ~= ED_FILTER_TYPE_BLACKLIST and EasyDestroy.Blacklist.InFilterBlacklist(item) then 
                    matchfound = false; break
                end

                break
            end

            if matchfound and typematch then
                tinsert(items, item)

                -- Queue trade goods for restacking
                if EasyDestroy.Inventory.ItemNeedsRestacked(item) then
                    EasyDestroy.Inventory.QueueForRestack(item)
                end
            end
        end
    end

    return items
end

-- ###########################################
-- UI Event Handlers
-- ###########################################

function protected.ItemOnClick(self, button)
	if button == "RightButton" and IsShiftKeyDown() then
	    self.item.menu = {
            { text = self.item:GetItemName(), notCheckable = true, isTitle = true },
            { text = "Add Item to Blacklist", notCheckable = true, func = function() EasyDestroy.Blacklist.AddItem(self.item) end },
            { text = "Ignore Item for Session", notCheckable = true, func = function() EasyDestroy.Blacklist.AddSessionItem(self.item) end },
        }
		EasyDestroy.Blacklist.AddItem(self.item)
		print("Added item to permanent blacklist.")
		return
	end
    if button == "RightButton" then
        self.item.menu = {
            { text = self.item:GetItemName(), notCheckable = true, isTitle = true },
            { text = "Add Item to Blacklist", notCheckable = true, func = function() EasyDestroy.Blacklist.AddItem(self.item) end },
            { text = "Ignore Item for Session", notCheckable = true, func = function() EasyDestroy.Blacklist.AddSessionItem(self.item) end },
        }
		EasyDestroy.Blacklist.AddSessionItem(self.item)
		print("Added item to blacklist for the session.")
		return
    end
	
end
