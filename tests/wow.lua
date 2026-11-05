-- Симулятор мира WoW: Forever для тестов. Несколько клиентов, каждый со своим окружением
-- (setfenv) и своей копией аддона; гильдии, ростер, GUILD/WHISPER аддон-сообщения,
-- обычный текст в канале, системное «нет такого игрока», таймеры и общие часы.
local T = ...

local Wow = {}

local SERVER0 = 1793000000
local NOT_FOUND = "No player named '%s' is currently playing."

local World = {}
World.__index = World

function Wow.World()
	local w = setmetatable({ now = 0, timers = {}, seq = 0, clients = {}, guilds = {}, channels = {}, log = {}, channelDisabled = false }, World)
	return w
end

function World:Schedule(at, fn, client)
	self.seq = self.seq + 1
	self.timers[#self.timers + 1] = { at = at, fn = fn, seq = self.seq, client = client }
end

-- Часы идут до t, по пути срабатывают таймеры (в порядке времени).
function World:Run(seconds)
	local stop = self.now + seconds
	while true do
		local best, bi
		for i, t in ipairs(self.timers) do
			if t.at <= stop and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then best, bi = t, i end
		end
		if not best then break end
		table.remove(self.timers, bi)
		if best.at > self.now then self.now = best.at end
		if not best.client or best.client.online then best.fn() end
	end
	self.now = stop
end

---------------------------------------------------------------------------
-- Гильдии: участники — клиенты или просто строки ростера (не в игре)
---------------------------------------------------------------------------
function World:Guild(name, ranks)
	local g = { name = name, ranks = ranks or { "Глава", "Офицер", "Ветеран", "Рядовой" }, members = {} }
	self.guilds[name] = g
	return g
end

function World:AddOffline(guild, full, rank, level, class, days)
	local g = self.guilds[guild]
	g.members[#g.members + 1] = { full = full, rank = rank, level = level or 60, class = class or "WARRIOR", days = days or 3 }
end

local CLASS_LOCAL = { WARRIOR = "Воин", MAGE = "Маг", PRIEST = "Жрец", PALADIN = "Паладин", DRUID = "Друид", ROGUE = "Разбойник", HUNTER = "Охотник", WARLOCK = "Чернокнижник", SHAMAN = "Шаман" }

---------------------------------------------------------------------------
-- Клиент
---------------------------------------------------------------------------
local Client = {}
Client.__index = Client

local function Stamp(c)
	return c.first .. " " .. c.surname .. "-" .. c.realm
end

function World:FindByTell(name)
	for _, c in ipairs(self.clients) do
		if c.online and (c.first .. " " .. c.surname) == name then return c end
	end
	return nil
end

function World:Deliver(from, dist, prefix, msg, target, logged)
	local event = logged and "CHAT_MSG_ADDON_LOGGED" or "CHAT_MSG_ADDON"
	self.log[#self.log + 1] = { t = self.now, from = from.first .. " " .. from.surname, dist = dist, msg = msg, target = target }
	if dist == "GUILD" then
		local g = from.guild
		for _, c in ipairs(self.clients) do
			if c.online and c.guild == g then
				local stamp = Stamp(from)
				self:Schedule(self.now + 0.05, function() c:Fire(event, prefix, msg, "GUILD", stamp) end, c)
			end
		end
		return 0
	elseif dist == "WHISPER" then
		local to = self:FindByTell(target)
		if not to or (to.faction ~= from.faction) then
			self:Schedule(self.now + 0.05, function() from:Fire("CHAT_MSG_SYSTEM", NOT_FOUND:format(target)) end, from)
			return 0
		end
		local stamp = Stamp(from)
		self:Schedule(self.now + 0.05, function() to:Fire(event, prefix, msg, "WHISPER", stamp) end, to)
		return 0
	end
	return 4
end

function World:Say(from, msg, id)
	local chan = from.joinedById[id]
	if not chan or self.channelDisabled then return end
	self.log[#self.log + 1] = { t = self.now, from = from.first .. " " .. from.surname, dist = "CHANNEL", msg = msg }
	for _, c in ipairs(self.clients) do
		if c.online and c.joined[chan] then
			local stamp = Stamp(from)
			local cid = c.joined[chan]
			self:Schedule(self.now + 0.05, function() c:Fire("CHAT_MSG_CHANNEL", msg, stamp, "", cid .. ". " .. chan, "", "", 0, cid, chan) end, c)
		end
	end
end

-- Любое неизвестное поле кадра: и вызывается, и индексируется, ничего не делая.
local NOOP = setmetatable({}, { __call = function() return nil end })
getmetatable(NOOP).__index = function() return NOOP end

local function NewFrame(c)
	local f = { scripts = {}, shown = false }
	local methods = {}
	function methods.RegisterEvent(self, e)
		c.handlers[e] = c.handlers[e] or {}
		table.insert(c.handlers[e], self)
	end
	function methods.SetScript(self, k, fn) self.scripts[k] = fn end
	function methods.GetScript(self, k) return self.scripts[k] end
	function methods.HookScript(self, k, fn) self.scripts[k] = fn end
	function methods.IsShown(self) return self.shown end
	function methods.Show(self) self.shown = true end
	function methods.Hide(self) self.shown = false end
	function methods.CreateFontString() return NewFrame(c) end
	function methods.CreateTexture() return NewFrame(c) end
	return setmetatable(f, { __index = function(_, k) return methods[k] or NOOP end })
end

-- Окружение клиента: всё, к чему аддон обращается как к глобалам.
local function Env(c)
	local w = c.world
	local env = {}
	env._G = env
	env.GetTime = function() return w.now end
	env.GetServerTime = function() return SERVER0 + math.floor(w.now) + (c.clockSkew or 0) end
	env.time = env.GetServerTime
	env.date = os.date
	env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	env.tinsert = table.insert
	env.C_Timer = {
		After = function(s, fn) w:Schedule(w.now + s, fn, c) end,
		NewTicker = function(s, fn)
			local h = { cancelled = false }
			function h.Cancel() h.cancelled = true end
			local function tick()
				if h.cancelled then return end
				fn()
				w:Schedule(w.now + s, tick, c)
			end
			w:Schedule(w.now + s, tick, c)
			return h
		end,
	}
	env.CreateFrame = function() return NewFrame(c) end
	env.UnitFullName = function(unit) if unit == "player" then return c.first, c.surname end end
	env.GetNormalizedRealmName = function() return c.realm end
	env.GetRealmName = function() return c.realm end
	env.UnitFactionGroup = function() return c.faction end
	env.UnitClass = function() return CLASS_LOCAL[c.class], c.class end
	env.IsInGuild = function() return c.guild ~= nil end
	env.GetGuildInfo = function()
		if not c.guild then return nil end
		local g = w.guilds[c.guild]
		return c.guild, g.ranks[c.rank + 1], c.rank
	end
	local function Rows()
		local g = c.guild and w.guilds[c.guild]
		local rows = {}
		if not g then return rows end
		for _, o in ipairs(w.clients) do
			if o.guild == c.guild then
				rows[#rows + 1] = { full = Stamp(o), rank = o.rank, level = o.level, class = o.class, online = o.online, zone = o.zone, days = 0 }
			end
		end
		for _, m in ipairs(g.members) do rows[#rows + 1] = { full = m.full, rank = m.rank, level = m.level, class = m.class, online = false, days = m.days } end
		return rows
	end
	env.GetNumGuildMembers = function()
		local rows, on = Rows(), 0
		for _, r in ipairs(rows) do if r.online then on = on + 1 end end
		return #rows, on, on
	end
	env.GetGuildRosterInfo = function(i)
		local r = Rows()[i]
		if not r then return nil end
		local g = w.guilds[c.guild]
		return r.full, g.ranks[r.rank + 1], r.rank, r.level, CLASS_LOCAL[r.class], r.zone, "", "", r.online, 0, r.class
	end
	env.GetGuildRosterLastOnline = function(i)
		local r = Rows()[i]
		if not r or r.online then return nil end
		return 0, 0, math.floor(r.days or 0), 0
	end
	env.C_GuildInfo = { GuildRoster = function() w:Schedule(w.now + 0.2, function() c:Fire("GUILD_ROSTER_UPDATE") end, c) end }
	env.C_ChatInfo = {
		RegisterAddonMessagePrefix = function() return true end,
		SendAddonMessage = function(prefix, msg, dist, target)
			assert(#msg <= 255, "сообщение длиннее 255 байт")
			return w:Deliver(c, dist, prefix, msg, target, false)
		end,
		SendAddonMessageLogged = function(prefix, msg, dist, target)
			assert(#msg <= 255, "сообщение длиннее 255 байт")
			return w:Deliver(c, dist, prefix, msg, target, true)
		end,
		InChatMessagingLockdown = function() return c.lockdown == true end,
	}
	env.GetChannelName = function(id)
		if type(id) == "number" then
			for name, n in pairs(c.joined) do if n == id then return n, name end end
			return 0, nil
		end
		return c.joined[id] or 0, id
	end
	env.JoinChannelByName = function(name)
		c.nextChan = (c.nextChan or 4) + 1
		c.joined[name], c.joinedById[c.nextChan] = c.nextChan, name
	end
	env.LeaveChannelByName = function(name)
		local id = c.joined[name]
		if id then c.joinedById[id] = nil end
		c.joined[name] = nil
	end
	env.SendChatMessage = function(msg, kind, _, id)
		assert(kind == "CHANNEL")
		assert(#msg <= 255, "строка канала длиннее 255 байт")
		w:Say(c, msg, id)
	end
	env.ChatFrame_RemoveChannel = function() end
	env.ChatFrame_AddMessageEventFilter = function(event, fn)
		c.filters[event] = c.filters[event] or {}
		table.insert(c.filters[event], fn)
	end
	env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) c.printed[#c.printed + 1] = text end }
	env.NUM_CHAT_WINDOWS = 0
	env.SlashCmdList = {}
	env.UISpecialFrames = {}
	env.RAID_CLASS_COLORS = {}
	env.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
	c.stubs = {}
	for k in pairs(env) do c.stubs[k] = true end
	return setmetatable(env, { __index = _G })
end

-- opts: first, surname, realm, faction, guild, rank, class, level, zone, relays (Config.RELAYS)
function World:Client(opts)
	local c = setmetatable({
		world = self, first = opts.first, surname = opts.surname, realm = opts.realm or "CAMWOWUS2Realm7PvE",
		faction = opts.faction or "Alliance", guild = opts.guild, rank = opts.rank or 3, class = opts.class or "MAGE",
		level = opts.level or 60, zone = opts.zone or "Штормград", online = true,
		handlers = {}, filters = {}, printed = {}, joined = {}, joinedById = {},
	}, Client)
	c.env = Env(c)
	c.ns = {}
	for _, f in ipairs(T.tocFiles()) do
		if not f:find("^libs/") then
			T.load({ f }, c.env, c.ns)
			if f == "Config.lua" then c.ns.Config.RELAYS = opts.relays or {} end
		end
	end
	self.clients[#self.clients + 1] = c
	c:Fire("ADDON_LOADED", "Chillzone")
	c:Fire("PLAYER_LOGIN")
	return c
end

function Client:Fire(event, ...)
	for _, f in ipairs(self.handlers[event] or {}) do
		local fn = f.scripts.OnEvent
		if fn then fn(f, event, ...) end
	end
end

function Client:Name()
	return self.first .. " " .. self.surname
end

function Client:Slash(cmd, text)
	local key = ({ ["/cz"] = "CHILLZONE", ["/cz1"] = "CHILLZONEA", ["/cz2"] = "CHILLZONEC", ["/cz3"] = "CHILLZONEL" })[cmd]
	self.env.SlashCmdList[key](text or "")
end

function Client:Logout()
	self.online = false
	for i, c in ipairs(self.world.clients) do
		if c == self then
			table.remove(self.world.clients, i)
			break
		end
	end
end

-- Строки, которые клиент вывел в чат и которые содержат text.
function Client:Saw(text)
	local n = 0
	for _, line in ipairs(self.printed) do
		if line:find(text, 1, true) then n = n + 1 end
	end
	return n
end

-- Глобалы, которые аддон создал сам (кроме разрешённых).
function Client:Leaks()
	local out = {}
	for k in pairs(self.env) do
		if not self.stubs[k] and k ~= "ChillzoneDB" and not tostring(k):find("^SLASH_CHILLZONE") then out[#out + 1] = tostring(k) end
	end
	table.sort(out)
	return out
end

Wow.SERVER0 = SERVER0
return Wow
