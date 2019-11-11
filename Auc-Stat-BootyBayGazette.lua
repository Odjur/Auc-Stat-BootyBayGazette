
local library, parent, private = AucAdvanced.NewModule("Stat", "Booty Bay Gazette")
local auctionPrint, decode, _, _, replicate, empty, get, set, default, debugPrint, fill, _TRANS = AucAdvanced.GetModuleLocals()
local bellCurve = AucAdvanced.API.GenerateBellCurve()
local resources = AucAdvanced.Resources
local resolveServerKey = AucAdvanced.ResolveServerKey

local math_huge = math.huge
local math_floor = math.floor
local wipe = wipe

library.Processors = {
	config = function(callbackType, ...)
			private.SetupConfigGui(...)
		end,
	load = function(callbackType, addon)
			if private.OnLoad then
				private.OnLoad(addon)
			end
		end,
	itemtooltip = function(callbackType, ...)
			private.ProcessTooltip(...)
		end,
	battlepettooltip = function(callbackType, ...)
			private.ProcessTooltip(...)
		end
}

local BBGdata = {}

 -- library.GetPrice()
 -- (optional) Returns the estimated price for an item link.
function library.GetPrice(hyperlink, serverKey)
	if not private.GetInfo(hyperlink, serverKey) then
		return
	end
	
	return BBGdata.recent, BBGdata.market, BBGdata.stddev, BBGdata.globalMedian, BBGdata.globalMean, BBGdata.globalStdDev, BBGdata.age, BBGdata.days
end

 -- library.GetPriceColumns()
 -- (optional) Returns the column names for GetPrice.
function library.GetPriceColumns()
	return "Local 2-Day Mean", "Local 14-Day Mean", "Local 14-Day Std Dev", "Global Median", "Global Mean", "Global Std Dev", "Data Age", "Last Seen Locally"
end

local customPrice
local debounce

 -- library.GetPriceArray()
 -- Returns pricing and other statistical info in an array.
function library.GetPriceArray(hyperlink, serverKey)
	if not private.GetInfo(hyperlink, serverKey) then
		return
	end
	
	-- customPrice is the lowest of all selected price values, or 0 if the item has been filtered out.
	customPrice = math_huge
	
	if get("stat.BBG.includeRecent") and BBGdata.recent then
		if BBGdata.recent < customPrice then
			debounce = true
			
			if get("stat.BBG.limitRecentDays") and BBGdata.days then
				if BBGdata.days > 2 then
					debounce = false
				end
			end
			
			if debounce then
				customPrice = BBGdata.recent
			end
		end
	end
	
	if get("stat.BBG.includeMarket") and BBGdata.market then
		if BBGdata.market < customPrice then
			debounce = true
			
			if get("stat.BBG.limitMarketDays") and BBGdata.days then
				if BBGdata.days > 14 then
					debounce = false
				end
			end
			
			if debounce then
				customPrice = BBGdata.market
			end
		end
	end
	
	if get("stat.BBG.includeGlobalMedian") and BBGdata.globalMedian then
		if BBGdata.globalMedian < customPrice then
			customPrice = BBGdata.globalMedian
		end
	end
	
	if get("stat.BBG.includeGlobalMean") and BBGdata.globalMean then
		if BBGdata.globalMean < customPrice then
			customPrice = BBGdata.globalMean
		end
	end
	
	-- Filter out unwanted values.
	if get("stat.BBG.includeStdDev") and BBGdata.stddev and BBGdata.market then
		debounce = true
		
		if get("stat.BBG.limitMarketDays") and BBGdata.days then
			if BBGdata.days > 14 then
				debounce = false
			end
		end
		
		if debounce and BBGdata.stddev > BBGdata.market * get("stat.BBG.thresholdStdDev") / 100 then
			customPrice = 0
		end
	end
	
	if get("stat.BBG.includeGlobalStdDev") and BBGdata.globalStdDev and BBGdata.globalMedian then
		if BBGdata.globalStdDev > BBGdata.globalMedian * get("stat.BBG.thresholdGlobalStdDev") / 100 then
			customPrice = 0
		end
	end
	
	if get("stat.BBG.excludeVendorItems") and BBGdata.days then
		if BBGdata.days == 252 then
			customPrice = 0
		end
	end
	
	-- No usable price sources.
	if customPrice == math_huge then
		customPrice = 0
	end
	
	local priceArray = {}
	priceArray.price = customPrice
	priceArray.seen = 0
	
	-- (optional) Values that other modules may be looking for.
	priceArray.recent = BBGdata.recent -- local 2-day mean
	priceArray.market = BBGdata.market -- local 14-day mean
	priceArray.stddev = BBGdata.stddev -- local 14-day standard deviation
	priceArray.globalMedian = BBGdata.globalMedian -- global mean
	priceArray.globalMean = BBGdata.globalMean -- global median 
	priceArray.globalStdDev = BBGdata.globalStdDev -- global standard deviation
	priceArray.age = BBGdata.age -- seconds since BBG data was compiled
	priceArray.days = BBGdata.days -- days since item was last seen locally
	
	return priceArray
