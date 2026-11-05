-- Chillzone: ретрансляторы. На WoW: Forever аддон-сообщения в пользовательском канале не
-- доставляются, а GUILD и WHISPER доставляются. Поэтому данные между гильдиями ходят
-- шёпотом через реле: автор → реле (RL) → репортёр каждой гильдии (RM) → его гильдия (RG).
-- Схема — упрощённая версия Olympus Relay.lua.
local ADDON, ns = ...

local U = ns.Util
local C = ns.Config
local Codec = ns.Codec
local L = ns.L

local Relay = {}
ns.Relay = Relay

local known = {} -- [Key] = { key, name, verified, asked, down }: реле, о которых я знаю
local reporters = {} -- (я реле) [guildKey] = { name, key, t }
local regOf = {} -- (я реле) [Key репортёра] = guildKey
local seen = {} -- [ключ дедупа] = время
local rate = {} -- [Key автора] = { n, t0 }
local hold = {} -- сообщения, пока ни одно реле не ответило
local recent = {} -- [Key реле] = { { mode, inner, t } }: что ему недавно ушло (на случай офлайна)
local lastPong = {} -- [Key] = когда отвечали RY
Relay.stats = { forwarded = 0, delivered = 0, dropped = 0, untrusted = 0 }

local REG_TTL = 2 * C.REG_EVERY + 30
local WHISPER_FRESH = 10 -- системное «нет такого игрока» относится к шёпоту не старше

local function Now() return ns.Now() end

local function MyGuildKey()
	local g = ns.MyGuild()
	return g and U.GuildKey(g) or nil
end

-- Гильдия, от имени которой написано вложенное сообщение.
function Relay.InnerGuild(inner)
	return inner:match("^M1~%u~([^~]+)~") or inner:match("^R1~([^~]+)~")
end

local function Logged(inner)
	return Codec.InnerType(inner) == "M1"
end

---------------------------------------------------------------------------
-- Кто реле и кому я доверяю
---------------------------------------------------------------------------
local function IsSeed(key)
	for _, n in ipairs(C.RELAYS) do
		if U.Key(n) == key then return true end
	end
	return false
end

function Relay.IAmRelay()
	if not ns.myKey then return false end
	if IsSeed(ns.myKey) then return true end
	local g, rank = ns.MyGuild()
	return g ~= nil and U.IsMainGuild(g) and rank ~= nil and rank <= C.OFFICER_RANK
end

-- Откуда доверие к реле: "seed", "manual", "officer", "gossip" — или nil.
function Relay.TrustOf(name)
	local key = U.Key(name)
	if not key then return nil end
	if key == ns.myKey then return Relay.IAmRelay() and "self" or nil end
	if IsSeed(key) then return "seed" end
	local store = ns.store
	if store and store.manual[key] then return "manual" end
	local g = ns.MyGuild()
	if g and U.IsMainGuild(g) then
		local rank = ns.Roster.RankOf(name)
		if rank and rank <= C.OFFICER_RANK then return "officer" end
	end
	local l = store and store.relays[key]
	if l and ns.ServerTime() - (l.t or 0) <= C.RELAY_LEARNED_TTL then
		-- Выученное реле должно быть главой или офицером главной гильдии, если её отчёт известен.
		if ns.Data.IsMainLeader(name) == false then return nil end
		return "gossip"
	end
	return nil
end

local function Entry(key, name)
	local e = known[key]
	if not e then
		e = { key = key }
		known[key] = e
	end
	if name then e.name = U.TellName(name) end
	return e
end

