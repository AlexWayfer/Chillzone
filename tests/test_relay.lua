-- Интеграция: три гильдии, реле, перепись, чат — в симуляторе мира.
local T = ...
local Wow = assert(loadfile(T.ROOT .. "/tests/wow.lua"))(T)

local RELAY = { "Арагорн Светлый" }
local LINK = "|cffa335ee|Hitem:19019::::::::60:::::|h[Громосвёрт, Благословенный клинок Искателя Ветра]|h|r"

local function Build(opts)
	opts = opts or {}
	math.randomseed(opts.seed or tonumber(os.getenv("CZ_SEED") or "") or 7)
	local w = Wow.World()
	w.channelDisabled = opts.noChannel or false
	w:Guild("Чиллзон")
	w:Guild("Чиллзон Север")
	w:Guild("Орден Чиллзона")
	w:AddOffline("Чиллзон", "Старый Воин-CAMWOWUS2Realm3PvE", 3, 60, "WARRIOR", 40)
	w:AddOffline("Чиллзон Север", "Тихий Друид-CAMWOWUS2Realm7PvE", 3, 41, "DRUID", 2)
	for i = 1, (opts.officers or 0) do
		w:AddOffline("Орден Чиллзона", ("Офицерскийперсонаж%02d Длиннофамильный-CAMWOWUS2Realm3PvE"):format(i), 1, 60, "PRIEST", i)
	end
	local c = {}
	c.A = w:Client({ first = "Арагорн", surname = "Светлый", guild = "Чиллзон", rank = 1, zone = "Штормград" })
	c.K = w:Client({ first = "Карл", surname = "Великий", guild = "Чиллзон", rank = 0, realm = "CAMWOWUS2Realm3PvE", class = "PALADIN" })
	c.M = w:Client({ first = "Мира", surname = "Тихая", guild = "Чиллзон", rank = 3, class = "PRIEST" })
	c.B = w:Client({ first = "Борис", surname = "Быстрый", guild = "Чиллзон Север", rank = 2, relays = RELAY, class = "WARRIOR", zone = "Тернистая долина" })
	c.V = w:Client({ first = "Вера", surname = "Верная", guild = "Чиллзон Север", rank = 0, relays = RELAY, realm = "CAMWOWUS2Realm5PvE", class = "DRUID" })
	c.G = w:Client({ first = "Глеб", surname = "Гордый", guild = "Орден Чиллзона", rank = 0, relays = RELAY, class = "HUNTER" })
	w:Run(opts.run or 400)
	return w, c
end

local function Key(c, name) return c.ns.Util.Key(name) end