end

local bound

 -- library.GetItemPDF()
 -- Returns the Probability Density Function for an item link.
function library.GetItemPDF(hyperlink, serverKey)
	if not private.GetInfo(hyperlink, serverKey) then
		return
	end
	
	local mean
	local standardDeviation
	
	--[[
		Prioritize local information over global information.
		
		There is no "right" way to return data with this function. Unlike
		GetPriceArray, GetItemPDF only returns one primary value - the bell curve
		- and the information from BBG can produce two bell curves.
		
		A compelling change to this function may be to prioritize returning values
		that are used to determine customPrice, but such a change has no effect on
		this module, and is therefore beyond its scope.
	--]]
	if BBGdata.market and BBGdata.stddev then
		mean = BBGdata.market
		standardDeviation = BBGdata.stddev
	else
		if BBGdata.globalMean and BBGdata.globalStdDev then
			mean = BBGdata.globalMean
			standardDeviation = BBGdata.globalStdDev
		end
	end
	
	-- No available data.
	if mean then
		if mean == 0 then
			return
		end
	else
		return
	end
	
	if standardDeviation then
		if standardDeviation == 0 then
			return
		end
	else
		return
	end
	
	-- Bound standardDeviation to avoid extreme values, which can cause problems for GetMarketValue.
	if standardDeviation > mean then
		standardDeviation = mean
	elseif standardDeviation < mean * 0.01 then
		standardDeviation = mean * 0.01
	end
	
	bellCurve:SetParameters(mean, standardDeviation)
	
	-- Calculate the lower and upper bounds as +/- 3 standard deviations.
	bound = 3 * standardDeviation
	
	return bellCurve, mean - bound, mean + bound
end

function private.OnLoad(addon)
	default("stat.BBG.disableOriginalTooltip", true)
	default("stat.BBG.enable", true)
	
	-- Tooltip variables.
	default("stat.BBG.tooltip", true)
	default("stat.BBG.multiplyStackSize", false)
	default("stat.BBG.custom", false)
	default("stat.BBG.recent", true)
	default("stat.BBG.market", true)
	default("stat.BBG.stddev", true)
	default("stat.BBG.globalMedian", true)
	default("stat.BBG.globalMean", true)
	default("stat.BBG.globalStdDev", true)
	default("stat.BBG.days", true)
	
	-- Price source variables.
	default("stat.BBG.includeRecent", false)
	default("stat.BBG.includeMarket", true)
	default("stat.BBG.includeGlobalMedian", true)
	default("stat.BBG.includeGlobalMean", false)
	
	-- Filter variables.
	default("stat.BBG.limitRecentDays", true)
	default("stat.BBG.limitMarketDays", true)
	default("stat.BBG.includeStdDev", false)
	default("stat.BBG.thresholdStdDev", 50)
	default("stat.BBG.includeGlobalStdDev", false)
	default("stat.BBG.thresholdGlobalStdDev", 50)
	default("stat.BBG.excludeVendorItems", true)
	
	-- Only run this function once.
	private.OnLoad = nil
end

local linkType, itemID, suffix, factor

 -- private.GetInfo(hyperlink, serverKey)
 -- Returns the market info for the requested item in the BBGdata table.
