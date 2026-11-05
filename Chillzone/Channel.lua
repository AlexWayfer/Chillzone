-- Chillzone: скрытый канал для текста чата. На Forever аддон-сообщения в канале не
-- доставляются, а обычный текст — доставляется между под-реалмами. Строка чата уходит
-- текстом "M1~..." (только из аппаратного события — Enter или слэш-команды).
-- Вход после General, скрытие из окон чата и KeepLast — из Olympus Comm.lua / ChatHall.lua.
local ADDON, ns = ...

local C = ns.Config
local U = ns.Util

local Channel = {}
ns.Channel = Channel

local JOIN_BY = 15 -- не позже стольких секунд после входа
local joined -- имя канала, в который вошли
local index = 0
Channel.stats = { sent = 0, heard = 0, echoed = 0 }

function Channel.Name()
	return C.CHANNEL[ns.faction or "Alliance"] or C.CHANNEL.Alliance
end

function Channel.Index()
	if not joined or not GetChannelName then return 0 end
	index = GetChannelName(joined) or 0
	return index
end

local function Hide(name)
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if cf and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, cf, name) end
	end
end

-- Наш канал — после каналов игры: если вошли раньше General, тот получил бы /2.
local function KeepLast()
	if not joined or not GetChannelList then return end
	local swap = C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex
	local infoOf = C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier
	if not swap or not infoOf then return end
	local ours = GetChannelName(joined) or 0
	if ours <= 0 then return end
	local list = { GetChannelList() }
	local stride = type(list[3]) == "boolean" and 3 or 2
	local after = {}
	for i = 1, #list, stride do
		local id = tonumber(list[i])
		local ok, info = pcall(infoOf, list[i + 1])
		if id and id > ours and ok and type(info) == "table" and (tonumber(info.zoneChannelID) or 0) > 0 then after[#after + 1] = id end
	end
	if #after == 0 then return end
	table.sort(after)
	local at = ours
	for _, id in ipairs(after) do
		if not pcall(swap, at, id) then break end
		at = id
	end
end

function Channel.Join()
	if not ns.IsMember() then return end
	local name = Channel.Name()
	joined = name
	local id = GetChannelName(name)
	if id and id > 0 then
		index = id
		Hide(name)
		return
	end
	ns.Log("вход в канал %s", name)
	JoinChannelByName(name)
	ns.After(3, "channel check", function()
		index = GetChannelName(name) or 0
		Hide(name)
		ns.SafeCall("channel last", KeepLast)
	end)
end

function Channel.Leave()
	if joined and GetChannelName(joined) > 0 then LeaveChannelByName(joined) end
	joined, index = nil, 0
end

local function JoinSoon(t, seenAt)
	local _, first = GetChannelName(1)
	if first and first ~= "" then seenAt = seenAt or t end
	if t >= JOIN_BY or (seenAt and t - seenAt >= 2) then
		Channel.Join()
		return
	end
	ns.After(1, "join channel", function() JoinSoon(t + 1, seenAt) end)
end

-- Отправка текста в канал. Вызывать только из обработчика слэш-команды.
function Channel.Send(msg)
	if type(msg) ~= "string" or msg:sub(1, 3) ~= "M1~" or #msg > 255 then return false end
	local id = Channel.Index()
	if id <= 0 then return false end
	local ok = pcall(SendChatMessage, msg, "CHANNEL", nil, id)
	if ok then Channel.stats.sent = Channel.stats.sent + 1 end
	return ok
end

local function Ours(baseName)
	return joined ~= nil and type(baseName) == "string" and U.Fold(baseName) == U.Fold(joined)
end

ns.RegisterEvent("CHAT_MSG_CHANNEL", function(text, sender, _, _, _, _, _, _, baseName)
	if not Ours(baseName) or type(text) ~= "string" or type(sender) ~= "string" then return end
	if text:sub(1, 3) ~= "M1~" or #text > 255 then return end
	sender = U.Normal(sender)
	if ns.IsMe(sender) then
		Channel.stats.echoed = Channel.stats.echoed + 1
		return
	end
	Channel.stats.heard = Channel.stats.heard + 1
	ns.Comm.Dispatch(text, sender, "CHANNEL", { via = "CHANNEL" })
end)

-- Строки канала и уведомления о нём не показываются ни в одном окне.
local function Filter(_, _, _, _, _, _, _, _, _, _, baseName)
	return Ours(baseName)
end
ns.AddChatFilter("CHAT_MSG_CHANNEL", Filter)
ns.AddChatFilter("CHAT_MSG_CHANNEL_NOTICE", Filter)
ns.AddChatFilter("CHAT_MSG_CHANNEL_NOTICE_USER", Filter)
ns.AddChatFilter("CHAT_MSG_CHANNEL_JOIN", Filter)
ns.AddChatFilter("CHAT_MSG_CHANNEL_LEAVE", Filter)

ns.On("LOGIN", function()
	ns.After(1, "join channel", function() JoinSoon(1, nil) end)
	ns.Every(60, "channel keep", function()
		if ns.IsMember() then
			if Channel.Index() <= 0 then Channel.Join() end
		elseif joined then
			Channel.Leave()
		end
	end)
end)

ns.On("GUILD_CHANGED", function()
	if ns.IsMember() then Channel.Join() else Channel.Leave() end
end)

ns.Status(function()
	local s = Channel.stats
	return ns.L.STATUS_CHANNEL:format(joined or "—", Channel.Index(), s.sent, s.heard, s.echoed)
end)
