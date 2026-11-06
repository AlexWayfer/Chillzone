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
local GREEN = "|cff40ff40"

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
-- Шапка окна, как у Olympus: крупно — сколько всего участников во всех гильдиях «Чиллзон»,
-- мелко — сколько в игре, сколько гильдий и когда пришёл самый свежий отчёт.
-- { big, small, guilds, total, online, newest (возраст в секундах) }.
function Views.Status(now)
	now = now or ns.ServerTime()
	local st = { guilds = 0, total = 0, online = 0 }
	for _, s in ipairs(ns.Data.Summary(now)) do
		if s.recent then
			st.guilds = st.guilds + 1
			st.total = st.total + (s.total or 0)
			st.online = st.online + (s.online or 0)
			if not st.newest or s.age < st.newest then st.newest = s.age end
		end
	end
	if st.guilds == 0 then
		st.big, st.small = L.HEAD_WAIT, L.HEAD_WAIT_SUB
		return st
	end
	st.big = U.Num(st.total) .. " " .. U.Plural(st.total, L.HEAD_MEMBER_1, L.HEAD_MEMBER_2, L.HEAD_MEMBER_5)
	st.small = L.HEAD_SUB:format(
		GREEN .. U.Num(st.online) .. "|r",
		WHITE .. st.guilds .. "|r " .. U.Plural(st.guilds, L.HEAD_GUILD_1, L.HEAD_GUILD_2, L.HEAD_GUILD_5),
		Views.Ago(st.newest))
	return st
end

-- Подсказка шапки: по гильдиям, сколько в игре из скольких.
function Views.StatusTip(tt, now)
	now = now or ns.ServerTime()
	local st = Views.Status(now)
	tt:AddLine(st.big, 1, 0.82, 0)
	tt:AddLine(st.small, 0.7, 0.7, 0.7)
	local list = ns.Data.Summary(now)
	if #list > 0 then tt:AddLine(" ") end
	for _, s in ipairs(list) do
		if s.recent then
			local name = Codec.Plain(s.guild) .. (s.mine and (" " .. L.MINE_MARK) or "")
			local online = s.online and (GREEN .. U.Num(s.online) .. "|r") or (GREY .. "?|r")
			local r, g, b = 1, 1, 1
			if s.main then r, g, b = 1, 0.82, 0 end
			tt:AddDoubleLine(name, online .. GREY .. " / |r" .. U.Num(s.total or 0), r, g, b, 1, 1, 1)
		end
	end
	tt:AddLine(" ")
	tt:AddLine(L.HEAD_TIP_MORE, 0.6, 0.6, 0.6)
end

function Views.Census()
	local lines = {}
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
			text = GREY .. L.CENSUS_LEADER .. "|r " .. leader .. GREY .. ", " .. (s.mine and L.TIP_FROM_ROSTER or Views.Ago(s.age)) .. "|r",
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
		tt:AddLine(role .. ", " .. Codec.Plain(guild), 0.8, 0.8, 0.8)
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
-- Окно чата: строки сообщений и список людей справа
---------------------------------------------------------------------------
local ACTIVE_WINDOW = 3600 -- «писал за последний час»
local ROLE_ORDER = { leader = 0, officer = 1, member = 2, active = 3 }

-- Строка канала для окна: [время] [Имя] <Гильдия>: текст. Имя — ссылка player.
function Views.ChatLine(e, channel, showTime)
	local link = "|Hplayer:" .. (U.TellName(e.s) or "?") .. "|h[" .. Views.Name(e.s, e.c) .. "]|h"
	local guild = ""
	if not ns.Chat.GUILD_CHANNELS[channel] and e.g then guild = " " .. GREY .. "<" .. Codec.Plain(e.g) .. ">|r" end
	local stamp = (showTime and date) and (GREY .. date("%H:%M", e.t or 0) .. "|r ") or ""
	return stamp .. link .. guild .. ": " .. Codec.SanitizeChat(e.x)
end

local function ByRole(a, b)
	if ROLE_ORDER[a.role] ~= ROLE_ORDER[b.role] then return ROLE_ORDER[a.role] < ROLE_ORDER[b.role] end
	if a.role == "active" then return (a.wrote or 0) > (b.wrote or 0) end
	if (a.online and 1 or 0) ~= (b.online and 1 or 0) then return a.online and true or false end
	if (a.rank or 9) ~= (b.rank or 9) then return (a.rank or 9) < (b.rank or 9) end
	return a.name < b.name
end

-- Своя гильдия по ростеру: в G — кто в игре, в O — офицеры (в игре первыми).
local function GuildPeople(channel)
	local list = {}
	for _, m in ipairs(ns.Roster.members or {}) do
		local rank = m.rank or 9
		local officer = rank <= C.OFFICER_RANK
		if (channel == "G" and m.online) or (channel == "O" and officer) then
			list[#list + 1] = {
				name = U.Display(m.name), class = m.class, level = m.level, online = m.online, days = m.days,
				rank = rank, rankName = m.rankName, zone = m.zone, guild = ns.Roster.guild,
				role = rank == 0 and "leader" or (officer and "officer" or "member"),
			}
		end
	end
	table.sort(list, function(a, b)
		if (a.online and 1 or 0) ~= (b.online and 1 or 0) then return a.online and true or false end
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.name < b.name
	end)
	return list
