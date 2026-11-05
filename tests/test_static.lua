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
