-- Окно чата: каналы по рангу, отправка из поля ввода, чат гильдии, метка-ссылка, люди справа,
-- непрочитанные, Enter при открытом окне — в симуляторе мира.
local T = ...
local Wow = assert(loadfile(T.ROOT .. "/tests/wow.lua"))(T)

local RELAY = { "Арагорн Светлый" }
local LINK = "|cffa335ee|Hitem:19019::::::::60:::::|h[Громосвёрт, Благословенный клинок Искателя Ветра]|h|r"

local function Build(opts)
	opts = opts or {}
	math.randomseed(tonumber(os.getenv("CZ_SEED") or "") or 11)
	local w = Wow.World()
	w:Guild("Чиллзон")
	w:Guild("Чиллзон Север")
	w:Guild("Орден Чиллзона")
	w:AddOffline("Чиллзон Север", "Тихий Друид-CAMWOWUS2Realm7PvE", 3, 41, "DRUID", 2)
	w:AddOffline("Орден Чиллзона", "Офицер Ордена-CAMWOWUS2Realm3PvE", 1, 60, "PRIEST", 1)
	local c = {}
	c.A = w:Client({ first = "Арагорн", surname = "Светлый", guild = "Чиллзон", rank = 1 })
	c.K = w:Client({ first = "Карл", surname = "Великий", guild = "Чиллзон", rank = 0, class = "PALADIN" })
	c.M = w:Client({ first = "Мира", surname = "Тихая", guild = "Чиллзон", rank = 3, class = "PRIEST" })
	c.B = w:Client({ first = "Борис", surname = "Быстрый", guild = "Чиллзон Север", rank = 2, relays = RELAY, class = "WARRIOR" })
	c.V = w:Client({ first = "Вера", surname = "Верная", guild = "Чиллзон Север", rank = 0, relays = RELAY, class = "DRUID" })
	c.G = w:Client({ first = "Глеб", surname = "Гордый", guild = "Орден Чиллзона", rank = 0, relays = RELAY, class = "HUNTER" })
	w:Run(opts.run or 400)
	return w, c
end

local function Has(lines, text)
	local n = 0
	for _, l in ipairs(lines) do
		if l:find(text, 1, true) then n = n + 1 end
	end
	return n
end

local function HistoryHas(cl, channel, text)
	local n = 0
	for _, e in ipairs(cl.ns.Chat.History(channel)) do
		if e.x:find(text, 1, true) then n = n + 1 end
	end
	return n
end

