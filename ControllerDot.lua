-- ControllerDot: customize the controller reticle (GamepadReticle) or turn it off completely.
-- Only GamepadReticle is touched (never match "reticle" broadly: that causes lag).
-- Always SetAlpha instead of Hide(), so it also works in combat.

local ADDON = "ControllerDot"

local defaults = {
	hidden = false,   -- whole reticle off
	alpha = 1,        -- dot transparency (0-1)
	r = 1, g = 1, b = 1,
	shape = "default",
	size = 3,         -- pixels
	thickness = 1,    -- line thickness for plus/cross
	swing = true,     -- show the swing timer ring around the dot
}

local SHAPES = { "default", "square", "circle", "plus", "cross" }
local SHAPE_NAMES = {
	default = "Default",
	square = "Square",
	circle = "Circle",
	plus = "Plus (+)",
	cross = "Cross (x)",
}
local CIRCLE_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- addons that also hide GamepadReticle and would make our settings invisible
local CONFLICTS = { "NoDot" }

local db
local overlay, tex, bar1, bar2
local hooked = false
local origIconW, origIconH
local busy = false -- prevents recursion in the hooks
local weHidReticle, weHidSwing = false, false

local function Print(msg)
	print("|cff33ff99ControllerDot|r: " .. msg)
end

local function IsLoaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		return C_AddOns.IsAddOnLoaded(name)
	end
	return IsAddOnLoaded and IsAddOnLoaded(name)
end

local function LoadedConflicts()
	local found = {}
	for _, name in ipairs(CONFLICTS) do
		if IsLoaded(name) then found[#found + 1] = name end
	end
	return found
end

---------------------------------------------------------------------------
-- Apply
---------------------------------------------------------------------------

local function IconAlpha()
	if db.shape ~= "default" then return 0 end
	return db.alpha
end

local function BuildOverlay(reticle)
	overlay = CreateFrame("Frame", nil, reticle)
	overlay:SetPoint("CENTER")
	overlay:SetSize(1, 1)
	overlay:SetFrameLevel(reticle:GetFrameLevel() + 5)

	tex = overlay:CreateTexture(nil, "OVERLAY")
	tex:SetPoint("CENTER")
	bar1 = overlay:CreateTexture(nil, "OVERLAY")
	bar1:SetPoint("CENTER")
	bar2 = overlay:CreateTexture(nil, "OVERLAY")
	bar2:SetPoint("CENTER")
end

local function ApplyOverlay()
	local s, t = db.size, db.thickness
	local shape = db.shape

	tex:Hide(); bar1:Hide(); bar2:Hide()
	if shape == "default" then
		overlay:Hide()
		return
	end
	overlay:Show()
	overlay:SetAlpha(db.alpha)

	if shape == "square" or shape == "circle" then
		if shape == "square" then
			tex:SetColorTexture(1, 1, 1, 1)
		else
			tex:SetTexture(CIRCLE_TEX)
		end
		tex:SetVertexColor(db.r, db.g, db.b)
		tex:SetSize(s, s)
		tex:Show()
	else
		local rot = (shape == "cross") and math.rad(45) or 0
		for i, bar in ipairs({ bar1, bar2 }) do
			bar:SetColorTexture(db.r, db.g, db.b, 1)
			if i == 1 then bar:SetSize(s, t) else bar:SetSize(t, s) end
			if bar.SetRotation then bar:SetRotation(rot) end
			bar:Show()
		end
	end
end

local function Apply()
	local reticle = GamepadReticle
	if not reticle or not db then return end
	local icon = reticle.Icons and reticle.Icons.StandardIcon
	local swing = reticle.SwingTimer

	if not hooked then
		hooked = true
		hooksecurefunc(reticle, "SetAlpha", function(self, a)
			if busy or not db.hidden then return end
			if a and a > 0 then
				busy = true; self:SetAlpha(0); busy = false
			end
		end)
		if icon then
			origIconW, origIconH = icon:GetSize()
			hooksecurefunc(icon, "SetAlpha", function(self, a)
				if busy then return end
				local want = IconAlpha()
				if a and math.abs(a - want) > 0.01 then
					busy = true; self:SetAlpha(want); busy = false
				end
			end)
			hooksecurefunc(icon, "SetVertexColor", function(self)
				if busy then return end
				busy = true; self:SetVertexColor(db.r, db.g, db.b); busy = false
			end)
		end
		if swing then
			hooksecurefunc(swing, "SetAlpha", function(self, a)
				if busy or db.swing then return end
				if a and a > 0 then
					busy = true; self:SetAlpha(0); busy = false
				end
			end)
		end
		BuildOverlay(reticle)
	end

	busy = true
	-- only restore what we hid ourselves; otherwise the game decides visibility
	if db.hidden then
		reticle:SetAlpha(0); weHidReticle = true
	elseif weHidReticle then
		reticle:SetAlpha(1); weHidReticle = false
	end
	if icon then
		icon:SetAlpha(IconAlpha())
		icon:SetVertexColor(db.r, db.g, db.b)
		if db.shape == "default" then
			icon:SetSize(db.size, db.size)
		elseif origIconW then
			icon:SetSize(origIconW, origIconH)
		end
	end
	if swing then
		if not db.swing then
			swing:SetAlpha(0); weHidSwing = true
		elseif weHidSwing then
			swing:SetAlpha(1); weHidSwing = false
		end
	end
	busy = false

	ApplyOverlay()
end

---------------------------------------------------------------------------
-- Settings window
---------------------------------------------------------------------------

local panel
local widgets = {}

local function MakeSlider(parent, label, minV, maxV, step, key, fmt, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	fs:SetPoint("TOPLEFT", 16, y)

	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetPoint("TOPLEFT", 16, y - 16)
	s:SetSize(248, 16)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:EnableMouseWheel(true)

	local bg = s:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("LEFT"); bg:SetPoint("RIGHT")
	bg:SetHeight(6)
	bg:SetColorTexture(0.2, 0.2, 0.2, 1)
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

	local function UpdateLabel(v)
		fs:SetText(label .. ": " .. string.format(fmt, v))
	end
	s:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v / step + 0.5) * step
		db[key] = v
		UpdateLabel(v)
		Apply()
	end)
	s:SetScript("OnMouseWheel", function(self, d)
		self:SetValue(self:GetValue() + d * step)
	end)
	s.Refresh = function(self)
		self:SetValue(db[key])
		UpdateLabel(db[key])
	end
	return s
