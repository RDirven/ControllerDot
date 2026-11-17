-- ControllerDot: customize the controller reticle (GamepadReticle) or turn it off completely.
-- Only GamepadReticle is touched (never match "reticle" broadly: that causes lag).
-- Always SetAlpha instead of Hide(), so it also works in combat.

local ADDON = "ControllerDot"

local defaults = {
	hidden = true,          -- master switch: whole reticle off (hidden by default)
	showWhen = "always",    -- always | combat | outofcombat | target
	colorByReaction = false, -- tint by hostile / neutral / friendly target
	alpha = 1,              -- dot transparency (0-1)
	r = 1, g = 1, b = 1,
	shape = "default",
	size = 3,               -- pixels
	thickness = 1,          -- line thickness for plus/cross/crosshair
	outline = 0,            -- black outline thickness in pixels (0 = off, custom shapes only)
}

local SHAPES = { "default", "square", "diamond", "circle", "plus", "cross", "crosshair" }
local SHAPE_NAMES = {
	default = "Default",
	square = "Square",
	diamond = "Diamond",
	circle = "Circle",
	plus = "Plus (+)",
	cross = "Cross (x)",
	crosshair = "Crosshair",
}
local CIRCLE_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local SHOW_WHEN = { "always", "combat", "outofcombat", "target" }
local SHOW_WHEN_NAMES = {
	always = "Always",
	combat = "Only in combat",
	outofcombat = "Only out of combat",
	target = "Only with a target",
}

-- colors used when "color by target" is on
local COLOR_HOSTILE = { 1, 0.2, 0.2 }
local COLOR_NEUTRAL = { 1, 0.9, 0.2 }
local COLOR_FRIENDLY = { 0.2, 1, 0.2 }
-- units that can be the reticle's target (soft targets do not exist on every client)
local TARGET_UNITS = { "target", "softenemy", "softfriend" }

-- addons that also hide GamepadReticle and would make our settings invisible
local CONFLICTS = { "NoDot" }

local db
local overlay
local parts = {}           -- up to 4 { edge, fill } texture pairs that make up the custom shape
local hooked = false
local origIconW, origIconH
local busy = false         -- prevents recursion in the hooks
local weHidReticle = false
local lastGameAlpha        -- last alpha the game asked for, so we can restore it
local inCombat = false

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
-- Visibility and color rules
---------------------------------------------------------------------------

local function HasTarget()
	for _, unit in ipairs(TARGET_UNITS) do
		if UnitExists(unit) then return true end
	end
	return false
end

-- true when the reticle must be invisible right now
local function ShouldHide()
	if db.hidden then return true end
	local w = db.showWhen
	if w == "combat" then
		return not inCombat
	elseif w == "outofcombat" then
		return inCombat
	elseif w == "target" then
		return not HasTarget()
	end
	return false
end

-- base color, or a reaction color when the reticle has a target
local function CurrentColor()
	if db.colorByReaction then
		for _, unit in ipairs(TARGET_UNITS) do
			if UnitExists(unit) then
				local reaction = UnitReaction("player", unit)
				if reaction then
					local c
					if reaction <= 3 then
						c = COLOR_HOSTILE
					elseif reaction == 4 then
						c = COLOR_NEUTRAL
					else
						c = COLOR_FRIENDLY
					end
					return c[1], c[2], c[3]
				end
			end
		end
	end
	return db.r, db.g, db.b
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

	-- edges are drawn below all fills (sublevel 0 vs 1) so outlines never cover the shape
	for i = 1, 4 do
		parts[i] = {
			edge = overlay:CreateTexture(nil, "OVERLAY", nil, 0),
			fill = overlay:CreateTexture(nil, "OVERLAY", nil, 1),
		}
	end
end

-- geometry of a shape: a list of { w, h, x, y, rot (degrees), circle }
local function ShapeParts(shape, s, t)
	if shape == "square" then
		return { { w = s, h = s } }
	elseif shape == "diamond" then
		return { { w = s, h = s, rot = 45 } }
	elseif shape == "circle" then
		return { { w = s, h = s, circle = true } }
	elseif shape == "plus" or shape == "cross" then
		local rot = (shape == "cross") and 45 or 0
		return { { w = s, h = t, rot = rot }, { w = t, h = s, rot = rot } }
	elseif shape == "crosshair" then
		local gap = math.max(1, math.floor(s / 4))
		local len = math.max(1, (s - 2 * gap) / 2)
		local off = gap + len / 2
		return {
			{ w = len, h = t, x = -off },
			{ w = len, h = t, x = off },
			{ w = t, h = len, y = off },
			{ w = t, h = len, y = -off },
		}
	end
	return {}
