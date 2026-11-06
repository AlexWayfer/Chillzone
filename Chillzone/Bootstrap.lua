-- Chillzone: самый первый файл. HereBeDragons-Pins ждёт карту мира при загрузке,
-- а в Classic она грузится по требованию: подгружаем её заранее (как Olympus).

if not WorldMapFrame then
	local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
	if load then pcall(load, "Blizzard_WorldMap") end
end
