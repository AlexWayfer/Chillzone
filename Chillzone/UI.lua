-- Chillzone: окно (вкладки «Перепись» и «Королевство»), флажки настроек, кнопка у миникарты.
-- Рамка и кнопка у миникарты — по образцу Olympus UI.lua.
local ADDON, ns = ...

local L = ns.L

local UI = {}
ns.UI = UI

local ROW_H = 18
local WIDTH, HEIGHT = 470, 500
local frame, scroll, child, tabs, rows = nil, nil, nil, {}, {}
local current = "census"
local minimapButton

local function SetTip(owner, tip)
	owner:SetScript("OnEnter", function(self)
		if not self.tip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		ns.SafeCall("tooltip", self.tip, GameTooltip)
		GameTooltip:Show()
	end)
	owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
	owner.tip = tip
end

local function Row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, child)
	r:SetHeight(ROW_H)
	r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.left:SetJustifyH("LEFT")
	r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	r.right:SetJustifyH("RIGHT")
	r.right:SetPoint("RIGHT", -4, 0)
	r.left:SetPoint("LEFT", 4, 0)
	r.left:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
	r.left:SetWordWrap(false)
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)
	SetTip(r, nil)
	rows[i] = r
	return r
end

function UI.Render()
	if not frame or not frame:IsShown() then return end
	local lines = current == "kingdom" and ns.Views.Kingdom() or ns.Views.Census()
	local width = scroll:GetWidth()
	child:SetWidth(width)
	local y = 0
	for i, line in ipairs(lines) do
		local r = Row(i)
		if line.gap then y = y + 8 end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", child, "TOPLEFT", (line.indent or 0) * 18, -y)
		r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
		r.left:SetFontObject(line.header and "GameFontNormal" or "GameFontHighlightSmall")
		r.left:SetText(line.text or "")
		r.right:SetText(line.right or "")
		r.tip = line.tip
		r:EnableMouse(line.tip ~= nil)
		r:Show()
		y = y + ROW_H
	end
	for i = #lines + 1, #rows do rows[i]:Hide() end
	child:SetHeight(math.max(y, 10))
	for key, tab in pairs(tabs) do
		if key == current then tab:LockHighlight() else tab:UnlockHighlight() end
	end
	frame.mapCheck:SetChecked(ns.db.settings.showMap)
	frame.zonesCheck:SetChecked(ns.char.shareZones)
end

local function Tab(key, text, x)
	local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	b:SetSize(130, 22)
	b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -30)
	b:SetText(text)
	b:SetScript("OnClick", function()
		current = key
		scroll:SetVerticalScroll(0)
		UI.Render()
	end)
	tabs[key] = b
end

local function Check(text, tip, x, onClick)
	local c = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	c:SetSize(24, 24)
	c:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, 8)
	local label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", c, "RIGHT", 2, 0)
	label:SetText(text)
	c:SetScript("OnClick", function(self) ns.SafeCall("check", onClick, self:GetChecked() and true or false) end)
	SetTip(c, function(tt) tt:AddLine(text, 1, 0.82, 0) tt:AddLine(tip, 1, 1, 1, true) end)
	return c
end

local function Create()
	frame = CreateFrame("Frame", "ChillzoneFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER", 0, 40)
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	local title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if not frame.TitleText then title:SetPoint("TOP", 0, -5) end
	title:SetText("Chillzone")
	tinsert(UISpecialFrames, "ChillzoneFrame")

	Tab("census", L.TAB_CENSUS, 12)
	Tab("kingdom", L.TAB_KINGDOM, 146)

	scroll = CreateFrame("ScrollFrame", "ChillzoneScroll", frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -58)
	scroll:SetPoint("BOTTOMRIGHT", -32, 40)
	child = CreateFrame("Frame", nil, scroll)
	child:SetSize(WIDTH - 44, 10)
	scroll:SetScrollChild(child)

	frame.mapCheck = Check(L.CHECK_MAP, L.CHECK_MAP_TIP, 12, function(on) ns.Map.SetEnabled(on) end)
	frame.zonesCheck = Check(L.CHECK_ZONES, L.CHECK_ZONES_TIP, 200, function(on)
		ns.char.shareZones = on
		ns.Print(on and L.ZONES_ON or L.ZONES_OFF)
		ns.Census.SendHello()
	end)

	frame:SetScript("OnShow", function() UI.Render() end)
	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= 30 then
			elapsed = 0
			UI.Render()
		end
	end)
end

function UI.Toggle(tab)
	if not frame then Create() end
	if tab then current = tab end
	if frame:IsShown() and not tab then frame:Hide() else frame:Show() UI.Render() end
end

local function Refresh()
	if frame and frame:IsShown() then UI.Render() end
end
ns.On("DATA", Refresh)
ns.On("RELAYS", Refresh)
ns.On("SETTINGS", Refresh)
ns.On("GUILD_CHANGED", Refresh)

---------------------------------------------------------------------------
-- Кнопка у миникарты: левый щелчок — окно, правый — круги на карте, перетаскивание — место.
---------------------------------------------------------------------------
local function PlaceButton()
	if not (minimapButton and rawget(_G, "Minimap")) then return end
	local angle = math.rad(ns.db.settings.minimap.angle or 200)
	local radius = (Minimap:GetWidth() / 2) + 5
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function CreateButton()
	local b = CreateFrame("Button", "ChillzoneMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 6, -6)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\Icons\\Spell_Nature_Tranquility")
	icon:SetSize(18, 18)
	icon:SetPoint("TOPLEFT", 7, -7)
	if icon.SetMask then pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end
	local ring = b:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	ring:SetSize(53, 53)
	ring:SetPoint("TOPLEFT")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnClick", function(_, button)
		ns.SafeCall("minimap click", function()
			if button == "RightButton" then ns.Map.SetEnabled(not ns.db.settings.showMap) else UI.Toggle() end
		end)
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			ns.db.settings.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx))
			PlaceButton()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		ns.SafeCall("minimap tip", ns.Views.MinimapTip, GameTooltip)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

function UI.UpdateMinimapButton()
	if not rawget(_G, "Minimap") then return end
	minimapButton = minimapButton or CreateButton()
	PlaceButton()
	minimapButton:SetShown(not ns.db.settings.minimap.hide)
end

ns.On("LOGIN", function()
	UI.UpdateMinimapButton()
end)

ns.Command("minimap", function()
	ns.db.settings.minimap.hide = not ns.db.settings.minimap.hide
	UI.UpdateMinimapButton()
	ns.Print(ns.db.settings.minimap.hide and L.MINIMAP_HIDDEN or L.MINIMAP_SHOWN)
end, L.HELP_MINIMAP)

ns.Command("kingdom", function() UI.Toggle("kingdom") end, L.HELP_KINGDOM)
ns.Command("census", function() UI.Toggle("census") end, L.HELP_CENSUS)