-- Доверенные реле, кроме меня.
function Relay.Candidates()
	local out, added = {}, {}
	local function add(name)
		local k = U.Key(name)
		if not k or k == ns.myKey or added[k] or not Relay.TrustOf(name) then return end
		added[k] = true
		out[#out + 1] = Entry(k, name)
	end
	for _, n in ipairs(C.RELAYS) do add(n) end
	if ns.store then
		for _, n in pairs(ns.store.manual) do add(n) end
		for _, l in pairs(ns.store.relays) do add(l.name) end
	end
	for _, p in pairs(ns.Census.Peers()) do
		if p.r then add(p.name) end
	end
	return out
end

local function Usable(e, now)
	return not (e.down and now < e.down)
end

local function Verified(e, now)
	return e.verified ~= nil and now - e.verified <= C.RELAY_VERIFIED and Usable(e, now)
end

---------------------------------------------------------------------------
-- Пинги и офлайн
---------------------------------------------------------------------------
local Out -- вперёд

local function MarkDown(e, why)
	local now = Now()
	e.down, e.asked, e.verified = now + C.RELAY_DOWN, nil, nil
	ns.Log("реле %s недоступно: %s", e.name or e.key, why)
	-- Что ему недавно ушло, уходит через другое реле.
	local list = recent[e.key]
	recent[e.key] = nil
	for _, m in ipairs(list or {}) do
		if now - m.t <= 15 then Out(m.mode, m.inner) end
	end
	ns.Fire("RELAYS")
end

local function Ask(e, payload)
	local now = Now()
	if e.asked and now - e.asked < C.RELAY_TIMEOUT then return end
	e.asked = now
	ns.Comm.Send("WHISPER", payload, { target = e.name, prio = true, key = "ask:" .. e.key })
	local asked = now
	ns.After(C.RELAY_TIMEOUT + 1, "relay timeout", function()
		if e.asked == asked then MarkDown(e, "нет ответа") end
	end)
end

function Relay.PingAll()
	local now = Now()
	for _, e in ipairs(Relay.Candidates()) do
		if Usable(e, now) then Ask(e, "RP~") end
	end
end

-- Регистрация репортёра у каждого реле (RR). Реле отвечает RY — это и пинг.
function Relay.Register()
	local g = ns.MyGuild()
	if not g or not ns.Census.IsReporter() then return end
	local now = Now()
	Relay.lastRegister = now
	if Relay.IAmRelay() then
		-- Реле — репортёр своей гильдии: регистрируется у себя. Впервые — отдаёт гильдии всё,
		-- что уже знает (чужие отчёты могли прийти до того, как я стал репортёром).
		local gk = U.GuildKey(g)
		local prev = reporters[gk]
		local isNew = not prev or prev.key ~= ns.myKey or now - prev.t > REG_TTL
		reporters[gk], regOf[ns.myKey] = { name = ns.me, key = ns.myKey, t = now }, gk
		if isNew then
			for _, c in ipairs(ns.Data.Cached()) do
				ns.Comm.Send("GUILD", Codec.EncodeRM("RG", "L", c.origin, c.raw), { key = "rg:" .. c.key })
			end
		end
	end
	for _, e in ipairs(Relay.Candidates()) do
		if Usable(e, now) then Ask(e, "RR~" .. Codec.Clean(g)) end
	end
end

-- Перед отчётом: зарегистрироваться, если давно не регистрировался (новый репортёр).
function Relay.EnsureRegistered()
	if not Relay.lastRegister or Now() - Relay.lastRegister >= C.REG_EVERY - 10 then Relay.Register() end
end

-- Я реле: новому репортёру — всё, что я знаю о других гильдиях, чтобы перепись у его
-- гильдии сошлась сразу, а не через полчаса отчётов.
local function CatchUp(r, gk)
	for _, c in ipairs(ns.Data.Cached()) do
		if c.key ~= gk then
			ns.Comm.Send("WHISPER", Codec.EncodeRM("RM", "L", c.origin, c.raw), { target = r.name, key = "rm:" .. gk .. ":" .. c.key })
		end
	end
	local mine = MyGuildKey()
	local own = ns.Census.lastRaw
	if own and mine and mine ~= gk and ns.Census.IsReporter() then
		ns.Comm.Send("WHISPER", Codec.EncodeRM("RM", "L", U.Display(ns.me), own), { target = r.name, key = "rm:" .. gk .. ":" .. mine })
	end
end

---------------------------------------------------------------------------
-- Отправка от автора
---------------------------------------------------------------------------
local function Remember(key, mode, inner)
	local list = recent[key] or {}
	local now = Now()
	for i = #list, 1, -1 do
		if now - list[i].t > 15 then table.remove(list, i) end
	end
	list[#list + 1] = { mode = mode, inner = inner, t = now }
	while #list > 5 do table.remove(list, 1) end
	recent[key] = list
end

local function Hold(mode, inner)
	if mode == "L" then
		local t = Codec.InnerType(inner)
		for i = #hold, 1, -1 do
			if hold[i].mode == "L" and Codec.InnerType(hold[i].inner) == t then table.remove(hold, i) end
		end
	end
	hold[#hold + 1] = { mode = mode, inner = inner, t = Now() }
	while #hold > C.RELAY_HOLD do table.remove(hold, 1) end
end

local function FlushHold()
	if #hold == 0 then return end
	local list = hold
	hold = {}
	local now = Now()
	for _, m in ipairs(list) do
		if now - m.t <= C.RELAY_VERIFIED then Out(m.mode, m.inner) end
	end
end

-- Реле, через которое пойдёт сообщение моей гильдии сейчас: запись known или nil.
function Relay.Pick()
	local now = Now()
	local keys = {}
	for _, e in ipairs(Relay.Candidates()) do
		if Verified(e, now) then keys[#keys + 1] = e.key end
	end
	local pick = Codec.PickRelay(MyGuildKey() or "", keys, now, C.RELAY_WINDOW)
	return pick and known[pick] or nil
end

-- mode: "L" (отчёт: новый заменяет старый) или "P" (каждое: чат). inner: R1 или M1.
function Out(mode, inner)
	if not ns.IsMember() or not Codec.InnerType(inner) then return false end
	if Relay.IAmRelay() then
		Relay.HandleRL(ns.me, mode, inner)
		return true
	end
	local e = Relay.Pick()
	if not e then
		Hold(mode, inner)
		Relay.PingAll()
		return false
	end
	local key = mode == "L" and ("rl:" .. Codec.InnerType(inner)) or nil
	ns.Comm.Send("WHISPER", Codec.EncodeRL(mode, inner), { target = e.name, key = key, prio = mode == "P", logged = Logged(inner) })
	Remember(e.key, mode, inner)
	return true
end
Relay.Out = Out

---------------------------------------------------------------------------
-- Работа реле
---------------------------------------------------------------------------
local function Seen(dk, now)
	if seen[dk] and now - seen[dk] <= C.RELAY_DEDUPE then return true end
	seen[dk] = now
	return false
end

local function RateOk(okey, now)
	local r = rate[okey]
	if not r or now - r.t0 > 60 then
		rate[okey] = { n = 1, t0 = now }
		return true
	end
	r.n = r.n + 1
	return r.n <= C.RELAY_PER_MIN
end

-- Я реле: сообщение автора уходит репортёрам остальных гильдий.
function Relay.HandleRL(origin, mode, inner)
	local now = Now()
	local okey = U.Key(origin)
	local ig = Relay.InnerGuild(inner)
	if not okey or not ig or not U.IsMemberGuild(ig) then return end
	if not RateOk(okey, now) then
		Relay.stats.dropped = Relay.stats.dropped + 1
		return
	end
	if Seen(Codec.DedupeKey(okey, inner), now) then return end
	local igk = U.GuildKey(ig)
	local mine = MyGuildKey()
	if igk ~= mine then ns.Comm.Inject(inner, origin, { via = "RL" }) end
	for gk, r in pairs(reporters) do
		if now - r.t > REG_TTL then
			reporters[gk] = nil
			if regOf[r.key] == gk then regOf[r.key] = nil end
		elseif gk ~= igk then
			Relay.stats.forwarded = Relay.stats.forwarded + 1
			local key = mode == "L" and ("rm:" .. gk .. ":" .. okey .. ":" .. Codec.InnerType(inner)) or nil
			if r.key == ns.myKey then
				if gk == mine then
					ns.Comm.Send("GUILD", Codec.EncodeRM("RG", mode, U.Display(origin), inner), { key = key, prio = mode == "P", logged = Logged(inner) })
				end
			else
				ns.Comm.Send("WHISPER", Codec.EncodeRM("RM", mode, U.Display(origin), inner), { target = r.name, key = key, prio = mode == "P", logged = Logged(inner) })
			end
		end
	end
end

-- Доставка вложенного сообщения у получателя (RM — репортёр, RG — его гильдия).
local function Deliver(mode, origin, inner, ctx, toGuild)
	local now = Now()
	local okey = U.Key(origin)
	if not okey or Seen(Codec.DedupeKey(okey, inner), now) then return end
	local ig = Relay.InnerGuild(inner)
	if not ig or U.GuildKey(ig) == MyGuildKey() then return end -- своя гильдия приходит напрямую
	Relay.stats.delivered = Relay.stats.delivered + 1
	ns.Comm.Inject(inner, origin, ctx)
	if toGuild and ns.MyGuild() then
		local key = mode == "L" and ("rg:" .. okey .. ":" .. Codec.InnerType(inner)) or nil
		ns.Comm.Send("GUILD", Codec.EncodeRM("RG", mode, origin, inner), { key = key, prio = mode == "P", logged = Logged(inner) })
	end
end

local function GossipList(exceptKey)
	local now = Now()
	local out = {}
	for _, e in ipairs(Relay.Candidates()) do
		if #out >= C.RELAY_GOSSIP then break end
		if e.key ~= exceptKey and Usable(e, now) then out[#out + 1] = U.Display(e.name) end
	end
	return out
end

local function Pong(sender)
	local k = U.Key(sender)
	local now = Now()
	if lastPong[k] and now - lastPong[k] < 20 then return end
	lastPong[k] = now
	ns.Comm.Send("WHISPER", Codec.EncodeRelayList(GossipList(k)), { target = sender, prio = true, key = "ry:" .. k })
end

ns.Comm.On("RP", function(_, sender, dist)
	if dist ~= "WHISPER" or not Relay.IAmRelay() then return end
	Pong(sender)
end)

ns.Comm.On("RR", function(msg, sender, dist)
	if dist ~= "WHISPER" or not Relay.IAmRelay() then return end
	local guild = msg:match("^RR~(.+)$")
	if not guild or not U.IsMemberGuild(guild) or Codec.LongGuild(guild) then return end
	local gk, k = U.GuildKey(guild), U.Key(sender)
	local now = Now()
	local old = regOf[k]
	if old and old ~= gk and reporters[old] and reporters[old].key == k then reporters[old] = nil end
	local prev = reporters[gk]
	local isNew = not prev or prev.key ~= k or now - prev.t > REG_TTL
	reporters[gk], regOf[k] = { name = sender, key = k, t = now }, gk
	Pong(sender)
	if isNew then CatchUp(reporters[gk], gk) end
end)

ns.Comm.On("RY", function(msg, sender, dist)
	if dist ~= "WHISPER" then return end
	if not Relay.TrustOf(sender) then
		Relay.stats.untrusted = Relay.stats.untrusted + 1
		return
	end
	local e = Entry(U.Key(sender), sender)
	e.verified, e.asked, e.down = Now(), nil, nil
	-- Выучить реле из ответа.
	local store = ns.store
	local changed = false
	for _, name in ipairs(Codec.DecodeRelayList(msg, C.RELAY_GOSSIP) or {}) do
		local k = U.Key(name)
		if k and k ~= ns.myKey and not Relay.TrustOf(name) and ns.Data.IsMainLeader(name) ~= false then
			store.relays[k] = { name = name, t = ns.ServerTime(), by = e.key }
			changed = true
		elseif k and store.relays[k] then
			store.relays[k].t = ns.ServerTime()
		end
	end
	if changed then Relay.PruneLearned() end
	FlushHold()
	ns.Fire("RELAYS")
end)

ns.Comm.On("RL", function(msg, sender, dist)
	if dist ~= "WHISPER" or not Relay.IAmRelay() then return end
	local kind, mode, _, inner = Codec.DecodeRelay(msg)
	if kind ~= "RL" then return end
	Relay.HandleRL(sender, mode, inner)
end)

ns.Comm.On("RM", function(msg, sender, dist)
	if dist ~= "WHISPER" then return end
	if not Relay.TrustOf(sender) then
		Relay.stats.untrusted = Relay.stats.untrusted + 1
		return
	end
	local kind, mode, origin, inner = Codec.DecodeRelay(msg)
	if kind ~= "RM" then return end
	local e = Entry(U.Key(sender), sender)
	e.verified, e.down = Now(), nil
	Deliver(mode, origin, inner, { via = "RM", relay = sender }, true)
end)

ns.Comm.On("RG", function(msg, sender, dist)
	if dist ~= "GUILD" then return end
	local kind, mode, origin, inner = Codec.DecodeRelay(msg)
	if kind ~= "RG" then return end
	Deliver(mode, origin, inner, { via = "RG", relay = sender }, false)
end)

---------------------------------------------------------------------------
-- Выученные реле: не дольше 14 дней, не больше 12.
---------------------------------------------------------------------------
function Relay.PruneLearned()
	local store = ns.store
	if not store then return end
	local now = ns.ServerTime()
	local list = {}
	for k, l in pairs(store.relays) do
		if type(l) ~= "table" or not l.name or now - (l.t or 0) > C.RELAY_LEARNED_TTL then
			store.relays[k] = nil
		else
			list[#list + 1] = { k = k, t = l.t }
		end
	end
	table.sort(list, function(a, b) return a.t > b.t end)
	for i = C.RELAY_LEARNED_MAX + 1, #list do store.relays[list[i].k] = nil end
end

---------------------------------------------------------------------------
-- «Нет такого игрока» после шёпота реле: реле офлайн, строка скрывается.
---------------------------------------------------------------------------
local notFound
local function NotFound(text)
	if type(text) ~= "string" then return nil end
	if type(issecretvalue) == "function" and issecretvalue(text) then return nil end
	if not notFound then
		local f = type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" and ERR_CHAT_PLAYER_NOT_FOUND_S or nil
		if not f then return nil end
		notFound = "^" .. (f:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)")) .. "$"
	end
	return text:match(notFound)
end

local function OursNotFound(text)
	local who = NotFound(text)
	if not who then return nil end
	local k = U.Key(who)
	local t = k and ns.Comm.lastWhisper[k]
	if t and Now() - t <= WHISPER_FRESH and known[k] then return known[k] end
	return nil
end

ns.RegisterEvent("CHAT_MSG_SYSTEM", function(text)
	local e = OursNotFound(text)
	if e then MarkDown(e, "не в игре") end
end)

if ChatFrame_AddMessageEventFilter then
	ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, text)
		return OursNotFound(text) ~= nil
	end)
end

---------------------------------------------------------------------------
-- Расписание, команды, статус
---------------------------------------------------------------------------
ns.On("LOGIN", function()
	Relay.PruneLearned()
	ns.After(20, "relay first ping", function()
		if ns.IsMember() and not Relay.IAmRelay() then Relay.PingAll() end
	end)
	ns.Every(C.REG_EVERY, "relay register", function()
		if not ns.IsMember() then return end
		if ns.Census.IsReporter() then
			Relay.EnsureRegistered()
		elseif not Relay.IAmRelay() and not Relay.Pick() then
			Relay.PingAll()
		end
	end)
	ns.Every(60, "relay gc", function()
		local now = Now()
		for k, t in pairs(seen) do
			if now - t > C.RELAY_DEDUPE then seen[k] = nil end
		end
		for k, t in pairs(lastPong) do
			if now - t > 60 then lastPong[k] = nil end
		end
	end)
end)

-- Для тестов и окна.
function Relay.Known() return known end
function Relay.Reporters() return reporters end
function Relay.HoldSize() return #hold end

local function StateOf(e, now)
	if e.down and now < e.down then return L.RELAY_DOWN end
	if Verified(e, now) then return L.RELAY_OK end
	if e.asked then return L.RELAY_ASKED end
	return L.RELAY_UNKNOWN
end

ns.Command("relay", function(arg)
	local cmd, name = U.Trim(arg):match("^(%S*)%s*(.-)$")
	cmd = U.Fold(cmd or "")
	name = U.Trim(name)
	local store = ns.store
	if cmd == "add" and name ~= "" then
		store.manual[U.Key(name)] = name
		ns.Print(L.RELAY_ADDED, name)
		Relay.PingAll()
		return
	elseif (cmd == "del" or cmd == "remove") and name ~= "" then
		local k = U.Key(name)
		store.manual[k], store.relays[k], known[k] = nil, nil, nil
		ns.Print(L.RELAY_REMOVED, name)
		return
	elseif cmd == "ping" then
		for _, e in pairs(known) do e.down, e.asked = nil, nil end
		Relay.PingAll()
		ns.Print(L.RELAY_PINGING)
		return
	end
	local now = Now()
	ns.Print(Relay.IAmRelay() and L.RELAY_I_AM or L.RELAY_I_AM_NOT)
	local list = Relay.Candidates()
	if #list == 0 then ns.Print(L.RELAY_NONE) end
	for _, e in ipairs(list) do
		ns.Print("  %s — %s (%s)", U.Display(e.name), StateOf(e, now), Relay.TrustOf(e.name) or "?")
	end
	if Relay.IAmRelay() then
		local n = 0
		for gk, r in pairs(reporters) do
			if now - r.t <= REG_TTL then
				n = n + 1
				ns.Print("  " .. L.RELAY_REPORTER, gk, U.Display(r.name))
			end
		end
		if n == 0 then ns.Print("  " .. L.RELAY_NO_REPORTERS) end
	end
end, L.HELP_RELAY)

ns.Status(function()
	local now = Now()
	local ok, total = 0, 0
	for _, e in ipairs(Relay.Candidates()) do
		total = total + 1
		if Verified(e, now) then ok = ok + 1 end
	end
	local pick = Relay.Pick()
	return L.STATUS_RELAY:format(Relay.IAmRelay() and L.YES or L.NO, ok, total, pick and U.Display(pick.name) or "—", #hold)
end)