T.test("relay: глобалы не утекают", function()
	local _, c = Build({ run = 5 })
	for name, cl in pairs(c) do
		local leaks = cl:Leaks()
		T.eq(#leaks, 0, name .. ": утечки " .. table.concat(leaks, ", "))
	end
end)

T.test("relay: выборы репортёра одинаковы у всех", function()
	local _, c = Build()
	T.eq(c.B.ns.Census.Reporter(), Key(c.B, "Борис Быстрый"), "Север у Бориса")
	T.eq(c.V.ns.Census.Reporter(), Key(c.V, "Борис Быстрый"), "Север у Веры")
	T.ok(c.B.ns.Census.IsReporter(), "Борис репортёр")
	T.eq(c.M.ns.Census.Reporter(), Key(c.M, "Арагорн Светлый"), "главная")
	T.ok(c.A.ns.Relay.IAmRelay() and c.K.ns.Relay.IAmRelay(), "офицеры главной — реле")
	T.no(c.B.ns.Relay.IAmRelay(), "Борис не реле")
end)

T.test("relay: согласие делиться зонами переключает репортёра", function()
	local w, c = Build()
	c.V:Slash("/cz", "zones on")
	w:Run(200)
	T.eq(c.B.ns.Census.Reporter(), Key(c.B, "Вера Верная"), "у Бориса")
	T.eq(c.V.ns.Census.Reporter(), Key(c.V, "Вера Верная"), "у Веры")
	w:Run(200)
	local row = c.G.ns.Data.Row("Чиллзон Север")
	T.ok(row and next(row.r.zones), "зоны Севера видны после согласия")
	local main = c.G.ns.Data.Row("Чиллзон")
	T.eq(next(main.r.zones), nil, "зон главной гильдии без согласия нет")
end)

T.test("relay: перепись сходится у всех", function()
	local _, c = Build()
	for name, cl in pairs(c) do
		local mine = cl.ns.MyGuild()
		for _, g in ipairs({ "Чиллзон", "Чиллзон Север", "Орден Чиллзона" }) do
			local row = cl.ns.Data.Row(g)
			T.ok(row and row.r, name .. " знает " .. g)
			T.eq(row.mine == true, g == mine, name .. ": своя гильдия только из ростера, " .. g)
		end
	end
	local row = c.G.ns.Data.Row("Чиллзон")
	T.eq(row.r.leader, "Карл Великий", "глава главной")
	T.eq(row.r.total, 4, "численность главной")
	T.eq(row.r.online, 3, "онлайн главной")
	local tree = c.G.ns.Data.Kingdom()
	T.ok(tree.king and tree.king.leader == "Карл Великий", "король")
	T.eq(c.B.ns.Data.KnownRank("Чиллзон", "Арагорн Светлый"), 1, "ранг офицера главной")
	T.eq(c.B.ns.Data.KnownRank("Орден Чиллзона", "Глеб Гордый-CAMWOWUS2Realm7PvE"), 0, "ранг главы")
end)

T.test("relay: реле выучено из ответа доверенного реле", function()
	local _, c = Build()
	local learned = c.B.ns.store.relays[Key(c.B, "Карл Великий")]
	T.ok(learned, "Карл выучен")
	T.eq(c.B.ns.Relay.TrustOf("Карл Великий"), "gossip", "доверие")
	T.eq(c.B.ns.Relay.TrustOf("Мира Тихая"), nil, "не офицер — не реле")
end)

T.test("relay: строка чата доходит один раз до всех (канал + GUILD + реле)", function()
	local w, c = Build()
	local text = "всем привет " .. LINK
	c.B:Slash("/cz1", text)
	w:Run(30)
	for name, cl in pairs(c) do T.eq(cl:Saw(text), 1, name .. " видит один раз") end
end)

T.test("relay: без канала чат идёт через реле, ссылка цела", function()
	local w, c = Build({ noChannel = true })
	local text = "только через реле " .. LINK
	c.B:Slash("/cz1", text)
	w:Run(30)
	for name, cl in pairs(c) do T.eq(cl:Saw(text), 1, name .. " видит один раз") end
end)

T.test("relay: реле пишет само — без шёпота RL", function()
	local w, c = Build({ noChannel = true })
	local text = "слово реле"
	c.A:Slash("/cz1", text)
	w:Run(30)
	for _, e in ipairs(w.log) do
		T.no(e.from == "Арагорн Светлый" and e.dist == "WHISPER" and e.msg:find("^RL~"), "реле не шепчет RL себе")
	end
	for name, cl in pairs(c) do T.eq(cl:Saw(text), 1, name .. " видит") end
end)

T.test("relay: уровни чата — офицеры и главы", function()
	local w, c = Build({ noChannel = true })
	c.B:Slash("/cz2", "можно мне?")
	T.ok(c.B:Saw("можно писать только") >= 1, "Борису отказано")
	w:Run(5)
	c.V:Slash("/cz2", "офицерам привет")
	w:Run(30)
	for _, n in ipairs({ "A", "K", "G", "V" }) do T.eq(c[n]:Saw("офицерам привет"), 1, n .. " видит офицерский") end
	T.eq(c.M:Saw("офицерам привет"), 0, "рядовой не видит")
	T.eq(c.B:Saw("офицерам привет"), 0, "не офицер не видит")
	c.G:Slash("/cz3", "главам слово")
	w:Run(30)
	for _, n in ipairs({ "A", "K", "V", "G" }) do T.eq(c[n]:Saw("главам слово"), 1, n .. " видит") end
	T.eq(c.B:Saw("главам слово"), 0, "Борис не видит")
end)

T.test("relay: подделка в канале отклоняется", function()
	local w, c = Build()
	local B = c.B
	-- Чужак пишет в канал от имени Севера и уровнем глав.
	local fake = w:Client({ first = "Чужак", surname = "Хитрый", guild = nil, rank = 3 })
	fake.joined["ChillzoneA"], fake.joinedById[9] = 9, "ChillzoneA"
	local msg1 = B.ns.Codec.EncodeChat("A", "Чиллзон Север", 77, "MAGE", "я из Севера")
	local msg2 = B.ns.Codec.EncodeChat("L", "Орден Чиллзона", 78, "MAGE", "я глава Ордена")
	w:Say(fake, msg1, 9)
	w:Say(fake, msg2, 9)
	w:Run(5)
	T.eq(B:Saw("я из Севера"), 0, "назвался моей гильдией, но не в ростере")
	T.eq(c.A:Saw("я глава Ордена"), 0, "уровень глав без подтверждения")
end)

T.test("relay: длинный отчёт (несколько кусков) доходит целым", function()
	local w, c = Build({ officers = 30, run = 500 })
	local chunked = false
	for _, e in ipairs(w.log) do
		if e.from == "Глеб Гордый" and e.msg:find("^C") then chunked = true end
	end
	T.ok(chunked, "отчёт шёл кусками")
	local ref = c.A.ns.Data.Row("Орден Чиллзона")
	T.ok(ref and #ref.r.officers == 30, "30 офицеров у реле")
	for _, n in ipairs({ "K", "M", "B", "V" }) do
		local row = c[n].ns.Data.Row("Орден Чиллзона")
		T.ok(row, n .. " получил")
		T.eq(row.raw, ref.raw, n .. ": байт в байт")
	end
end)

T.test("relay: реле вышло из игры — сообщение уходит через другое", function()
	local w, c = Build({ noChannel = true })
	local pick = c.B.ns.Relay.Pick()
	T.ok(pick, "у Бориса есть реле")
	local gone = (pick.name == "Арагорн Светлый") and c.A or c.K
	local other = (gone == c.A) and c.K or c.A
	gone:Logout()
	local text = "реле ушло, а я пишу"
	c.B:Slash("/cz1", text)
	w:Run(60)
	T.ok(c.B.ns.Relay.Known()[pick.key].down, "ушедшее реле помечено")
	T.eq(c.G:Saw(text), 1, "Глеб видит")
	T.eq(other:Saw(text), 1, "второе реле видит")
	local hidden = false
	for _, fn in ipairs(c.B.filters["CHAT_MSG_SYSTEM"] or {}) do
		if fn(nil, "CHAT_MSG_SYSTEM", ("No player named '%s' is currently playing."):format(pick.name)) then hidden = true end
	end
	T.no(hidden, "через 60 с строка уже не скрывается")
end)

T.test("relay: Q1 после /reload восполняет перепись", function()
	local w, c = Build()
	-- Мира перезаходит с пустыми данными.
	c.M:Logout()
	local M2 = w:Client({ first = "Мира", surname = "Тихая", guild = "Чиллзон", rank = 3, class = "PRIEST" })
	T.eq(M2.ns.Data.Row("Орден Чиллзона"), nil, "сначала пусто")
	w:Run(40)
	T.ok(M2.ns.Data.Row("Орден Чиллзона"), "Орден пришёл по Q1")
	T.ok(M2.ns.Data.Row("Чиллзон Север"), "Север пришёл по Q1")
end)

T.test("relay: команды, окно и вкладки без ошибок", function()
	local w, c = Build()
	for _, cmd in ipairs({ "", "help", "status", "relay", "relay ping", "zones", "chat", "chat off", "chat on", "history 1", "history 3", "map off", "map on", "minimap", "minimap", "kingdom", "census", "ignore", "log 5", "debug", "debug", "нетакой" }) do
		c.B:Slash("/cz", cmd)
		c.A:Slash("/cz", cmd)
	end
	c.B:Slash("/cz", "ignore Глеб Гордый")
	c.G:Slash("/cz1", "меня не видно")
	w:Run(30)
	T.eq(c.B:Saw("меня не видно"), 0, "игнор работает")
	T.eq(c.A:Saw("меня не видно"), 1, "у других видно")
	c.B.ns.Map.RefreshNow()
	local census = c.B.ns.Views.CensusRows()
	local kingdom = c.B.ns.Views.Kingdom()
	local function has(lines, text)
		for _, l in ipairs(lines) do
			if (l.text or ""):find(text, 1, true) then return true end
		end
		return false
	end
	T.ok(has(census, "Орден Чиллзона") and has(census, "Чиллзон Север"), "перепись")
	T.ok(has(kingdom, "Карл Великий") and has(kingdom, "Глеб Гордый") and has(kingdom, "Вера Верная"), "королевство")
	T.ok(has(kingdom, "Арагорн Светлый"), "капитан короля")
	for _, l in ipairs(census) do
		if l.tip then l.tip(setmetatable({}, { __index = function() return function() end end })) end
	end
	for name, cl in pairs(c) do
		local errors = cl.ns.db.errors
		T.eq(#errors, 0, name .. ": ошибки " .. table.concat(errors, " | "))
	end
end)
