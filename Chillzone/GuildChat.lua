-- Chillzone: чат своей гильдии и офицерский чат гильдии в окне Chillzone. Строки берутся из
-- обычных событий игры (CHAT_MSG_GUILD / CHAT_MSG_OFFICER), хранятся по 100 на персонажа и
-- уходят событием CHAT в окно. В чат игры аддон их не пишет — это делает сама игра.
local ADDON, ns = ...

local U = ns.Util
local C = ns.Config
local L = ns.L

local GuildChat = {}
ns.GuildChat = GuildChat

-- Может ли персонаж писать в офицерский чат гильдии.
function GuildChat.CanOfficer()
	local g, rank = ns.MyGuild()
	if not g then return false end
	local info = rawget(_G, "C_GuildInfo")
	local can = type(info) == "table" and info.CanSpeakInOfficerChat
	if type(can) == "function" then
		local ok, yes = pcall(can)
		if ok and yes ~= nil then return yes and true or false end
	end
	return rank ~= nil and rank <= C.OFFICER_RANK
end

-- Класс автора: по GUID из события, иначе по ростеру.
local function ClassOf(sender, guid)
	local byGuid = rawget(_G, "GetPlayerInfoByGUID")
	if guid and guid ~= "" and type(byGuid) == "function" then
		local ok, _, class = pcall(byGuid, guid)
		if ok and class then return class end
	end
	local key = U.Key(sender)
	for _, m in ipairs(ns.Roster.members or {}) do
		if m.key == key then return m.class end
	end
	return nil
end

function GuildChat.Receive(channel, text, sender, guid)
	if not ns.char or type(text) ~= "string" or type(sender) ~= "string" then return end
	ns.Chat.Remember(channel, ns.MyGuild(), sender, ClassOf(sender, guid), text)
end

-- Строка в чат гильдии (G) или офицеров гильдии (O). true — ушла.
function GuildChat.Send(channel, text)
	if not ns.MyGuild() then
		ns.Print(L.GUILD_NONE)
		return false
	end
	if channel == "O" and not GuildChat.CanOfficer() then
		ns.Print(L.GUILD_NO_OFFICER)
		return false
	end
	text = U.Cut(U.Trim(text), 255)
	if text == "" then return false end
	SendChatMessage(text, channel == "O" and "OFFICER" or "GUILD")
	return true
end

-- История принадлежит гильдии: сменил гильдию — старые строки не показываем.
local function CheckGuild()
	local g = ns.MyGuild()
	if not g or not ns.char then return end
	if ns.char.historyGuild ~= g then
		ns.char.history.G, ns.char.history.O = {}, {}
		ns.char.historyGuild = g
	end
end

ns.RegisterEvent("CHAT_MSG_GUILD", function(text, sender, ...)
	local guid = select(10, ...)
	GuildChat.Receive("G", text, sender, guid)
end)
ns.RegisterEvent("CHAT_MSG_OFFICER", function(text, sender, ...)
	local guid = select(10, ...)
	GuildChat.Receive("O", text, sender, guid)
end)
ns.On("ROSTER", CheckGuild)
ns.On("GUILD_CHANGED", CheckGuild)