end

local function MakeCheck(parent, label, key, y)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetPoint("TOPLEFT", 12, y)
	local fs = c.Text or c.text or c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
	fs:SetText(label)
	c:SetScript("OnClick", function(self)
		db[key] = self:GetChecked() and true or false
		Apply()
	end)
	c.Refresh = function(self) self:SetChecked(db[key]) end
	return c
end

local function OpenColorPicker()
	local oldR, oldG, oldB = db.r, db.g, db.b
	local function OnChange()
		db.r, db.g, db.b = ColorPickerFrame:GetColorRGB()
		widgets.swatch:Refresh()
		Apply()
	end
	local function OnCancel()
		db.r, db.g, db.b = oldR, oldG, oldB
		widgets.swatch:Refresh()
		Apply()
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = oldR, g = oldG, b = oldB,
			hasOpacity = false,
			swatchFunc = OnChange,
			cancelFunc = OnCancel,
		})
	else
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.func = OnChange
		ColorPickerFrame.cancelFunc = OnCancel
		ColorPickerFrame.previousValues = { oldR, oldG, oldB }
		ColorPickerFrame:SetColorRGB(oldR, oldG, oldB)
		ColorPickerFrame:Hide()
		ColorPickerFrame:Show()
	end
end

local function RefreshPanel()
	for _, w in pairs(widgets) do w:Refresh() end
end