end

local function StyleTexture(texture, spec, grow, r, g, b)
	texture:ClearAllPoints()
	texture:SetPoint("CENTER", overlay, "CENTER", spec.x or 0, spec.y or 0)
	texture:SetSize(spec.w + grow, spec.h + grow)
	if spec.circle then
		texture:SetTexture(CIRCLE_TEX)
		texture:SetVertexColor(r, g, b)
	else
		texture:SetColorTexture(r, g, b, 1)
	end
	if texture.SetRotation then texture:SetRotation(math.rad(spec.rot or 0)) end
	texture:Show()
end

local function ApplyOverlay()
	for _, p in ipairs(parts) do
		p.fill:Hide(); p.edge:Hide()
	end
	if db.shape == "default" then
		overlay:Hide()
		return
	end
	overlay:Show()
	overlay:SetAlpha(db.alpha)

	local r, g, b = CurrentColor()
	local grow = db.outline * 2
	for i, spec in ipairs(ShapeParts(db.shape, db.size, db.thickness)) do
		local p = parts[i]
		StyleTexture(p.fill, spec, 0, r, g, b)
		if db.outline > 0 then
			StyleTexture(p.edge, spec, grow, 0, 0, 0)
		end
	end
end

local function Apply()
	local reticle = GamepadReticle
	if not reticle or not db then return end
	local icon = reticle.Icons and reticle.Icons.StandardIcon

	if not hooked then
		hooked = true
		lastGameAlpha = reticle:GetAlpha()
		hooksecurefunc(reticle, "SetAlpha", function(self, a)
			if busy then return end
			lastGameAlpha = a
			if a and a > 0 and ShouldHide() then
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
				busy = true; self:SetVertexColor(CurrentColor()); busy = false
			end)
		end
		BuildOverlay(reticle)
	end

	busy = true
	-- only restore what we hid ourselves; otherwise the game decides visibility
	if ShouldHide() then
		reticle:SetAlpha(0); weHidReticle = true
	elseif weHidReticle then
		reticle:SetAlpha(lastGameAlpha or 1); weHidReticle = false
	end
	if icon then
		icon:SetAlpha(IconAlpha())
		icon:SetVertexColor(CurrentColor())
		if db.shape == "default" then
			icon:SetSize(db.size, db.size)
		elseif origIconW then
			icon:SetSize(origIconW, origIconH)
		end
	end
	busy = false

	ApplyOverlay()
end

-- restore all styling; the master "reticle off" switch is left as the user set it
local function ResetSettings()
	for k, v in pairs(defaults) do
		if k ~= "hidden" then db[k] = v end
	end
end

---------------------------------------------------------------------------
-- Settings UI (shared by the small /dot window and the Blizzard options page)
---------------------------------------------------------------------------

local panel
local sets = {}          -- one widget set per UI that was built
local refreshing = false -- true while widgets are being synced from the db

local function RefreshAll()
	refreshing = true
	for _, set in ipairs(sets) do
		for _, w in pairs(set) do w:Refresh() end
	end
	refreshing = false
end

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
		-- round to the step and drop floating point noise (0.15000000000000002)
		v = tonumber(string.format("%.4f", math.floor(v / step + 0.5) * step))
		UpdateLabel(v)
		if refreshing then return end
		db[key] = v
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

