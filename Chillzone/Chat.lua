-- Chillzone: общий чат гильдий «Чиллзон». /cz1 — все, /cz2 — офицеры, /cz3 — главы
-- гильдий и офицеры главной гильдии. Строка уходит тремя путями (текст в скрытый канал,
-- M1 по GUILD, через реле), на приёме все три сходятся в Chat.Receive с дедупликацией.
-- Формат вывода и окно вывода — по образцу Olympus Channels.lua.
local ADDON, ns = ...

local U = ns.Util
local C = ns.Config
local Codec = ns.Codec
local L = ns.L

local Chat = {}
ns.Chat = Chat

Chat.TIER_LEVEL = { A = 1, C = 2, L = 3 }
Chat.TIER_COLOR = { A = "ff7fd4c1", C = "ff6fa8ff", L = "ffffb347" }
Chat.stats = { sent = 0, shown = 0, dupes = 0, refused = 0, limited = 0 }

local seen = {} -- [Key#id#text] = время
local buckets = {} -- [Key] = { n, t }
local tierMinute = {} -- [tier] = { n, t0 }
local lastSend = -1e9
local nextId = math.random(0, 9999)

---------------------------------------------------------------------------
-- Уровни
---------------------------------------------------------------------------

-- Уровень по рангу в гильдии: 3 — глава или офицер главной гильдии, 2 — офицер, 1 — участник.
function Chat.LevelOf(guild, rank)
	if rank == nil then return 1 end
	if rank == 0 then return 3 end
	if rank <= C.OFFICER_RANK then return U.IsMainGuild(guild) and 3 or 2 end
	return 1
end

function Chat.MyLevel()
	local g, rank = ns.MyGuild()
	if not g or not U.IsMemberGuild(g) then return 0 end
	return Chat.LevelOf(g, rank)
end

-- Уровень отправителя, насколько я могу его проверить. 0 — подделка.
function Chat.VerifiedLevel(guild, sender)
	local mine = ns.MyGuild()
	local myRank = ns.Roster.RankOf(sender)
	if mine and U.GuildKey(guild) == U.GuildKey(mine) then
		if myRank == nil then return 0 end -- назвался моей гильдией, но его нет в ростере
		return Chat.LevelOf(guild, myRank)
	end
	if myRank ~= nil then return 0 end -- согильдиец назвался другой гильдией
	return Chat.LevelOf(guild, ns.Data.KnownRank(guild, sender))
end

---------------------------------------------------------------------------
-- Вывод
---------------------------------------------------------------------------
local function WindowByName(name)
	if type(name) ~= "string" or name == "" then return nil end
	local info = GetChatWindowInfo or FCF_GetChatWindowInfo
	for i = 1, (tonumber(NUM_CHAT_WINDOWS) or 10) do
		local f = _G["ChatFrame" .. i]
		if type(f) == "table" and type(f.AddMessage) == "function" and type(info) == "function" then
			local ok, n = pcall(info, i)
			if ok and type(n) == "string" and U.Fold(n) == U.Fold(name) then return f end
		end
	end
	return nil
end

function Chat.Frame()
	local name = ns.char and ns.char.chatWindow
	return (name and WindowByName(name)) or DEFAULT_CHAT_FRAME
end

function Chat.Tag(tier)
	return "|c" .. Chat.TIER_COLOR[tier] .. "[" .. L["TIER_" .. tier] .. "]|r"
end

function Chat.Format(tier, guild, sender, class, text)
	local name = U.Display(sender)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color and color.colorStr then name = "|c" .. color.colorStr .. name .. "|r" end
	local g = Codec.Plain(guild or "?")
	return Chat.Tag(tier) .. " |cff999999<" .. g .. ">|r |Hplayer:" .. (U.TellName(sender) or "?") .. "|h[" .. name .. "]|h: " .. Codec.SanitizeChat(text)
end

local function Remember(tier, guild, sender, class, text)
	local list = ns.store and ns.store.chat[tier]
	if not list then return end
	list[#list + 1] = { t = ns.ServerTime(), s = U.Display(sender), g = guild, c = class, x = text }
	while #list > C.CHAT_HISTORY do table.remove(list, 1) end
end

function Chat.Show(tier, guild, sender, class, text)
	local f = Chat.Frame()
	if f then f:AddMessage(Chat.Format(tier, guild, sender, class, text)) end
	Chat.stats.shown = Chat.stats.shown + 1
	Remember(tier, guild, sender, class, text)
	ns.Fire("CHAT", tier)
end

---------------------------------------------------------------------------
-- Приём
---------------------------------------------------------------------------
local function Bucket(key, now)
	local b = buckets[key]
	if not b then
		b = { n = C.CHAT_BURST, t = now }
		buckets[key] = b
	end
	b.n = math.min(C.CHAT_BURST, b.n + (now - b.t) / C.CHAT_REFILL)
	b.t = now
	if b.n < 1 then return false end
	b.n = b.n - 1
	return true
end

local function TierOk(tier, now)
	local m = tierMinute[tier]
	if not m or now - m.t0 >= 60 then
		tierMinute[tier] = { n = 1, t0 = now }
		return true
	end
	m.n = m.n + 1
	return m.n <= C.CHAT_TIER_MIN
end

function Chat.Receive(msg, sender, dist)
	local d = Codec.DecodeChat(msg)
	if not d or ns.IsMe(sender) or not ns.IsMember() then return end
	if not U.IsMemberGuild(d.guild) then return end
	local key = U.Key(sender)
	if not key or (ns.store and ns.store.ignore[key]) then return end
	local mine = U.GuildKey(ns.MyGuild())
	local theirs = U.GuildKey(d.guild)
	if dist == "GUILD" and theirs ~= mine then return end -- по GUILD пишут только согильдийцы
	if dist == "RELAY" and theirs == mine then return end -- своя гильдия приходит напрямую
	local now = ns.Now()
	local dk = key .. "#" .. d.id .. "#" .. d.text
	if seen[dk] and now - seen[dk] <= C.CHAT_DEDUPE then
		Chat.stats.dupes = Chat.stats.dupes + 1
		return
	end
	seen[dk] = now
	local need = Chat.TIER_LEVEL[d.tier]
	if Chat.MyLevel() < need then return end -- не мой уровень
	if Chat.VerifiedLevel(d.guild, sender) < need then
		Chat.stats.refused = Chat.stats.refused + 1
		ns.Log("строка %s от %s <%s> отклонена: уровень не подтверждён", d.tier, U.Display(sender), d.guild)
		return
	end
	if not ns.char.chatOn then return end
	if not Bucket(key, now) or not TierOk(d.tier, now) then
		Chat.stats.limited = Chat.stats.limited + 1
		return
	end
	Chat.Show(d.tier, d.guild, sender, d.class, d.text)
end

ns.Comm.On("M1", Chat.Receive)

---------------------------------------------------------------------------
-- Отправка (синхронно, из слэш-команды: текст в канал требует аппаратного события)
---------------------------------------------------------------------------
function Chat.Send(tier, text)
	if not ns.me then return end
	local guild = ns.MyGuild()
	if not guild or not U.IsMemberGuild(guild) then
		ns.Print(L.CHAT_NOT_MEMBER)
		return
	end
	if Chat.MyLevel() < Chat.TIER_LEVEL[tier] then
		ns.Print(L.CHAT_NO_RIGHTS, L["TIER_" .. tier])
		return
	end
	text = Codec.SanitizeChat(text)
	if text == "" then
		ns.Print(L.CHAT_USAGE)
		return
	end
	local now = ns.Now()
	if now - lastSend < C.CHAT_GAP then
		ns.Print(L.CHAT_TOO_FAST)
		return
	end
	lastSend = now
	if not ns.char.warned then
		ns.char.warned = true
		ns.Print(L.CHAT_WARNING)
	end
	local _, class = UnitClass("player")
	local budget = math.min(C.CHAT_PART, Codec.ChatBudget(guild, Codec.CLASS_CODE[class or ""] or ""))
	local parts, cut = Codec.SplitChat(text, budget, C.CHAT_PARTS)
	for _, part in ipairs(parts) do
		nextId = (nextId + 1) % 10000
		local msg = Codec.EncodeChat(tier, guild, nextId, class, part)
		if msg then
			ns.Channel.Send(msg)
			ns.Comm.Send("GUILD", msg, { prio = true, logged = true })
			ns.Relay.Out("P", msg)
			seen[ns.myKey .. "#" .. nextId .. "#" .. part] = now
			Chat.Show(tier, guild, ns.me, class, part)
			Chat.stats.sent = Chat.stats.sent + 1
		end
	end
	ns.Comm.Flush(2)
	if cut then ns.Print(L.CHAT_CUT) end
end

for i, tier in ipairs({ "A", "C", "L" }) do
	_G["SLASH_CHILLZONE" .. tier .. "1"] = "/cz" .. i
	SlashCmdList["CHILLZONE" .. tier] = function(msg) ns.SafeCall("/cz" .. i, Chat.Send, tier, msg or "") end
end

---------------------------------------------------------------------------
-- Команды
---------------------------------------------------------------------------
ns.Command("chat", function(arg)
	arg = U.Fold(U.Trim(arg))
	if arg == "on" or arg == "вкл" then
		ns.char.chatOn = true
	elseif arg == "off" or arg == "выкл" then
		ns.char.chatOn = false
	end
	ns.Print(ns.char.chatOn and L.CHAT_ON or L.CHAT_OFF)
end, L.HELP_CHAT_TOGGLE)

ns.Command("window", function(arg)
	arg = U.Trim(arg)
	if arg == "" then
		ns.char.chatWindow = false
		ns.Print(L.CHAT_WINDOW_MAIN)
		return
	end
	if not WindowByName(arg) then
		ns.Print(L.CHAT_WINDOW_MISSING, arg)
		return
	end
	ns.char.chatWindow = arg
	ns.Print(L.CHAT_WINDOW_SET, arg)
end, L.HELP_WINDOW)

ns.Command("ignore", function(arg)
	arg = U.Trim(arg)
	if arg == "" then
		local names = {}
		for _, n in pairs(ns.store.ignore) do names[#names + 1] = n end
		table.sort(names)
		ns.Print(L.IGNORE_LIST, #names > 0 and table.concat(names, ", ") or "—")
		return
	end
	local k = U.Key(arg)
	if ns.store.ignore[k] then
		ns.store.ignore[k] = nil
		ns.Print(L.IGNORE_OFF, arg)
	else
		ns.store.ignore[k] = U.Display(arg)
		ns.Print(L.IGNORE_ON, arg)
	end
end, L.HELP_IGNORE)

ns.Command("history", function(arg)
	local tier = ({ ["1"] = "A", ["2"] = "C", ["3"] = "L" })[U.Trim(arg)] or "A"
	if Chat.MyLevel() < Chat.TIER_LEVEL[tier] then
		ns.Print(L.CHAT_NO_RIGHTS, L["TIER_" .. tier])
		return
	end
	local list = ns.store.chat[tier]
	local f = Chat.Frame()
	for i = math.max(1, #list - 19), #list do
		local e = list[i]
		f:AddMessage("|cff999999" .. (date and date("%H:%M", e.t) or "") .. "|r " .. Chat.Format(tier, e.g, e.s, e.c, e.x))
	end
end, L.HELP_HISTORY)

ns.Every(60, "chat gc", function()
	local now = ns.Now()
	for k, t in pairs(seen) do
		if now - t > C.CHAT_DEDUPE then seen[k] = nil end
	end
	for k, b in pairs(buckets) do
		if now - b.t > 60 then buckets[k] = nil end
	end
end)

ns.Status(function()
	local s = Chat.stats
	return L.STATUS_CHAT:format(Chat.MyLevel(), s.sent, s.shown, s.dupes, s.refused, s.limited)
end)