local function BuildPanel()
	panel = CreateFrame("Frame", "ControllerDotFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	panel:SetSize(280, 370)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:SetClampedToScreen(true)
	if panel.SetBackdrop then
		panel:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		panel:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
	end
	tinsert(UISpecialFrames, "ControllerDotFrame") -- close with Escape

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -12)
	title:SetText("Controller Dot Customizer")

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	widgets.hidden = MakeCheck(panel, "Turn reticle off", "hidden", -38)
	widgets.swing = MakeCheck(panel, "Show swing timer ring", "swing", -64)

	-- shape
	local shapeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	shapeLabel:SetPoint("TOPLEFT", 16, -100)
	shapeLabel:SetText("Shape")
	local shapeBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	shapeBtn:SetPoint("TOPLEFT", 14, -114)
	shapeBtn:SetSize(130, 22)
	shapeBtn:SetScript("OnClick", function(self)
		local idx = 1
		for i, s in ipairs(SHAPES) do if s == db.shape then idx = i end end
		idx = (idx % #SHAPES) + 1
		db.shape = SHAPES[idx]
		self:Refresh()
		Apply()
	end)
	shapeBtn.Refresh = function(self) self:SetText(SHAPE_NAMES[db.shape] or db.shape) end
	widgets.shape = shapeBtn

	-- color
	local swatch = CreateFrame("Button", nil, panel)
	swatch:SetPoint("LEFT", shapeBtn, "RIGHT", 12, 0)
	swatch:SetSize(22, 22)
	local border = swatch:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0.6, 0.6, 0.6, 1)
	local fill = swatch:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", 2, -2)
	fill:SetPoint("BOTTOMRIGHT", -2, 2)
	local swLabel = swatch:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	swLabel:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
	swLabel:SetText("Color")
	swatch:SetScript("OnClick", OpenColorPicker)
	swatch.Refresh = function() fill:SetColorTexture(db.r, db.g, db.b, 1) end
	widgets.swatch = swatch

	widgets.alpha = MakeSlider(panel, "Opacity", 0, 1, 0.05, "alpha", "%.2f", -150)
	widgets.size = MakeSlider(panel, "Size", 1, 40, 1, "size", "%d px", -192)
	widgets.thickness = MakeSlider(panel, "Line thickness (plus/cross)", 1, 8, 1, "thickness", "%d px", -234)

	-- warning when another addon also hides the reticle
	local warn = panel:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
	warn:SetPoint("TOPLEFT", 16, -276)
	warn:SetPoint("RIGHT", -16, 0)
	warn:SetJustifyH("LEFT")
	warn.Refresh = function(self)
		local found = LoadedConflicts()
		if #found > 0 then
			self:SetText(table.concat(found, ", ") .. " is also enabled and hides the reticle. Disable it, or these settings will have no visible effect.")
			self:Show()
		else
			self:Hide()
		end
	end
	widgets.warn = warn

	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetPoint("BOTTOM", 0, 14)
	reset:SetSize(120, 22)
	reset:SetText("Defaults")
	reset:SetScript("OnClick", function()
		for k, v in pairs(defaults) do db[k] = v end
		RefreshPanel()
		Apply()
	end)

	panel:SetScript("OnShow", RefreshPanel)
	panel:Hide()
end

local function TogglePanel()
	if not panel then BuildPanel() end
	panel:SetShown(not panel:IsShown())
end

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------

local function Debug()
	local r = GamepadReticle
	Print("GamepadReticle: " .. (r and "found" or "NOT found"))
	if r then
		Print(string.format("  shown=%s visible=%s alpha=%.2f hooked=%s",
			tostring(r:IsShown()), tostring(r:IsVisible()), r:GetAlpha(), tostring(hooked)))
		local icon = r.Icons and r.Icons.StandardIcon
		if icon then
			local w, h = icon:GetSize()
			Print(string.format("  StandardIcon: alpha=%.2f size=%.0fx%.0f", icon:GetAlpha(), w, h))
		else
			Print("  StandardIcon: NOT found")
		end
		Print("  SwingTimer: " .. (r.SwingTimer and "found" or "NOT found"))
	end
	Print(string.format("  settings: hidden=%s shape=%s alpha=%.2f size=%d",
		tostring(db.hidden), db.shape, db.alpha, db.size))
	local found = LoadedConflicts()
	Print("  conflicting addons: " .. (#found > 0 and table.concat(found, ", ") or "none"))
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_CONTROLLERDOT1 = "/dot"
SLASH_CONTROLLERDOT2 = "/controllerdot"
SlashCmdList.CONTROLLERDOT = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "off" then
		db.hidden = true
	elseif msg == "on" then
		db.hidden = false
	elseif msg == "toggle" then
		db.hidden = not db.hidden
	elseif msg == "reset" then
		for k, v in pairs(defaults) do db[k] = v end
	elseif msg == "debug" then
		Debug()
		return
	elseif msg == "help" then
		Print("/dot - open settings, /dot on|off|toggle, /dot reset, /dot debug")
		return
	else
		TogglePanel()
		return
	end
	Apply()
	if panel and panel:IsShown() then RefreshPanel() end
	Print(db.hidden and "reticle off." or "reticle on.")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(f.RegisterEvent, f, "GAME_PAD_ACTIVE_CHANGED")
f:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			ControllerDotDB = ControllerDotDB or {}
			db = ControllerDotDB
			for k, v in pairs(defaults) do
				if db[k] == nil then db[k] = v end
			end
		end
		return
	end
	if event == "PLAYER_LOGIN" then
		local found = LoadedConflicts()
		if #found > 0 then
			Print("|cffff5555" .. table.concat(found, ", ") .. " is also enabled and hides the reticle. Disable it, or ControllerDot's settings will have no visible effect.|r")
		end
		return
	end
	Apply()
	-- in case the reticle is created a bit later
	C_Timer.After(2, Apply)
end)