local function Errors(c)
	for name, cl in pairs(c) do
		local errors = cl.ns.db.errors
		T.eq(#errors, 0, name .. ": ошибки " .. table.concat(errors, " | "))
	end
end

T.test("окно: каналы по рангу", function()
	local _, c = Build({ run = 60 })
	local function chans(cl) return table.concat(cl.ns.Chat.Channels(), ",") end
	T.eq(chans(c.M), "G,A", "рядовой главной")
	T.eq(chans(c.B), "G,A", "ветеран Севера — не офицер")
	T.eq(chans(c.A), "G,O,A,C,L", "офицер главной — и главы")
	T.eq(chans(c.V), "G,O,A,C,L", "глава Севера")
	local stranger = c.A.world:Client({ first = "Никто", surname = "Ничей", guild = nil })
	T.eq(chans(stranger), "", "без гильдии каналов нет")
end)

T.test("окно: чат гильдии и офицеров, шёпот, команды", function()
	local w, c = Build()
	T.ok(c.B.ns.Chat.Submit("G", "привет Северу " .. LINK), "строка в гильдию ушла")
	w:Run(2)
	T.eq(HistoryHas(c.V, "G", "привет Северу"), 1, "Вера получила")
	T.eq(HistoryHas(c.B, "G", "привет Северу"), 1, "Борис видит своё эхо")
	T.eq(HistoryHas(c.A, "G", "привет Северу"), 0, "другая гильдия не видит")
	local e = c.V.ns.Chat.History("G")[1]
	T.eq(e.s, "Борис Быстрый", "имя автора")
	T.eq(e.c, "WARRIOR", "класс по GUID")
	T.ok(e.x:find(LINK, 1, true), "ссылка цела")
	T.no(c.B.ns.Chat.Submit("O", "можно?"), "не офицер не пишет в офицерский")
	T.ok(c.V.ns.Chat.Submit("O", "офицерам Севера"), "глава пишет офицерам")
	w:Run(2)
	T.eq(HistoryHas(c.V, "O", "офицерам Севера"), 1, "глава видит")
	T.eq(HistoryHas(c.B, "O", "офицерам Севера"), 0, "ветеран не видит")
	T.ok(c.B.ns.Chat.Submit("A", "/w Глеб Гордый секрет"), "шёпот ушёл")
	local whisper
	for _, l in ipairs(w.log) do
		if l.dist == "CHAT_WHISPER" then whisper = l end
	end
	T.ok(whisper and whisper.target == "Глеб Гордый" and whisper.msg == "секрет", "шёпот по «Имя Фамилия»")
	T.no(c.B.ns.Chat.Submit("A", "/dance"), "команды не выполняются")
	T.ok(c.B:Saw("команды пишите в обычном чате") >= 1, "подсказка про команды")
	T.no(c.B.ns.Chat.Submit("A", "/w Глеб"), "шёпот без текста")
	Errors(c)
end)

T.test("окно: поле ввода отправляет и держит курсор", function()
	local w, c = Build()
	local B = c.B
	B.ns.UI.OpenChat("A", true)
	local box = B.ns.ChatPane.frames.box
	T.ok(box:HasFocus(), "курсор в поле")
	box:SetText("из окна " .. LINK)
	box.scripts.OnEnterPressed(box)
	T.eq(box:GetText(), "", "поле очищено")
	T.ok(box:HasFocus(), "курсор остался")
	w:Run(30)
	for name, cl in pairs(c) do T.eq(cl:Saw("из окна"), 1, name .. " видит строку один раз") end
	T.eq(Has(B.ns.ChatPane.frames.messages.lines, "из окна"), 1, "строка в окне автора")
	box:SetText("")
	box.scripts.OnEnterPressed(box)
	T.no(box:HasFocus(), "пустой Enter убирает курсор")
	-- ↑ возвращает последнюю отправленную строку.
	box.scripts.OnArrowPressed(box, "UP")
	T.ok(box:GetText():find("из окна", 1, true), "история отправленного")
	-- Недоступный канал («Главы» для ветерана) заменяется первым доступным.
	B.ns.ChatPane.Select("L")
	T.eq(B.ns.ChatPane.Current(), "G", "вместо «Глав» — чат гильдии")
	Errors(c)
end)

T.test("окно: строка приходит в окно, непрочитанные", function()
	local w, c = Build()
	local B = c.B
	B.ns.UI.OpenChat("G")
	T.eq(B.ns.ChatPane.Current(), "G", "открыт чат гильдии")
	c.G:Slash("/cz1", "в окно Бориса")
	w:Run(30)
	T.eq(B.ns.ChatPane.unread.A, 1, "непрочитанная в «Чиллзон»")
	T.eq(Has(B.ns.ChatPane.frames.messages.lines, "в окно Бориса"), 0, "в чате гильдии её нет")
	B.ns.ChatPane.Select("A")
	T.eq(B.ns.ChatPane.unread.A, 0, "прочитано")
	T.eq(Has(B.ns.ChatPane.frames.messages.lines, "в окно Бориса"), 1, "строка из истории")
	T.eq(Has(B.ns.ChatPane.frames.messages.lines, "<Орден Чиллзона>"), 1, "гильдия автора у строки")
	c.V:Slash("/cz1", "сразу видно")
	w:Run(30)
	T.eq(Has(B.ns.ChatPane.frames.messages.lines, "сразу видно"), 1, "новая строка открытого канала")
	T.eq(B.ns.ChatPane.unread.A, 0, "открытый канал не копит непрочитанные")
	Errors(c)
end)

T.test("окно: метка в чате игры открывает окно", function()
	local w, c = Build()
	local B = c.B
	c.G:Slash("/cz1", "метка")
	w:Run(30)
	local line
	for _, l in ipairs(B.printed) do
		if l:find("метка", 1, true) then line = l end
	end
	T.ok(line and line:find("|Haddon:Chillzone:chan:A|h[Чиллзон]|h", 1, true), "метка — ссылка")
	B:CallHooks("SetItemRef", "addon:Chillzone:chan:A", "[Чиллзон]", "RightButton")
	T.eq(B.ns.UI.Current(), nil, "правый клик ничего не делает")
	B:CallHooks("SetItemRef", "item:19019", "[x]", "LeftButton")
	T.eq(B.ns.UI.Current(), nil, "чужие ссылки не трогаем")
	B:CallHooks("SetItemRef", "addon:Chillzone:chan:A", "[Чиллзон]", "LeftButton")
	T.eq(B.ns.UI.Current(), "chat", "окно на чате")
	T.eq(B.ns.ChatPane.Current(), "A", "канал «Чиллзон»")
	T.ok(B.ns.ChatPane.frames.box:HasFocus(), "курсор в поле")
	Errors(c)
end)

T.test("окно: без дубля в чат игры строка только в окне", function()
	local w, c = Build()
	c.B.ns.char.chatMirror = false
	c.G:Slash("/cz1", "только окно")
	w:Run(30)
	T.eq(c.B:Saw("только окно"), 0, "в чат игры не пришло")
	T.eq(HistoryHas(c.B, "A", "только окно"), 1, "в истории есть")
	T.eq(c.V:Saw("только окно"), 1, "у других дубль включён")
end)

T.test("окно: люди справа", function()
	local w, c = Build()
	c.M:Slash("/cz1", "я тоже тут")
	w:Run(30)
	local function find(list, name)
		for _, p in ipairs(list) do
			if not p.header and p.name == name then return p end
		end
	end
	local function headers(list)
		local out = {}
		for _, p in ipairs(list) do if p.header then out[#out + 1] = p.guild end end
		return table.concat(out, ",")
	end
	local all = c.G.ns.Views.People("A")
	T.ok(headers(all):find("^Чиллзон,"), "главная гильдия первой: " .. headers(all))
	local karl = find(all, "Карл Великий")
	T.ok(karl and karl.role == "leader" and karl.online, "король в сети")
	T.eq(c.G.ns.Views.Role(karl), "Король", "подпись роли")
	T.eq(find(all, "Арагорн Светлый").role, "officer", "капитан")
	local mira = find(all, "Мира Тихая")
	T.ok(mira and mira.role == "active" and mira.wrote, "рядовая — потому что писала")
	local off = find(all, "Офицер Ордена")
	T.ok(off and not off.online, "офицер не в сети — серым")
	local lords = c.G.ns.Views.People("L")
	T.ok(find(lords, "Вера Верная") and find(lords, "Глеб Гордый") and find(lords, "Карл Великий"), "главы в «Главах»")
	T.ok(find(lords, "Арагорн Светлый"), "офицер главной в «Главах»")
	T.eq(find(lords, "Офицер Ордена"), nil, "офицер другой гильдии не в «Главах»")
	local guild = c.B.ns.Views.People("G")
	T.ok(find(guild, "Вера Верная") and find(guild, "Борис Быстрый"), "своя гильдия по ростеру")
	T.eq(find(guild, "Тихий Друид"), nil, "не в игре — не в списке чата гильдии")
	local officers = c.V.ns.Views.People("O")
	T.ok(find(officers, "Вера Верная") and not find(officers, "Борис Быстрый"), "офицеры гильдии")
	local tt = setmetatable({}, { __index = function() return function() end end })
	for _, p in ipairs(all) do
		if not p.header then c.G.ns.Views.PersonTip(tt, p) end
	end
	Errors(c)
end)

T.test("окно: Enter при открытом окне и в бою", function()
	local w, c = Build({ run = 60 })
	local B = c.B
	B.ns.UI.OpenChat("A")
	local bind = B.bindings.ENTER
	T.ok(bind and bind.button == "ChillzoneChatKey", "Enter ведёт в поле окна")
	B.ns.ChatPane.frames.keyButton.scripts.OnClick()
	T.ok(B.ns.ChatPane.frames.box:HasFocus(), "клавиша ставит курсор")
	B.ns.UI.Toggle()
	T.eq(B.bindings.ENTER, nil, "окно закрыто — Enter снова у игры")
	B.combat = true
	B.ns.UI.OpenChat("A")
	T.eq(B.bindings.ENTER, nil, "в бою привязку не трогаем")
	B.combat = false
	B:Fire("PLAYER_REGEN_ENABLED")
	T.ok(B.bindings.ENTER, "после боя привязка поставлена")
	B:Fire("UPDATE_BINDINGS")
	T.ok(B.bindings.ENTER, "повторная синхронизация ничего не ломает")
	Errors(c)
end)

T.test("окно: вкладки, каналы, ссылки и шёпот без ошибок", function()
	local w, c = Build()
	local A = c.A
	c.G:Slash("/cz1", "ссылка " .. LINK)
	w:Run(30)
	for _, tab in ipairs({ "census", "kingdom", "settings", "chat" }) do A.ns.UI.Toggle(tab) end
	for _, ch in ipairs({ "G", "O", "A", "C", "L" }) do A.ns.ChatPane.Select(ch) end
	local box = A.ns.ChatPane.frames.box
	box.scripts.OnTabPressed(box)
	A.shift = true
	box.scripts.OnTabPressed(box)
	A.shift = false
	A.ns.ChatPane.Select("A")
	local msgs = A.ns.ChatPane.frames.messages
	msgs.scripts.OnHyperlinkClick(msgs, "player:Глеб Гордый", "[Глеб Гордый]", "LeftButton")
	T.eq(box:GetText(), "/w Глеб Гордый ", "клик по имени — шёпот в поле")
	A.shift = true
	box:SetText("")
	msgs.scripts.OnHyperlinkClick(msgs, "item:19019", LINK, "LeftButton")
	A.shift = false
	T.eq(box:GetText(), LINK, "Shift-клик по ссылке — в поле")
	box:SetFocus()
	A:CallHooks("ChatEdit_InsertLink", "[Предмет из сумки]")
	T.ok(box:GetText():find("[Предмет из сумки]", 1, true), "предмет из сумки — в поле")
	A.ns.char.chatTime = true
	A.ns.ChatPane.Reload()
	A.ns.UI.Toggle()
	T.eq(A.ns.UI.Current(), nil, "окно закрыто")
	-- Смена гильдии стирает историю чата гильдии.
	A.ns.char.history.G[1] = { t = 0, s = "Кто-то", x = "старое" }
	A.ns.char.historyGuild = "Прежняя гильдия"
	A:Fire("PLAYER_GUILD_UPDATE")
	A.ns.Roster.Scan()
	T.eq(#A.ns.char.history.G, 0, "история прежней гильдии стёрта")
	Errors(c)
end)

T.test("окно: чат гильдии «Чиллзон» и общий канал «Чиллзон» различимы", function()
	local _, c = Build({ run = 60 })
	local A = c.A
	A.ns.UI.OpenChat("G")
	local f = A.ns.ChatPane.frames
	local seen = {}
	for _, e in ipairs(f.entries) do
		if e:IsShown() then
			local text = e.name:GetText() .. " / " .. e.sub:GetText()
			T.no(seen[text], "одинаковые строки в списке каналов: " .. text)
			seen[text] = true
		end
	end
	T.ok(seen["Чиллзон / чат гильдии"], "чат гильдии подписан")
	T.ok(seen["Чиллзон / все гильдии"], "общий канал подписан")
	T.ok(seen["Офицеры / чат гильдии"] and seen["Офицеры / все гильдии"], "оба «Офицеры» различимы")
	T.ok(seen["Главы / все гильдии"], "«Главы» подписаны")
	T.eq(f.prompt:GetText(), "Гильдия:", "поле ввода чата гильдии — как в игре")
	T.eq(f.scope:GetText(), "чат гильдии", "подпись в шапке")
	A.ns.ChatPane.Select("A")
	T.eq(f.prompt:GetText(), "Чиллзон:", "поле ввода общего канала")
	T.eq(f.scope:GetText(), "все гильдии «Чиллзон», /cz1", "шапка общего канала — с командой")
	A.ns.ChatPane.Select("O")
	T.eq(f.title:GetText(), "Офицеры гильдии", "в шапке — полное название")
	Errors(c)
end)

T.test("окно: шапка — все гильдии, как у Olympus", function()
	local w, c = Build()
	local B = c.B
	local guilds, total, online = B.ns.Data.Totals()
	T.eq(guilds, 3, "три гильдии в переписи")
	local st = B.ns.Views.Status()
	T.eq(st.total, total, "всего")
	T.eq(st.online, online, "в игре")
	T.eq(st.big, B.ns.Util.Num(total) .. " " .. B.ns.Util.Plural(total, "участник", "участника", "участников"), "крупно")
	T.ok(st.small:find("3|r гильдии", 1, true), "мелко: 3 гильдии — " .. st.small)
	T.ok(st.small:find("в игре", 1, true) and st.small:find("обновлено", 1, true), "мелко: в игре, обновлено")
	B.ns.UI.OpenChat("G")
	T.eq(B.ns.UI.status.big:GetText(), st.big, "шапка в окне")
	T.eq(B.ns.UI.heading:GetText(), "", "на чате названия вкладки нет — там канал")
	B.ns.UI.Toggle("census")
	T.eq(B.ns.UI.status.big:GetText(), st.big, "та же шапка на «Переписи»")
	T.eq(B.ns.UI.heading:GetText(), "Перепись", "название вкладки")
	-- Подсказка: по строке на гильдию.
	local lines = {}
	local tt = setmetatable({
		AddLine = function(_, t) lines[#lines + 1] = t end,
		AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. " = " .. r end,
	}, { __index = function() return function() end end })
	B.ns.Views.StatusTip(tt)
	local text = table.concat(lines, "\n")
	for _, g in ipairs({ "Чиллзон", "Чиллзон Север (моя)", "Орден Чиллзона" }) do
		T.ok(text:find(g .. " = ", 1, true), "в подсказке " .. g)
	end
	-- Подсказка у миникарты — те же две строки.
	lines = {}
	B.ns.Views.MinimapTip(tt)
	T.eq(lines[2], st.big, "миникарта: крупная строка")
	-- Без переписи — «ждём».
	local stranger = w:Client({ first = "Никто", surname = "Ничей", guild = nil })
	T.eq(stranger.ns.Views.Status().big, "Ждём перепись", "без данных")
	Errors(c)
end)

T.test("окно: «В сети» под списком людей — про людей канала", function()
	local w, c = Build()
	local V = c.V
	V.ns.UI.OpenChat("G")
	V.ns.ChatPane.RenderPeople()
	local r = V.ns.Roster.report
	local label = V.ns.ChatPane.frames.count
	T.eq(label:GetText(), ("В сети: %s из %s"):format(r.online, r.total), "чат гильдии — по ростеру")
	V.ns.ChatPane.Select("O")
	V.ns.ChatPane.RenderPeople()
	local items, online = V.ns.Views.People("O")
	local n = 0
	for _, p in ipairs(items) do if not p.header then n = n + 1 end end
	T.eq(label:GetText(), ("В сети: %s из %s"):format(online, n), "офицеры — только офицеры")
	T.ok(n < r.total, "офицеров меньше, чем всех")
	V.ns.ChatPane.Select("L")
	V.ns.ChatPane.RenderPeople()
	local on, all = V.ns.ChatPane.Counts("L")
	T.eq(label:GetText(), ("В сети: %s из %s"):format(on, all), "«Главы» — люди списка")
	T.ok(all >= 3 and all < V.ns.Views.Status().total, "главы, а не все участники")
	Errors(c)
end)
