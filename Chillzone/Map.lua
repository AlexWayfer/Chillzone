-- Chillzone: круги на карте мира — сколько участников гильдий «Чиллзон» в каждой зоне.
-- Только по свежим отчётам, где репортёр согласился делиться зонами. Рисуется через
-- HereBeDragons-Pins и только при открытой карте. Портировано из Olympus Map.lua.
local ADDON, ns = ...

local L = ns.L

local Map = {}
ns.Map = Map

local Pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
if Pins and not (Pins.AddWorldMapIconMap and Pins.RemoveAllWorldMapIcons) then Pins = nil end

local SHOW_FLAG = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2
local SHOW_HERE = 0
local pool, active = {}, {}
local queued = false
local drawn = false
Map.dirty = true

function Map.GamepadUI()
	local current = C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle
	local gamepad = Enum and Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad
	if not current or gamepad == nil then return false end
	local ok, style = pcall(current)
	return ok and style == gamepad
end

local function ShortCount(n)
	if n >= 1000 then return ("%.1fk"):format(n / 1000) end
	return tostring(n)
end

local function PinEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(ns.Zones.NameForKey(self.key), 1, 0.82, 0)
	GameTooltip:AddLine(L.PIN_TOTAL:format(self.count), 1, 1, 1)
	local list = {}
	for name, n in pairs(self.guilds or {}) do list[#list + 1] = { name = name, n = n } end
	table.sort(list, function(a, b)
		if a.n ~= b.n then return a.n > b.n end
		return a.name < b.name
	end)
	for i = 1, math.min(10, #list) do
		GameTooltip:AddDoubleLine(ns.Codec.Plain(list[i].name), tostring(list[i].n), 0.8, 0.8, 0.8, 1, 1, 1)
	end
	GameTooltip:Show()
end

local function CreatePin()
	local p = CreateFrame("Frame", nil, UIParent)
	p:SetSize(20, 20)
	p:EnableMouse(true)
	p.edge = p:CreateTexture(nil, "BACKGROUND", nil, -1)
	p.edge:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
	p.edge:SetVertexColor(0.5, 0.83, 0.76, 0.95)
	p.edge:SetPoint("TOPLEFT", -2, 2)
	p.edge:SetPoint("BOTTOMRIGHT", 2, -2)
	p.bg = p:CreateTexture(nil, "BACKGROUND", nil, 1)
	p.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
	p.bg:SetVertexColor(0.04, 0.1, 0.1, 0.9)
	p.bg:SetAllPoints()
	p.text = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	p.text:SetPoint("CENTER", 0, 0)
	p.text:SetTextColor(1, 1, 1)
	p:SetScript("OnEnter", PinEnter)
	p:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return p
end

-- Город — не дочерняя карта своей зоны (Штормград лежит в Восточных королевствах, а не в
-- Элвиннском лесу): круг города повторяется на карте зоны вокруг него.
local containerOf = {}
local function ContainerOf(mapID)
	if containerOf[mapID] ~= nil then return containerOf[mapID] end
	local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
	if not HBD or not HBD.GetWorldCoordinatesFromZone or not C_Map.GetMapInfo then return false end
	containerOf[mapID] = false
	local wx, wy = HBD:GetWorldCoordinatesFromZone(0.5, 0.5, mapID)
	local info = C_Map.GetMapInfo(mapID)
	if not wx or not info or not info.parentMapID then return false end
	local ownW, ownH = HBD:GetZoneSize(mapID)
	local best, bestArea
	for _, child in ipairs(C_Map.GetMapChildrenInfo(info.parentMapID) or {}) do
		local zone = child.mapID
		if zone ~= mapID then
			local x, y = HBD:GetZoneCoordinatesFromWorld(wx, wy, zone)
			local w, h = HBD:GetZoneSize(zone)
			local area = (w or 0) * (h or 0)
			local ax, ay = HBD:GetWorldCoordinatesFromZone(0, 0, mapID)
			local bx, by = HBD:GetWorldCoordinatesFromZone(1, 1, mapID)
			local inside = ax and bx and HBD:GetZoneCoordinatesFromWorld(ax, ay, zone) and HBD:GetZoneCoordinatesFromWorld(bx, by, zone)
			if x and y and inside and area >= 4 * (ownW or 0) * (ownH or 0) and (not best or area < bestArea) then
				best, bestArea = { zone = zone, x = x, y = y }, area
			end
		end
	end
	containerOf[mapID] = best or false
	return containerOf[mapID]
end

local function Clear()
	if drawn and Pins then Pins:RemoveAllWorldMapIcons(Map) end
	drawn = false
	for i = #active, 1, -1 do
		active[i]:Hide()
		pool[#pool + 1] = active[i]
		active[i] = nil
	end
end

local function Place(mapID, x, y, flag, key, count, guilds, size)
	local p = table.remove(pool) or CreatePin()
	p:SetSize(size, size)
	p.text:SetText(ShortCount(count))
	p.key, p.count, p.guilds = key, count, guilds
	Pins:AddWorldMapIconMap(Map, p, mapID, x, y, flag)
	active[#active + 1] = p
	drawn = true
end

function Map.RefreshNow()
	queued = false
	Map.dirty = false
	if not Pins then return end
	Clear()
	-- С интерфейсом геймпада кругов нет: правка карты из кода аддона ломает её управление.
	if Map.GamepadUI() or not ns.db.settings.showMap or not ns.IsMember() then return end
	for key, z in pairs(ns.Data.ZoneCounts()) do
		local mapID = ns.Zones.MapID(key)
		if mapID and z.total > 0 then
			local size = math.min(34, 16 + math.floor(5 * math.log10(z.total)))
			Place(mapID, 0.5, 0.5, SHOW_FLAG, key, z.total, z.guilds, size)
			local around = ContainerOf(mapID)
			if around then Place(around.zone, around.x, around.y, SHOW_HERE, key, z.total, z.guilds, size) end
		end
	end
end

-- Перерисовка только при открытой карте; закрытая перерисуется при открытии.
function Map.Refresh()
	Map.dirty = true
	if queued or not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
	queued = true
	ns.After(0.5, "map refresh", Map.RefreshNow)
end

function Map.SetEnabled(on)
	ns.db.settings.showMap = on and true or false
	ns.Print(on and L.MAP_ON or L.MAP_OFF)
	Map.dirty = true
	if WorldMapFrame and WorldMapFrame:IsShown() then Map.RefreshNow() else Clear() end
	ns.Fire("SETTINGS")
end

-- С геймпадом провайдер библиотеки при каждой смене карты чистит её пины, даже если их нет,
-- и делает это нашим кодом — карта геймпада потом блокируется. Пока наших пинов нет, чистка
-- пропускается. Только если загружена наша копия библиотеки.
local function QuietProvider()
	local provider = type(Pins) == "table" and Pins.worldmapProvider
	local original = type(provider) == "table" and provider.RemoveAllData
	if type(original) ~= "function" or type(issecurevariable) ~= "function" then return end
	local _, owner = issecurevariable(provider, "RemoveAllData")
	if owner ~= ADDON then return end
	provider.RemoveAllData = function(self, ...)
		if Map.GamepadUI() then
			local pinPool = Pins.worldmapPinsPool
			if type(pinPool) == "table" and type(pinPool.GetNumActive) == "function" and pinPool:GetNumActive() == 0 then return end
		end
		return original(self, ...)
	end
end

ns.On("LOGIN", function()
	ns.SafeCall("map provider", QuietProvider)
	if WorldMapFrame then
		WorldMapFrame:HookScript("OnShow", function()
			if Map.dirty then ns.SafeCall("map shown", Map.RefreshNow) end
		end)
	end
end)

ns.On("DATA", Map.Refresh)
ns.On("GUILD_CHANGED", Map.Refresh)

ns.Command("map", function(arg)
	arg = ns.Util.Fold(ns.Util.Trim(arg))
	if arg == "on" or arg == "вкл" then
		Map.SetEnabled(true)
	elseif arg == "off" or arg == "выкл" then
		Map.SetEnabled(false)
	else
		Map.SetEnabled(not ns.db.settings.showMap)
	end
end, L.HELP_MAP)
