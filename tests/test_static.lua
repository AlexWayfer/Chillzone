-- Статические проверки файлов аддона: синтаксис, Lua 5.1 (без goto/меток), без BOM.
local T = ...

local files = T.tocFiles()

T.test("static: toc перечисляет существующие файлы", function()
	T.ok(#files > 5, "toc пуст")
	for _, f in ipairs(files) do
		local h = io.open(T.ROOT .. "/Chillzone/" .. f, "rb")
		T.ok(h, "нет файла " .. f)
		h:close()
	end
end)

-- Версия записана дважды: toc показывает её игре, C.VERSION уходит в приветствие другим клиентам.
T.test("static: версия в toc и Config.lua совпадает", function()
	local toc = T.read(T.ROOT .. "/Chillzone/Chillzone.toc"):match("## Version:%s*([^\r\n]-)%s*[\r\n]")
	local cfg = T.read(T.ROOT .. "/Chillzone/Config.lua"):match('C%.VERSION%s*=%s*"([^"]+)"')
	T.ok(toc, "нет ## Version в Chillzone.toc")
	T.ok(cfg, "нет C.VERSION в Config.lua")
	T.eq(cfg, toc, "C.VERSION против ## Version")
end)

T.test("static: синтаксис всех файлов", function()
	for _, f in ipairs(files) do
		local chunk, err = loadfile(T.ROOT .. "/Chillzone/" .. f)
		T.ok(chunk, err)
	end
end)

-- Строки и комментарии вырезаются грубо, чтобы слово goto в тексте не мешало.
local function code(s)
	s = s:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
	s = s:gsub("%[(=*)%[.-%]%1%]", '""'):gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''")
	return s
end

T.test("static: свои файлы — Lua 5.1 и UTF-8 без BOM", function()
	for _, f in ipairs(files) do
		if not f:find("^libs/") then
			local s = T.read(T.ROOT .. "/Chillzone/" .. f)
			T.no(s:sub(1, 3) == "\239\187\191", f .. ": BOM")
			local c = code(s)
			T.no(c:find("%f[%w_]goto%f[^%w_]"), f .. ": goto")
			T.no(c:find("::[%a_][%w_]*::"), f .. ": метка")
			T.ok(s:find("^%-%-") or s:find("^local ADDON, ns = %.%.%."), f .. ": должен начинаться с комментария или local ADDON, ns = ...")
		end
	end
end)

-- Строки, которые видит игрок, — только символы, которые точно есть в русском шрифте игры:
-- ASCII, кириллица, «», — и №. Остального (·, …, –, →, ×) в шрифте нет — вместо них квадраты.
local function Literals(line)
	local out, i, n = {}, 1, #line
	while i <= n do
		local ch = line:sub(i, i)
		if ch == "-" and line:sub(i + 1, i + 1) == "-" then break end
		if ch == '"' or ch == "'" then
			local j, buf = i + 1, {}
			while j <= n and line:sub(j, j) ~= ch do
				if line:sub(j, j) == "\\" then j = j + 1 end
				buf[#buf + 1] = line:sub(j, j)
				j = j + 1
			end
			out[#out + 1] = table.concat(buf)
			i = j
		end
		i = i + 1
	end
	return out
end

local SAFE = { ["«"] = true, ["»"] = true, ["—"] = true, ["№"] = true }

local function BadGlyph(s)
	for ch in s:gmatch("[\192-\255][\128-\191]*") do
		local b1, b2 = ch:byte(1, 2)
		local cyr = (b1 == 0xD0) or (b1 == 0xD1 and b2 <= 0x9F)
		if not cyr and not SAFE[ch] then return ch end
	end
end

T.test("static: в строках нет символов, которых нет в шрифте игры", function()
	local found = {}
	for _, f in ipairs(files) do
		if not f:find("^libs/") then
			local n = 0
			for line in (T.read(T.ROOT .. "/Chillzone/" .. f) .. "\n"):gmatch("([^\n]*)\n") do
				n = n + 1
				for _, lit in ipairs(Literals(line)) do
					local bad = BadGlyph(lit)
					if bad then found[#found + 1] = ("%s:%d: «%s» в «%s»"):format(f, n, bad, lit) end
				end
			end
		end
	end
	T.eq(#found, 0, "\n  " .. table.concat(found, "\n  "))
end)

-- SetCheckedTexture, SetNormalTexture и SetPushedTexture режим наложения не принимают (это умеет
-- только SetHighlightTexture): второй аргумент молча теряется. Так значок вкладки закрывала рамка.
T.test("static: режим наложения — только через SetBlendMode", function()
	for _, f in ipairs(files) do
		if not f:find("^libs/") then
			local c = code(T.read(T.ROOT .. "/Chillzone/" .. f))
			for _, m in ipairs({ "SetCheckedTexture", "SetNormalTexture", "SetPushedTexture", "SetDisabledTexture" }) do
				T.no(c:find(m .. "%([^)]*,"), f .. ": " .. m .. " со вторым аргументом")
			end
		end
	end
end)