function private.GetInfo(hyperlink, serverKey)
	if not get("stat.BBG.enable") then
		return
	end
	
	-- BootyBayGazette addon doesn't support cross-server pricing.
	if resolveServerKey(serverKey) ~= resources.ServerKey then
		return
	end
	
	linkType, itemID, suffix, factor = decode(hyperlink)
	
	if linkType ~= "item" and linkType ~= "battlepet" then
		return
	end
	
	wipe(BBGdata)
	
	if TUJMarketInfo then
		TUJMarketInfo(hyperlink, BBGdata)
	else
		return
	end
	
	if BBGdata.itemid then
		return itemID
	end
	
	if BBGdata.species then
		return BBGdata.species
	end
end

function private.SetupConfigGui(gui)
	local tab = gui:AddTab(library.libName, library.libType .. " Modules")
	
	gui:AddHelp(tab, "TODO",
		_TRANS("Author's Note"),
		_TRANS("This help section is somewhat out of date, but I am too lazy to update it. No one reads this anyways. Mouse over the options for clarification about what they do.")
	) gui:AddHelp(tab, "what BBG",
		_TRANS("BBG_Help_Question1"),
		_TRANS("BBG_Help_Answer1")
	) gui:AddHelp(tab, "what auc stat BBG",
		_TRANS("BBG_Help_Question2"),
		_TRANS("BBG_Help_Answer2")
	) gui:AddHelp(tab, "which setup",
		_TRANS("BBG_Help_Question3"),
		_TRANS("BBG_Help_Answer3")
	) gui:AddHelp(tab, "where setup",
		_TRANS("BBG_Help_Question4"),
		_TRANS("BBG_Help_Answer4")
	)
	
	-- All options here will be duplicated in the tooltip frame.
	function private.addTooltipControls(id)
		gui:MakeScrollable(id)
		
		gui:AddControl(id, "Header", 0, _TRANS("BBG_Interface_Options"))
		gui:AddControl(id, "Note", 0, 1, nil, nil, " ")
		
		gui:AddControl(id, "Checkbox", 0, 1, "stat.BBG.disableOriginalTooltip", _TRANS("BBG_Interface_DisableOriginalTooltip"))
		gui:AddTip(id, _TRANS("BBG_HelpTooltip_DisableOriginalTooltip"))
		gui:AddControl(id, "Note", 0, 1, nil, nil, " ")
		
		gui:AddControl(id, "Checkbox", 0, 1, "stat.BBG.enable", _TRANS("BBG_Interface_Enable"))
		gui:AddTip(id, _TRANS("BBG_HelpTooltip_Enable"))
		
		gui:AddControl(id, "Subhead", 0, _TRANS("BBG_Interface_Tooltip"))
		gui:AddControl(id, "Checkbox", 0, 4, "stat.BBG.tooltip", _TRANS("BBG_Interface_ToggleTooltip"))
		gui:AddTip(id, _TRANS("BBG_HelpTooltip_ToggleTooltip"))
		gui:AddControl(id, "Checkbox", 0, 7, "stat.BBG.multiplyStackSize", _TRANS("BBG_Interface_ToggleMultiplyStackSize"))
		gui:AddTip(id, _TRANS("BBG_HelpTooltip_ToggleMultiplyStackSize"))
		gui:AddControl(id, "Note", 0, 1, nil, nil, " ")
		gui:AddControl(id, "Checkbox", 0, 7, "stat.BBG.custom", _TRANS("BBG_Interface_ToggleCustom"))
		gui:AddTip(id, _TRANS("BBG_HelpTooltip_ToggleCustom"))
		gui:AddControl(id, "Checkbox", 0, 7, "stat.BBG.recent", _TRANS("BBG_Interface_ToggleRecent"))
		gui:AddTip(id, _TRANS("BBG_HelpTooltip_ToggleRecent"))
		gui:AddControl(id, "Checkbox", 0, 7, "stat.BBG.market", _TRANS("BBG_Interface_ToggleMarket"))
		gui:AddTip(id, _TRANS("BBG_HelpTooltip_ToggleMarket"))
		gui:AddControl(id, "Checkbox", 0, 7, "stat.BBG.stddev", _TRANS("BBG_Interface_ToggleStdDev"))
		gui:AddTip(id, _TRANS("BBG_HelpTooltip_ToggleStdDev"))
		gui:AddControl(id, "Checkbox", 0, 7, "stat.BBG.globalMedian", _TRANS("BBG_Interface_ToggleGlobalMedian"))
		gui:AddTip(id, _TRANS("BBG_HelpTooltip_ToggleGlobalMedian"))
		gui:AddControl(id, "Checkbox", 0, 7, "stat.BBG.globalMean", _TRANS("BBG_Interface_ToggleGlobalMean"))
		gui:AddTip(id, _TRANS("BBG_HelpTooltip_ToggleGlobalMean"))
		gui:AddControl(id, "Checkbox", 0, 7, "stat.BBG.globalStdDev", _TRANS("BBG_Interface_ToggleGlobalStdDev"))
		gui:AddTip(id, _TRANS("BBG_HelpTooltip_ToggleGlobalStdDev"))
		gui:AddControl(id, "Checkbox", 0, 7, "stat.BBG.days", _TRANS("BBG_Interface_ToggleDays"))
		gui:AddTip(id, _TRANS("BBG_HelpTooltip_ToggleDays"))
	end
	
	private.addTooltipControls(tab)
	
	gui:AddControl(tab, "Subhead", 0, _TRANS("BBG_Interface_Custom"))
	gui:AddControl(tab, "Checkbox", 0, 4, "stat.BBG.includeRecent", _TRANS("BBG_Interface_IncludeRecent"))
	gui:AddTip(tab, _TRANS("BBG_HelpTooltip_IncludeRecent"))
	gui:AddControl(tab, "Checkbox", 0, 4, "stat.BBG.includeMarket", _TRANS("BBG_Interface_IncludeMarket"))
	gui:AddTip(tab, _TRANS("BBG_HelpTooltip_IncludeMarket"))
	gui:AddControl(tab, "Checkbox", 0, 4, "stat.BBG.includeGlobalMedian", _TRANS("BBG_Interface_IncludeGlobalMedian"))
	gui:AddTip(tab, _TRANS("BBG_HelpTooltip_IncludeGlobalMedian"))
	gui:AddControl(tab, "Checkbox", 0, 4, "stat.BBG.includeGlobalMean", _TRANS("BBG_Interface_IncludeGlobalMean"))
	gui:AddTip(tab, _TRANS("BBG_HelpTooltip_IncludeGlobalMean"))
	
	gui:AddControl(tab, "Subhead", 0, _TRANS("BBG_Interface_Filters"))
	gui:AddControl(tab, "Checkbox", 0, 4, "stat.BBG.limitRecentDays", _TRANS("BBG_Interface_LimitRecentDays"))
	gui:AddTip(tab, _TRANS("BBG_HelpTooltip_LimitRecentDays"))
	gui:AddControl(tab, "Checkbox", 0, 4, "stat.BBG.limitMarketDays", _TRANS("BBG_Interface_LimitMarketDays"))
	gui:AddTip(tab, _TRANS("BBG_HelpTooltip_LimitMarketDays"))
	gui:AddControl(tab, "Checkbox", 0, 4, "stat.BBG.includeStdDev", _TRANS("BBG_Interface_IncludeStdDev"))
	gui:AddTip(tab, _TRANS("BBG_HelpTooltip_IncludeStdDev"))
	gui:AddControl(tab, "WideSlider", 0, 6, "stat.BBG.thresholdStdDev", 0, 100, 1, _TRANS("BBG_Interface_ThresholdStdDev"))
	gui:AddControl(tab, "Checkbox", 0, 4, "stat.BBG.includeGlobalStdDev", _TRANS("BBG_Interface_IncludeGlobalStdDev"))
	gui:AddTip(tab, _TRANS("BBG_HelpTooltip_IncludeGlobalStdDev"))
	gui:AddControl(tab, "WideSlider", 0, 6, "stat.BBG.thresholdGlobalStdDev", 0, 100, 1, _TRANS("BBG_Interface_ThresholdGlobalStdDev"))
	gui:AddControl(tab, "Checkbox", 0, 4, "stat.BBG.excludeVendorItems", _TRANS("BBG_Interface_ExcludeVendorItems"))
	gui:AddTip(tab, _TRANS("BBG_HelpTooltip_ExcludeVendorItems"))
	gui:AddControl(tab, "Note", 0, 1, nil, nil, " ")
	
	local tooltipID = AucAdvanced.Settings.Gui.tooltipID
	
	if tooltipID then
		private.addTooltipControls(tooltipID)
		gui:AddControl(tooltipID, "Note", 0, 1, nil, nil, " ")
	end