-- button that cycles through a list of values (left-click next, right-click previous)
local function MakeCycle(parent, key, list, names, x, y, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetPoint("TOPLEFT", x, y)
	b:SetSize(width, 22)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(self, button)
		local idx = 1
		for i, v in ipairs(list) do
			if v == db[key] then idx = i end
		end
		idx = idx + (button == "RightButton" and -1 or 1)
		if idx < 1 then idx = #list elseif idx > #list then idx = 1 end
		db[key] = list[idx]
		self:Refresh()
		Apply()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Left-click: next, right-click: previous")
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b.Refresh = function(self) self:SetText(names[db[key]] or db[key]) end
	return b
end

local function OpenColorPicker()
	local oldR, oldG, oldB = db.r, db.g, db.b
	local function OnChange()
		db.r, db.g, db.b = ColorPickerFrame:GetColorRGB()
		RefreshAll()
		Apply()
	end
	local function OnCancel()
		db.r, db.g, db.b = oldR, oldG, oldB
		RefreshAll()
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

-- fills `parent` with all controls; y0 is the y offset of the first row
local function BuildContent(parent, y0)
	local w = {}
	sets[#sets + 1] = w

	w.hidden = MakeCheck(parent, "Turn reticle off", "hidden", y0)

	-- shape + color
	local shapeLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	shapeLabel:SetPoint("TOPLEFT", 16, y0 - 36)
	shapeLabel:SetText("Shape")
	w.shape = MakeCycle(parent, "shape", SHAPES, SHAPE_NAMES, 14, y0 - 50, 130)

	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetPoint("LEFT", w.shape, "RIGHT", 12, 0)
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
	w.swatch = swatch

	-- visibility rules
	local whenLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	whenLabel:SetPoint("TOPLEFT", 16, y0 - 80)
	whenLabel:SetText("Show when (only applies if the reticle is not turned off)")
	w.showWhen = MakeCycle(parent, "showWhen", SHOW_WHEN, SHOW_WHEN_NAMES, 14, y0 - 94, 190)
	w.colorByReaction = MakeCheck(parent, "Color by target (hostile / neutral / friendly)", "colorByReaction", y0 - 124)

	w.alpha = MakeSlider(parent, "Opacity", 0, 1, 0.05, "alpha", "%.2f", y0 - 158)
	w.size = MakeSlider(parent, "Size", 1, 40, 1, "size", "%d px", y0 - 200)
	w.thickness = MakeSlider(parent, "Line thickness (plus/cross/crosshair)", 1, 8, 1, "thickness", "%d px", y0 - 242)
	w.outline = MakeSlider(parent, "Outline (not for Default shape)", 0, 4, 1, "outline", "%d px", y0 - 284)

	-- warning when another addon also hides the reticle
	local warn = parent:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
	warn:SetPoint("TOPLEFT", 16, y0 - 326)
	warn:SetWidth(248)
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
	w.warn = warn

	local reset = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	reset:SetPoint("TOPLEFT", 16, y0 - 372)
	reset:SetSize(120, 22)
	reset:SetText("Defaults")
	reset:SetScript("OnClick", function()
		ResetSettings()
		RefreshAll()
		Apply()
	end)

	return w
end

-- small movable window (/dot): leaves the screen center free so you can see the reticle
local function BuildPanel()
	panel = CreateFrame("Frame", "ControllerDotFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	panel:SetSize(280, 444)
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

	BuildContent(panel, -38)

	panel:SetScript("OnShow", RefreshAll)
	panel:Hide()
end

local function TogglePanel()
	if not panel then BuildPanel() end
	panel:SetShown(not panel:IsShown())
end

-- page in the Blizzard options window (Options > AddOns)
local optionsFrame, category

local function BuildOptions()
	optionsFrame = CreateFrame("Frame")
	optionsFrame.name = "Controller Dot"

	local title = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Controller Dot Customizer")

	local hint = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", 16, -42)
	hint:SetWidth(420)
	hint:SetJustifyH("LEFT")
	hint:SetText("The options window covers the center of the screen. Type /dot for a small movable window if you want to see the reticle while you edit.")

	BuildContent(optionsFrame, -84)
	optionsFrame:SetScript("OnShow", RefreshAll)

	pcall(function()
		if Settings and Settings.RegisterCanvasLayoutCategory then
			category = Settings.RegisterCanvasLayoutCategory(optionsFrame, optionsFrame.name)
			Settings.RegisterAddOnCategory(category)
		elseif InterfaceOptions_AddCategory then
			InterfaceOptions_AddCategory(optionsFrame)
		end
	end)
end

local function OpenOptions()
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
	elseif optionsFrame and InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(optionsFrame)
		InterfaceOptionsFrame_OpenToCategory(optionsFrame)
	else
		TogglePanel()
	end
end

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------

local function Debug()
	local log = { date("%Y-%m-%d %H:%M:%S") .. (InCombatLockdown() and " (in combat)" or " (not in combat)") }
	local function P(s) Print(s); log[#log + 1] = s end
	local r = GamepadReticle
	P("GamepadReticle: " .. (r and "found" or "NOT found"))
	if r then
		P(string.format("  shown=%s visible=%s alpha=%.2f hooked=%s",
			tostring(r:IsShown()), tostring(r:IsVisible()), r:GetAlpha(), tostring(hooked)))
		local icon = r.Icons and r.Icons.StandardIcon
		if icon then
			local w, h = icon:GetSize()
			P(string.format("  StandardIcon: alpha=%.2f size=%.0fx%.0f", icon:GetAlpha(), w, h))
		else
			P("  StandardIcon: NOT found")
		end
		P("  SwingTimer: " .. (r.SwingTimer and "found" or "NOT found"))
		P("  parts (key, type, visible, alpha):")
		local function Dump(obj, path, depth)
			if depth > 3 then return end
			for k, v in pairs(obj) do
				if type(k) == "string" and type(v) == "table" and v ~= obj
					and type(v.GetObjectType) == "function" and v ~= overlay then
					local ok, objType = pcall(v.GetObjectType, v)
					if ok then
						local vis = v.IsVisible and v:IsVisible()
						local a = v.GetAlpha and v:GetAlpha() or 1
						P(string.format("    %s.%s  %s  %s  %.2f", path, k, objType, tostring(vis), a))
						Dump(v, path .. "." .. k, depth + 1)
					end
				end
			end
		end
		Dump(r, "R", 1)
	end
	P(string.format("  settings: hidden=%s showWhen=%s colorByReaction=%s shape=%s alpha=%.2f size=%d outline=%d",
		tostring(db.hidden), db.showWhen, tostring(db.colorByReaction), db.shape, db.alpha, db.size, db.outline))
	P(string.format("  state: inCombat=%s hasTarget=%s shouldHide=%s",
		tostring(inCombat), tostring(HasTarget()), tostring(ShouldHide())))
	local found = LoadedConflicts()
	P("  conflicting addons: " .. (#found > 0 and table.concat(found, ", ") or "none"))
	db.lastDebug = log
	Print("saved to ControllerDotDB.lastDebug (do /reload to write it to disk)")
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_CONTROLLERDOT1 = "/dot"
SLASH_CONTROLLERDOT2 = "/controllerdot"
SlashCmdList.CONTROLLERDOT = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	local say

	if cmd == "off" then
		db.hidden = true
		say = "reticle off."
	elseif cmd == "on" then
		db.hidden = false
		say = "reticle on."
	elseif cmd == "toggle" then
		db.hidden = not db.hidden
		say = db.hidden and "reticle off." or "reticle on."
	elseif cmd == "reset" then
		ResetSettings()
		say = "settings reset (reticle stays " .. (db.hidden and "off" or "on") .. ")."
	elseif cmd == "show" then
		if SHOW_WHEN_NAMES[arg] then
			db.showWhen = arg
			say = "show when: " .. SHOW_WHEN_NAMES[arg]:lower() .. "."
		else
			Print("current: " .. (SHOW_WHEN_NAMES[db.showWhen] or db.showWhen)
				.. ". Usage: /dot show " .. table.concat(SHOW_WHEN, "|"))
			return
		end
	elseif cmd == "debug" then
		Debug()
		return
	elseif cmd == "options" then
		OpenOptions()
		return
	elseif cmd == "help" then
		Print("/dot - small settings window, /dot options - Blizzard options page")
		Print("/dot on|off|toggle, /dot show " .. table.concat(SHOW_WHEN, "|") .. ", /dot reset, /dot debug")
		return
	else
		TogglePanel()
		return
	end

	Apply()
	RefreshAll()
	Print(say)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
-- not present on every client
for _, ev in ipairs({ "GAME_PAD_ACTIVE_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_FRIEND_CHANGED" }) do
	pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			ControllerDotDB = ControllerDotDB or {}
			db = ControllerDotDB
			for k, v in pairs(defaults) do
				if db[k] == nil then db[k] = v end
			end
			BuildOptions()
		end
		return
	end
	if not db then return end

	if event == "PLAYER_LOGIN" then
		local found = LoadedConflicts()
		if #found > 0 then
			Print("|cffff5555" .. table.concat(found, ", ") .. " is also enabled and hides the reticle. Disable it, or ControllerDot's settings will have no visible effect.|r")
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		inCombat = true
		Apply()
	elseif event == "PLAYER_REGEN_ENABLED" then
		inCombat = false
		Apply()
	elseif event == "PLAYER_TARGET_CHANGED" or event:find("^PLAYER_SOFT_") then
		if db.colorByReaction or db.showWhen == "target" then Apply() end
	else
		-- PLAYER_ENTERING_WORLD, GAME_PAD_ACTIVE_CHANGED
		inCombat = UnitAffectingCombat("player") and true or false
		Apply()
		-- in case the reticle is created a bit later
		C_Timer.After(2, Apply)
	end
end)
