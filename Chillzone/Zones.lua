-- Chillzone: название зоны из ростера → ключ "m<uiMapID>" (одинаков на любом языке
-- клиента, карта знает, где рисовать) или "t<текст>", если карта не нашлась.
-- Портировано из Olympus Zones.lua.
local ADDON, ns = ...

local Zones = {}
ns.Zones = Zones

local ROOT_MAP = 947 -- Азерот
local COSMIC_MAP = 946 -- верх дерева карт: Азерот и Запределье
local SCAN_MAX = 5000

local byName, count
local scanned = false

local function ZoneType()
	return (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
end

local function Add(info)
	if info and info.name and info.name ~= "" then
		if not byName[info.name] or info.mapType == ZoneType() then
			if not byName[info.name] then count = count + 1 end
			byName[info.name] = info.mapID
		end
	end
end

local function Walk(root, visited, add)
	local queue = { root }
	while #queue > 0 do
		local id = table.remove(queue)
		if not visited[id] then
			visited[id] = true
			local children = C_Map.GetMapChildrenInfo(id)
			if children then
				for _, info in ipairs(children) do
					add(info)
					queue[#queue + 1] = info.mapID
				end
			end
		end
	end
end

local function Build()
	byName, count = {}, 0
	if not (C_Map and C_Map.GetMapChildrenInfo) then return end
	local visited = {}
	Walk(ROOT_MAP, visited, Add)
	local taken = {}
	for name in pairs(byName) do taken[name] = true end
	Walk(COSMIC_MAP, visited, function(info)
		if info and info.name and not taken[info.name] then Add(info) end
	end)
	if count == 0 and C_Map.GetMapInfo then
		for id = 1, 2500 do Add(C_Map.GetMapInfo(id)) end
	end
	ns.Log("зон в индексе: %d", count)
end

-- Один раз за сессию, при первом незнакомом названии: перебор всех id карт.
local function Scan()
	scanned = true
	if not (C_Map and C_Map.GetMapInfo) then return end
	local taken = {}
	for name in pairs(byName) do taken[name] = true end
	for id = 1, SCAN_MAX do
		local info = C_Map.GetMapInfo(id)
		local name = info and info.name
		if name and name ~= "" and not taken[name] and (byName[name] == nil or info.mapType == ZoneType()) then
			if byName[name] == nil then count = count + 1 end
			byName[name] = id
		end
	end
end

function Zones.KeyForName(name)
	if not name or name == "" then return nil end
	if not byName then Build() end
	local id = byName[name]
	if not id and not scanned then
		Scan()
		id = byName[name]
	end
	if id then return "m" .. id end
	return "t" .. name
end

function Zones.MapID(key)
	if key and key:sub(1, 1) == "m" then return tonumber(key:sub(2)) end
	return nil
end

function Zones.NameForKey(key)
	local id = Zones.MapID(key)
	if id and C_Map and C_Map.GetMapInfo then
		local info = C_Map.GetMapInfo(id)
		return info and info.name or key
	end
	return ns.Codec.Plain((key or "?"):sub(2))
end