end

-- Люди канала для правой панели: { header = true, guild, main, count } и строки людей
-- { name, class, level, online, days, role, guild, wrote }. Второе значение — сколько в сети.
-- Уровни «Чиллзон»: главы и офицеры гильдий из переписи (в «Главах» — только главы и офицеры
-- главной гильдии) плюс те, кто писал в канал за последний час.
function Views.People(channel, now)
	now = now or ns.ServerTime()
	local out, online = {}, 0
	local function add(p)
		out[#out + 1] = p
		if p.online then online = online + 1 end
	end
	if ns.Chat.GUILD_CHANNELS[channel] then
		for _, p in ipairs(GuildPeople(channel)) do add(p) end
		return out, online
	end
	local level = ns.Chat.TIER_LEVEL[channel] or 1
	local active, seen = {}, {}
	for _, e in ipairs(ns.Chat.History(channel)) do
		local k = U.Key(e.s)
		if k and now - (e.t or 0) <= ACTIVE_WINDOW then active[k] = e end
	end
	local groups, order = {}, {}
	local function group(guild, main)
		local gk = U.GuildKey(guild) or "?"
		if not groups[gk] then
			groups[gk] = { guild = guild, main = main, people = {} }
			order[#order + 1] = gk
		end
		return groups[gk]
	end
	for _, s in ipairs(ns.Data.Summary(now)) do
		if s.recent then
			local g = group(s.guild, s.main)
			local r = s.r
			local function person(p, role)
				local k = U.Key(p.name)
				if not k or seen[k] then return end
				seen[k] = true
				g.people[#g.people + 1] = {
					name = p.name, class = p.class, level = p.level, online = (s.fresh and p.online) and true or false,
					days = p.days, role = role, rank = p.rank, guild = s.guild, main = s.main, wrote = active[k] and active[k].t,
				}
			end
			if r.leader then person({ name = r.leader, class = r.leaderClass, level = r.leaderLevel, online = r.leaderOnline, days = r.leaderDays, rank = 0 }, "leader") end
			if level < 3 or s.main then
				for _, o in ipairs(r.officers or {}) do person(o, "officer") end
			end
		end
	end
	for k, e in pairs(active) do
		if not seen[k] then
			seen[k] = true
			local g = group(e.g or "?", U.IsMainGuild(e.g or ""))
			g.people[#g.people + 1] = { name = e.s, class = e.c, online = now - (e.t or 0) <= C.FRESH, role = "active", guild = e.g, wrote = e.t }
		end
	end
	for _, gk in ipairs(order) do
		local g = groups[gk]
		if #g.people > 0 then
			table.sort(g.people, ByRole)
			out[#out + 1] = { header = true, guild = g.guild, main = g.main, count = #g.people }
			for _, p in ipairs(g.people) do add(p) end
		end
	end
	return out, online
end

-- Подпись роли человека в списке справа.
function Views.Role(p)
	if p.role == "active" then return L.ROLE_ACTIVE end
	if p.rankName then return Codec.Plain(p.rankName) end -- своя гильдия: ранг из ростера
	if p.role == "leader" then return p.main and L.ROLE_KING or L.ROLE_LORD end
	if p.role == "officer" then return L.ROLE_CAPTAIN end
	return ""
end

function Views.PersonTip(tt, p)
	tt:AddLine(Views.Name(p.name, p.class))
	local role = Views.Role(p)
	tt:AddLine((role ~= "" and (role .. ", ") or "") .. Codec.Plain(p.guild or "?"), 0.8, 0.8, 0.8)
	if p.level and p.level > 0 then
		tt:AddLine(L.TIP_LEVEL:format(p.level) .. (p.class and L.CLASS[p.class] and (", " .. L.CLASS[p.class]) or ""), 0.8, 0.8, 0.8)
	end
	if p.zone and p.online then tt:AddLine(Codec.Plain(p.zone), 0.8, 0.8, 0.8) end
	if p.role ~= "active" then tt:AddLine(p.online and L.ONLINE or L.OFFLINE_DAYS:format(p.days or 0), 0.6, 0.6, 0.6) end
	if p.wrote then tt:AddLine(L.TIP_WROTE:format(Views.Ago(ns.ServerTime() - p.wrote)), 0.6, 0.6, 0.6) end
	tt:AddLine(L.TIP_CLICK_WHISPER, 0.5, 0.83, 0.76)
end

---------------------------------------------------------------------------
-- Кнопка у миникарты: подсказка
---------------------------------------------------------------------------
function Views.MinimapTip(tt)
	local status = Views.Status()
	tt:AddLine("Chillzone", 0.5, 0.83, 0.76)
	tt:AddLine(status.big, 1, 0.82, 0)
	tt:AddLine(status.small, 0.7, 0.7, 0.7)
	local tree = ns.Data.Kingdom()
	if tree.king then tt:AddLine(L.ROLE_KING .. ": " .. Views.Name(tree.king.leader, tree.king.leaderClass), 1, 0.82, 0) end
	tt:AddLine(" ")
	tt:AddLine(L.MINIMAP_LEFT, 0.6, 0.6, 0.6)
	tt:AddLine(L.MINIMAP_RIGHT, 0.6, 0.6, 0.6)
	tt:AddLine(L.MINIMAP_DRAG, 0.6, 0.6, 0.6)
end
