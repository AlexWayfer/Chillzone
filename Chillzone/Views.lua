-- Chillzone: содержимое вкладок окна — строки «Переписи» и дерево «Королевства», подсказки.
-- Каждая вкладка — список строк { text, right, indent, tip(tooltip) }; UI.lua их рисует.
local ADDON, ns = ...

local U = ns.Util
local C = ns.Config
local Codec = ns.Codec
local L = ns.L

local Views = {}
ns.Views = Views

local ICON_ON = "|TInterface\\FriendsFrame\\StatusIcon-Online:12|t"
local ICON_OFF = "|TInterface\\FriendsFrame\\StatusIcon-Offline:12|t"
local ICON_KING = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:14|t"
local ICON_OFFICER = "|TInterface\\GroupFrame\\UI-Group-AssistantIcon:12|t"
local GOLD, GREY, RED, WHITE = "|cffffd100", "|cff999999", "|cffff4040", "|cffffffff"

function Views.Ago(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	if seconds < 60 then return L.AGO_NOW end
	if seconds < 3600 then return L.AGO_MIN:format(math.floor(seconds / 60)) end
	if seconds < 86400 then return L.AGO_HOUR:format(math.floor(seconds / 3600)) end
	return L.AGO_DAY:format(math.floor(seconds / 86400))
end

-- Имя цветом класса (имена из чужих отчётов — только простой текст).
function Views.Name(name, class)
	name = Codec.Plain(name or "?")
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color and color.colorStr then return "|c" .. color.colorStr .. name .. "|r" end
	return name
end

local function Dot(online)
	return online and ICON_ON or ICON_OFF
end

local function GuildLabel(s)
	local name = Codec.Plain(s.guild)
	if s.main then name = GOLD .. name .. "|r" end
	if s.mine then name = name .. " " .. GREY .. L.MINE_MARK .. "|r" end
	if s.conflict then name = name .. " " .. RED .. "!|r" end
	return name
end

---------------------------------------------------------------------------
-- Подсказка гильдии
---------------------------------------------------------------------------
local function SortedMap(map)
	local list = {}
	for k, v in pairs(map or {}) do list[#list + 1] = { k = k, v = v } end
	table.sort(list, function(a, b)
		if a.v ~= b.v then return a.v > b.v end
		return tostring(a.k) < tostring(b.k)
	end)
	return list
end

function Views.GuildTip(tt, s)
	local r = s.r
	tt:AddLine(Codec.Plain(s.guild), 1, 0.82, 0)
	if s.conflict then tt:AddLine(L.TIP_CONFLICT, 1, 0.25, 0.25, true) end
	if s.main then tt:AddLine(L.TIP_MAIN, 0.5, 0.83, 0.76) end
	tt:AddDoubleLine(L.TIP_MEMBERS, s.total and tostring(s.total) or "?", 0.8, 0.8, 0.8, 1, 1, 1)
	tt:AddDoubleLine(L.TIP_ONLINE, s.online and tostring(s.online) or L.TIP_STALE, 0.8, 0.8, 0.8, 1, 1, 1)
	if r.leader then
		local state = (s.fresh and r.leaderOnline) and L.ONLINE or L.OFFLINE_DAYS:format(r.leaderDays or 0)
		tt:AddDoubleLine(L.TIP_LEADER, Views.Name(r.leader, r.leaderClass) .. " " .. GREY .. state .. "|r", 0.8, 0.8, 0.8, 1, 1, 1)
	end
	tt:AddDoubleLine(L.TIP_OFFICERS, tostring(#(r.officers or {})), 0.8, 0.8, 0.8, 1, 1, 1)
	tt:AddDoubleLine(L.TIP_ADDON, tostring(r.users or 0), 0.8, 0.8, 0.8, 1, 1, 1)
	tt:AddDoubleLine(L.TIP_AVG, ("%.1f"):format(r.avgLevel or 0), 0.8, 0.8, 0.8, 1, 1, 1)
	tt:AddDoubleLine(L.TIP_INACTIVE, ("%d / %d"):format(r.inactive7 or 0, r.inactive30 or 0), 0.8, 0.8, 0.8, 1, 1, 1)
	if s.fresh then
		local classes = {}
		for _, e in ipairs(SortedMap(r.classes)) do classes[#classes + 1] = Views.Name(L.CLASS[e.k] or e.k, e.k) .. " " .. e.v end
		if #classes > 0 then tt:AddLine(L.TIP_CLASSES .. " " .. table.concat(classes, ", "), 0.8, 0.8, 0.8, true) end
		local lv = r.levels or {}
		tt:AddLine(L.TIP_LEVELS:format(lv[1] or 0, lv[2] or 0, lv[3] or 0, lv[4] or 0, lv[5] or 0, lv[6] or 0, lv[7] or 0), 0.8, 0.8, 0.8, true)
		local zones = SortedMap(r.zones)
		if #zones > 0 then
			tt:AddLine(L.TIP_ZONES, 1, 0.82, 0)
			for i = 1, math.min(8, #zones) do
				tt:AddDoubleLine("  " .. ns.Zones.NameForKey(zones[i].k), tostring(zones[i].v), 0.8, 0.8, 0.8, 1, 1, 1)
			end
		elseif not s.mine then
			tt:AddLine(L.TIP_NO_ZONES, 0.6, 0.6, 0.6, true)
		end
	end
	local ranks = {}
	for _, e in ipairs(r.ranks or {}) do ranks[#ranks + 1] = Codec.Plain(e.name) .. " " .. e.count end
	if #ranks > 0 then tt:AddLine(L.TIP_RANKS .. " " .. table.concat(ranks, ", "), 0.6, 0.6, 0.6, true) end
	tt:AddLine(s.mine and L.TIP_FROM_ROSTER or L.TIP_UPDATED:format(Views.Ago(s.age)), 0.6, 0.6, 0.6)
end

---------------------------------------------------------------------------
-- Вкладка «Перепись»
---------------------------------------------------------------------------
function Views.Census()
	local lines = {}
	local guilds, total, online = ns.Data.Totals()
	lines[#lines + 1] = { text = WHITE .. L.CENSUS_TOTALS:format(guilds, total, online) .. "|r", header = true }
	local list = ns.Data.Summary()
	if #list == 0 then
		lines[#lines + 1] = { text = GREY .. L.CENSUS_EMPTY .. "|r", wrap = true }
		return lines
	end
	for _, s in ipairs(list) do
		local right
		if s.recent then
			right = (s.online and (WHITE .. s.online .. "|r") or (GREY .. "?|r")) .. GREY .. " / |r" .. s.total
		else
			right = GREY .. L.CENSUS_OLD:format(Views.Ago(s.age)) .. "|r"
		end
		local leader = s.r.leader and (Dot(s.fresh and s.r.leaderOnline) .. Views.Name(s.r.leader, s.r.leaderClass)) or GREY .. "—|r"
		lines[#lines + 1] = { text = GuildLabel(s), right = right, tip = function(tt) Views.GuildTip(tt, s) end }
		lines[#lines + 1] = {
			text = GREY .. L.CENSUS_LEADER .. "|r " .. leader .. GREY .. "  · " .. (s.mine and L.TIP_FROM_ROSTER or Views.Ago(s.age)) .. "|r",
			indent = 1, tip = function(tt) Views.GuildTip(tt, s) end,
		}
	end
	return lines
end

---------------------------------------------------------------------------
-- Вкладка «Королевство»
---------------------------------------------------------------------------
local function PersonTip(p, role, guild)
	return function(tt)
		tt:AddLine(Views.Name(p.name, p.class))
		tt:AddLine(role .. " · " .. Codec.Plain(guild), 0.8, 0.8, 0.8)
		if p.level and p.level > 0 then tt:AddLine(L.TIP_LEVEL:format(p.level), 0.8, 0.8, 0.8) end
		tt:AddLine(p.online and L.ONLINE or L.OFFLINE_DAYS:format(p.days or 0), 0.6, 0.6, 0.6)
	end
end

local function Captains(lines, node, indent)
	for _, c in ipairs(node.captains) do
		lines[#lines + 1] = {
			text = ICON_OFFICER .. " " .. Dot(c.online) .. Views.Name(c.name, c.class),
			right = GREY .. L.ROLE_CAPTAIN .. "|r", indent = indent,
			tip = PersonTip(c, L.ROLE_CAPTAIN, node.guild),
		}
	end
end

function Views.Kingdom()
	local lines = {}
	local tree = ns.Data.Kingdom()
	lines[#lines + 1] = { text = GOLD .. L.KINGDOM_KING .. "|r", header = true }
	local king = tree.king
	if king then
		lines[#lines + 1] = {
			text = ICON_KING .. " " .. Dot(king.leaderOnline) .. Views.Name(king.leader, king.leaderClass) .. "  " .. GREY .. "<" .. Codec.Plain(king.guild) .. ">|r" .. (king.conflict and (" " .. RED .. "!|r") or ""),
			right = GOLD .. L.ROLE_KING .. "|r",
			tip = PersonTip({ name = king.leader, class = king.leaderClass, level = king.leaderLevel, online = king.leaderOnline, days = king.leaderDays }, L.ROLE_KING, king.guild),
		}
		Captains(lines, king, 1)
	else
		lines[#lines + 1] = { text = GREY .. L.KINGDOM_NO_KING:format(C.MAIN_GUILD) .. "|r", wrap = true }
	end
	local lords = 0
	for _, node in ipairs(tree.guilds) do
		if not node.main then
			if lords == 0 then lines[#lines + 1] = { text = GOLD .. L.KINGDOM_LORDS .. "|r", header = true, gap = true } end
			lords = lords + 1
			local lord = node.leader and (Dot(node.leaderOnline) .. Views.Name(node.leader, node.leaderClass)) or (GREY .. "—|r")
			lines[#lines + 1] = {
				text = lord .. "  " .. GREY .. "<" .. Codec.Plain(node.guild) .. ">|r" .. (node.conflict and (" " .. RED .. "!|r") or ""),
				right = GREY .. L.ROLE_LORD .. "|r",
				tip = node.leader and PersonTip({ name = node.leader, class = node.leaderClass, level = node.leaderLevel, online = node.leaderOnline, days = node.leaderDays }, L.ROLE_LORD, node.guild) or nil,
			}
			Captains(lines, node, 1)
		end
	end
	if lords == 0 then
		lines[#lines + 1] = { text = GOLD .. L.KINGDOM_LORDS .. "|r", header = true, gap = true }
		lines[#lines + 1] = { text = GREY .. L.KINGDOM_NO_LORDS .. "|r", wrap = true }
	end
	return lines
end

---------------------------------------------------------------------------
-- Кнопка у миникарты: подсказка
---------------------------------------------------------------------------
function Views.MinimapTip(tt)
	local guilds, total, online = ns.Data.Totals()
	tt:AddLine("Chillzone", 0.5, 0.83, 0.76)
	tt:AddLine(L.CENSUS_TOTALS:format(guilds, total, online), 1, 1, 1)
	local tree = ns.Data.Kingdom()
	if tree.king then tt:AddLine(L.ROLE_KING .. ": " .. Views.Name(tree.king.leader, tree.king.leaderClass), 1, 0.82, 0) end
	tt:AddLine(" ")
	tt:AddLine(L.MINIMAP_LEFT, 0.6, 0.6, 0.6)
	tt:AddLine(L.MINIMAP_RIGHT, 0.6, 0.6, 0.6)
	tt:AddLine(L.MINIMAP_DRAG, 0.6, 0.6, 0.6)
end