end

local R_1 = 0.4 -- 102
local G_1 = 1.0 -- 255
local B_1 = 0.4 -- 102

-- BBG colors.
local R_2 = 0.9
local G_2 = 0.8
local B_2 = 0.5

function private.ProcessTooltip(tooltip, hyperlink, serverKey, quantity, decoded, additional, order)
	if TUJTooltip then
		if get("stat.BBG.disableOriginalTooltip") then
			TUJTooltip(false)
		else
			TUJTooltip(true)
		end
	end
	
	if not get("stat.BBG.tooltip") then return end
	if not private.GetInfo(hyperlink, serverKey) then return end
	
	if get("stat.BBG.multiplyStackSize") then
		if not quantity or quantity < 1 then
			quantity = 1
		end
		
		tooltip:AddLine(_TRANS("BBG_Tooltip_StackSize"):format(quantity), R_1, G_1, B_1)
	else
		quantity = 1
	end
	
	if BBGdata.age then
		if BBGdata.age > 259200 then
			local age1 = BBGdata.age / 86400
			local age2 = math.floor((BBGdata.age / 86400 - math_floor(BBGdata.age / 86400)) * 24)
			
			if age2 ~= 1 then
				if age2 ~= 0 then
					tooltip:AddLine(_TRANS("BBG_Tooltip_Age1"):format(age1, age2), R_1, G_1, B_1)
				else
					tooltip:AddLine(_TRANS("BBG_Tooltip_Age3"):format(age1), R_1, G_1, B_1)
				end
			else
				tooltip:AddLine(_TRANS("BBG_Tooltip_Age2"):format(age1, age2), R_1, G_1, B_1)
			end
		end
	end
	
	if get("stat.BBG.custom") and library.GetPriceArray(hyperlink, serverKey) then
		tooltip:AddLine(_TRANS("BBG_Tooltip_Custom"), customPrice * quantity)
	end
	
	if get("stat.BBG.recent") and BBGdata.recent then
		tooltip:AddLine(_TRANS("BBG_Tooltip_Recent"), BBGdata.recent * quantity)
	end
	
	if get("stat.BBG.market") and BBGdata.market then
		tooltip:AddLine(_TRANS("BBG_Tooltip_Market"), BBGdata.market * quantity)
	end
	
	if get("stat.BBG.stddev") and BBGdata.stddev then
		tooltip:AddLine(_TRANS("BBG_Tooltip_StdDev"), BBGdata.stddev * quantity, R_2, G_2, B_2)
	end
	
	if get("stat.BBG.globalMedian") and BBGdata.globalMedian then
		tooltip:AddLine(_TRANS("BBG_Tooltip_GlobalMedian"), BBGdata.globalMedian * quantity)
	end
	
	if get("stat.BBG.globalMean") and BBGdata.globalMean then
		tooltip:AddLine(_TRANS("BBG_Tooltip_GlobalMean"), BBGdata.globalMean * quantity)
	end
	
	if get("stat.BBG.globalStdDev") and BBGdata.globalStdDev then
		tooltip:AddLine(_TRANS("BBG_Tooltip_GlobalStdDev"), BBGdata.globalStdDev * quantity, R_2, G_2, B_2)
	end
	
	if get("stat.BBG.days") and BBGdata.days then
		if BBGdata.days == 255 then
			tooltip:AddLine(_TRANS("BBG_Tooltip_NotSeen"), R_1, G_1, B_1)
		elseif BBGdata.days == 252 then
			tooltip:AddLine(_TRANS("BBG_Tooltip_VendorItems"), R_1, G_1, B_1)
		elseif BBGdata.days > 250 then
			tooltip:AddLine(_TRANS("BBG_Tooltip_LastSeen250"), R_1, G_1, B_1)
		elseif BBGdata.days > 1 then
			tooltip:AddLine(_TRANS("BBG_Tooltip_Days"):format(BBGdata.days), R_1, G_1, B_1)
		elseif BBGdata.days == 1 then
			tooltip:AddLine(_TRANS("BBG_Tooltip_Day"), R_1, G_1, B_1)
		end
	end
end
