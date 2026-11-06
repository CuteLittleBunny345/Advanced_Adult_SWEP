- Power wheel for a possessed Alex Mercer = Prototype's own powersHUD (protohud.gfx), played back with the
-- game's textures and timelines (lua/alex_mercer/swfplayer.lua + hud_powershud.lua, tools/hudexport.py).
-- Hold the wheel key (G by default): the ring plays its INTRO (the world keeps running, the game has no slow motion
-- here); move the mouse toward a power (the red pointer follows, the ring leans in under it), release the key or
-- click to take it. Picking the active
-- power again turns it off (back to the normal form), as in the game. Number keys 1-9 still pick directly.
include("alex_mercer/swfplayer.lua")
include("alex_mercer/hud_powershud.lua")

local SWF = ALEX_MERCER_SWF
local WHEEL_KEY = CreateClientConVar("alex_mercer_wheel_key", tostring(KEY_G), true, false,
	"Клавиша колеса мутаций Alex Mercer (номер KEY_*, по умолчанию G)")

-- Node layout straight from the movie's init script (GotoAndStopHelper(node, power)): attack powers on
-- top, senses on the right, defence at the bottom, the two disguise slots on the left. Our forms take
-- the same nodes: the disguise slots hold the normal form (ALEX) and the disguise (the last one consumed: PEDESTRIAN /
-- MILITARY, locked until then); the cut power AlexSpines took the Infected Vision slot (6).
local NODES = {
	[0] = {form = 2, icon = "AlexClaws"},
	[1] = {form = 4, icon = "AlexHammerFist"},
	[2] = {form = 6, icon = "AlexMuscleMass"},
	[3] = {form = 5, icon = "AlexWhipFist"},
	[4] = {form = 3, icon = "AlexBlades"},
	-- (user 2026-10-29) the Senses: toggled over the attack power (alex_mercer_vision.lua), as the game's own slot
	[5] = {icon = "AlexThermalVision", vision = "thermal", name = "Thermal Vision"},
	-- (user 2026-10-22: the spines are not in the game - out) the slot back to the movie's own Infected Vision
	[6] = {icon = "AlexMotherVision", vision = "infected", name = "Infected Vision"},
	[7] = {form = 7, icon = "AlexShield"},
	[8] = {form = 8, icon = "AlexArmour"},
	[9] = {form = 1, icon = "ALEX"},
	[10] = {form = 10, icon = "PEDESTRIAN", disguise = true, name = "Disguise", locked = true},
}

local wheel, open, hovered, nodePos
local stick = Vector(0, 0, 0)
local frozenAngles

-- The ring leans toward the power under the pointer as if pressed in on that side; a new choice pushes it further
-- in and it springs back, the chosen node dips like a button.
local TILT, KICK = 11, 85 -- lean toward the hovered power (deg) / push on a new choice (deg/s)
local tilt, tiltVel = Vector(0, 0, 0), Vector(0, 0, 0) -- x, y: lean toward that screen direction (deg)
local press = {} -- node -> RealTime() of its dip
local PRESS_T, PRESS_DEPTH = 0.22, 0.1

local function nodeDir(n)
	local a = nodePos and nodePos[n]
	if not a then return end
	a = math.rad(a)
	return Vector(math.cos(a), math.sin(a), 0)
end

local function tiltThink(dt)
	local target = Vector(0, 0, 0)
	local d = open and hovered ~= nil and nodeDir(hovered)
	if d then target = d * TILT end
	dt = math.min(dt, 0.05)
	tiltVel = tiltVel + ((target - tilt) * 230 - tiltVel * 21) * dt
	tilt = tilt + tiltVel * dt
end

-- screen-space projection of the leaning ring (swfplayer SWF.Proj), pivot = the movie's origin
local function leanProjection(cx, cy)
	local len = tilt:Length()
	if len < 0.05 then return end
	-- rotating about k = (dy, -dx, 0) moves the point (dx, dy) away from the viewer
	local kx, ky = tilt.y / len, -tilt.x / len
	local th = math.rad(len)
	local c, s = math.cos(th), math.sin(th)
	local t = 1 - c
	return {cx = cx, cy = cy, f = ScrH() * 1.1, r = {
		c + kx * kx * t, kx * ky * t, ky * s,
		kx * ky * t, c + ky * ky * t, -kx * s,
		-ky * s, kx * s, c}}
end

local function possessedMercer()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply.DrG_GetPossessing then return end
	local ent = ply:DrG_GetPossessing()
	if IsValid(ent) and ent:GetClass() == "drg_alex_mercer" then return ent end
end

local function forms() return ALEX_MERCER_FORMS or {} end

local function sendForm(index, quick)
	net.Start("alex_mercer_form")
	net.WriteUInt(index, 8)
	net.WriteBool(quick or false)
	net.SendToServer()
end

local function nodeOf(form)
	for n, nd in pairs(NODES) do
		if nd.form == form then return n end
	end
end

-- the armour is the defence slot, worn over the attack power: its node is lit on its own
local function armourOn(ent)
	return ent ~= nil and ALEX_MERCER_ARMOUR ~= nil and ent:GetNW2Int("MercerDefense", 0) == ALEX_MERCER_ARMOUR
end

local function isActive(ent, n)
	if n == nil or not ent then return false end
	local nd = NODES[n]
	if nd and nd.vision then return ALEX_MERCER_VISION_MODE ~= nil and ALEX_MERCER_VISION_MODE() == nd.vision end
	if nd and nd.form == ALEX_MERCER_ARMOUR then return armourOn(ent) end
	-- (the shield worn over the attack power: its node lit by its own flag)
	if nd and ALEX_MERCER_SHIELD and nd.form == ALEX_MERCER_SHIELD and ent:GetNW2Bool("MercerShieldOn") then return true end
	-- (the disguise is a layer over the attack power too: lit by its own flag)
	if nd and ALEX_MERCER_DISGUISE and nd.form == ALEX_MERCER_DISGUISE then return ent:GetNW2Bool("MercerDisguised") end
	return n == nodeOf(ent:GetNW2Int("MercerForm", 1))
end

local function nodeName(n)
	local nd = NODES[n]
	if not nd then return "" end
	if nd.locked then return (nd.name or "") .. " - locked" end
	if nd.vision then return nd.name end
	local f = forms()[nd.form]
	return f and (f.label or f.name) or ""
end

-- the game's ChangeIconDiskBG(node, frame): node state + its disk (selectWedge) only while ACTIVATED
local function diskBG(n, frame)
	if not wheel or n == nil then return end
	local node = wheel:Child("powerring.Node" .. n)
	if node then node:GotoAndStop(frame) end
	local wedge = wheel:Child("powerring.selectWedge" .. n)
	if wedge then wedge.visible = frame == "ACTIVATED" end
end

-- GotoAndStopHelper(node, iconFrame): idle icon + selected-icon outline
local function setIcon(n, nd)
	for _, part in ipairs({"icon", "mcSelectedIcon"}) do
		local ic = wheel:Child("powerring.Node" .. n .. "." .. part)
		if ic then
			local label = nd.locked and "Locked" or nd.icon
			if not ic:GotoAndStop(label) then
				ic:GotoAndStop("NONE")
				ic.override = part == "icon" and nd.override or nd.overrideSel
			else
				ic.override = nil
			end
		end
	end
end

surface.CreateFont("AlexMercerPowerName", {font = "Bahnschrift SemiBold Condensed", size = 30, weight = 600, extended = true})
local fontScale

local function ensureFont(scale)
	if fontScale == scale then return end
	fontScale = scale
	surface.CreateFont("AlexMercerPowerName", {font = "Bahnschrift SemiBold Condensed",
		size = math.max(14, math.floor(25 * scale + 0.5)), weight = 600, extended = true, antialias = true})
end

local function build()
	local movie = ALEX_MERCER_HUD and ALEX_MERCER_HUD.powersHUD
	if not movie then return end
	wheel = SWF.New(movie)
	-- Initialize(): hide every disk, put the icons in place
	for i = 0, 10 do
		local w = wheel:Child("powerring.selectWedge" .. i)
		if w then w.visible = false end
		setIcon(i, NODES[i])
	end
	-- node positions inside powerring (for picking by direction)
	nodePos = {}
	local ring = movie.sprites[100]
	for _, e in ipairs(ring and ring.frames[1] or {}) do
		local n = e.n and tonumber(string.match(e.n, "^Node(%d+)$"))
		if n and e.m then nodePos[n] = math.deg(math.atan2(e.m[6], e.m[5])) end
	end
	-- the power-name text field draws with our font (the game's TitleFont has no Cyrillic)
	wheel.drawText = function(name, tx, m, cx)
		if name ~= "PowerNameText" or not wheel.nameText or wheel.nameText == "" then return end
		local r = tx.rect
		local x, y = SWF.Project(SWF.Apply(m, (r[1] + r[2]) / 2, (r[3] + r[4]) / 2))
		local a = cx and cx[4] or 1
		if a <= 0.01 then return end
		draw.SimpleTextOutlined(wheel.nameText, "AlexMercerPowerName", x, y, Color(255, 255, 255, 255 * a),
			TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200 * a))
	end
end

local function hover(n)
	if n == hovered then return end
	-- RemoveLastHighlight(): back to ACTIVATED if it is the active power, else IDLE
	if hovered ~= nil then
		diskBG(hovered, isActive(possessedMercer(), hovered) and "ACTIVATED" or "IDLE")
	end
	hovered = n
	if n ~= nil then
		diskBG(n, "SELECTED")
		local d = nodeDir(n)
		if d then tiltVel = tiltVel + d * KICK end
		press[n] = RealTime()
		-- (user 2026-10-29: "the wheel's sounds are not the game's") the HUD's own: boot_strap.p3d ui_hud_power_nav
		surface.PlaySound("mercer/fx/ui_hud_power_nav_05.wav")
	end
	if wheel then
		wheel.nameText = n ~= nil and nodeName(n) or ""
		local ptr = wheel:Child("powerring.mcSelectionArt.mcPointerWedge")
		if ptr then
			ptr.visible = n ~= nil
			if n ~= nil and nodePos[n] then ptr.rotation = nodePos[n] end
		end
	end
end

local function showWheel(ent)
	if not wheel then build() end
	if not wheel then return end
	open = true
	stick = Vector(0, 0, 0)
	frozenAngles = LocalPlayer():EyeAngles()
	hovered = nil
	-- the disguise slot: the last one consumed (its icon PEDESTRIAN / MILITARY), locked until someone was
	local dn = NODES[10]
	local kind = ent:GetNW2String("MercerDisguiseKind", "")
	dn.locked, dn.icon = kind == "", kind ~= "" and kind or "PEDESTRIAN"
	setIcon(10, dn)
	-- ShowPowerWheel(true, activePower...): every node IDLE, the active one ACTIVATED, then INTRO
	for i = 0, 10 do diskBG(i, isActive(ent, i) and "ACTIVATED" or "IDLE") end
	local active = nodeOf(ent:GetNW2Int("MercerForm", 1))
	wheel.nameText = active and nodeName(active) or ""
	local ptr = wheel:Child("powerring.mcSelectionArt.mcPointerWedge")
	if ptr then ptr.visible = false end
	wheel:GotoAndPlay("INTRO")
	tilt, tiltVel = Vector(0, 0, 0), Vector(0, 0, 0)
	press = {}
	-- (no opening sound in the game's HUD bank: the first node hovered plays ui_hud_power_nav)
end

local function closeWheel(take)
	if not open then return end
	open = false
	local ent = possessedMercer()
	if take and hovered ~= nil and ent then
		local nd = NODES[hovered]
		if nd and nd.vision and ALEX_MERCER_VISION_TOGGLE then
			-- (the request plays the HUD's select / deselect itself, once - alex_mercer_vision.lua)
			ALEX_MERCER_VISION_TOGGLE(nd.vision)
			press[hovered] = RealTime()
		elseif nd and not nd.locked and nd.form then
			local cur = ent:GetNW2Int("MercerForm", 1)
			-- the game toggles: choosing the active power again turns it off (the armour toggles on the server: it is
			-- worn over the attack power)
			local want = (nd.form == cur and nd.form ~= ALEX_MERCER_ARMOUR and nd.form ~= ALEX_MERCER_DISGUISE) and 1 or nd.form
			sendForm(want)
			-- the HUD's ui_hud_power_select on a power taken, ui_hud_power_deselect on the power put away (back to the
			-- normal form)
			local away = want == 1 or (nd.form == ALEX_MERCER_SHIELD and ent:GetNW2Bool("MercerShieldOn"))
			surface.PlaySound(away and "mercer/fx/ui_hud_power_deselect.wav" or "mercer/fx/ui_hud_power_select_04.wav")
			press[hovered] = RealTime()
			local d = nodeDir(hovered)
			if d then tiltVel = tiltVel + d * KICK end
		end
	end
	hovered = nil
	if wheel then wheel:GotoAndPlay("OUTRO") end
	-- (no closing sound in the game's HUD bank)
end

hook.Add("Think", "AlexMercerWheel", function()
	local ent = possessedMercer()
	local down = ent ~= nil and input.IsButtonDown(WHEEL_KEY:GetInt()) and not vgui.CursorVisible()
	if down and not open then
		showWheel(ent)
	elseif open and (not down or not ent) then
		closeWheel(ent ~= nil)
	end
	if wheel then
		wheel:Advance(RealFrameTime())
		tiltThink(RealFrameTime())
	end
end)

-- while the wheel is open the mouse moves a virtual stick instead of the camera, attacks are held back;
-- a click takes the power under the pointer
hook.Add("CreateMove", "AlexMercerWheel", function(cmd)
	if not open then return end
	stick.x = stick.x + cmd:GetMouseX() * 0.6
	stick.y = stick.y + cmd:GetMouseY() * 0.6
	local len = stick:Length()
	if len > 120 then stick = stick * (120 / len) end
	if frozenAngles then cmd:SetViewAngles(frozenAngles) end
	cmd:SetMouseX(0)
	cmd:SetMouseY(0)
	if cmd:KeyDown(IN_ATTACK) then
		cmd:RemoveKey(IN_ATTACK)
		if not open then return end
		timer.Simple(0, function() closeWheel(true) end)
	end
	cmd:RemoveKey(IN_ATTACK2)
	cmd:RemoveKey(IN_JUMP)
	cmd:RemoveKey(IN_RELOAD)
	-- pick by direction (dead zone in the middle keeps the current choice)
	if stick:Length() > 35 and nodePos then
		local ang = math.deg(math.atan2(stick.y, stick.x))
		local best, bestD
		for n, a in pairs(nodePos) do
			local d = math.abs(math.AngleDifference(ang, a))
			if not bestD or d < bestD then best, bestD = n, d end
		end
		hover(best)
	end
end)

hook.Add("HUDPaint", "AlexMercerWheel", function()
	if not wheel then return end
	local sp = wheel:Sprite()
	-- hidden at IDLE / after OUTRO (frames 1 and 27 stop the movie with the ring transparent)
	if not open and (wheel.frame == 1 or wheel.frame >= 27) then return end
	local s = ScrH() / 720
	ensureFont(s)
	local cx, cy = ScrW() / 2, ScrH() * 355.8 / 720
	local m = {s, 0, 0, s, cx, cy}
	-- the chosen node's dip
	local now = RealTime()
	for n, t0 in pairs(press) do
		local node = wheel:Child("powerring.Node" .. n)
		local t = now - t0
		if t >= PRESS_T or not node then
			press[n] = nil
			if node then node.scale = nil end
		else
			node.scale = 1 - PRESS_DEPTH * math.sin(math.pi * t / PRESS_T)
		end
	end
	SWF.Proj = leanProjection(cx, cy)
	render.PushFilterMag(TEXFILTER.ANISOTROPIC)
	render.PushFilterMin(TEXFILTER.ANISOTROPIC)
	wheel:Draw(m)
	render.PopFilterMin()
	render.PopFilterMag()
	SWF.Proj = nil
end)

-- (the mutation name at the bottom of the screen is gone - user: "мне совсем не нравится это"; removed here too so an
-- autorefresh drops the old hook)
hook.Remove("HUDPaint", "AlexMercerFormName")

-- 1-9: quick select (the slot binds would otherwise switch weapons).
hook.Add("PlayerBindPress", "AlexMercerQuickSelect", function(ply, bind, pressed)
	if not pressed or not possessedMercer() then return end
	local slot = tonumber(string.match(bind, "^slot(%d)$"))
	-- the Senses powers (alex_mercer_vision.lua): 9 = Thermal Vision, 0 = Infected Vision
	if (slot == 9 or slot == 0) and ALEX_MERCER_VISION_TOGGLE then
		-- (one request at a time: presses while one is on its way do nothing - alex_mercer_vision.lua)
		ALEX_MERCER_VISION_TOGGLE(slot == 9 and "thermal" or "infected")
		return true
	end
	if slot and forms()[slot] then
		-- (user 2026-10-29: the HUD's sounds on the number keys too) the key toggles like the wheel: the active power
		-- again = the normal form (deselect), else the power taken (select)
		local ent = possessedMercer()
		local cur = ent:GetNW2Int("MercerForm", 1)
		local want = (slot == cur and slot ~= ALEX_MERCER_ARMOUR and slot ~= ALEX_MERCER_DISGUISE) and 1 or slot
		-- (user 2026-11-03: "a quick shield as in the game") the shield's key: out at once, the game's quick transform -
		-- no showcase anim; the wheel's choice still plays it, standing still
		local shield = slot == ALEX_MERCER_SHIELD
		sendForm(want, shield)
		local away = want == 1 or (shield and ent:GetNW2Bool("MercerShieldOn"))
		surface.PlaySound(away and "mercer/fx/ui_hud_power_deselect.wav" or "mercer/fx/ui_hud_power_select_04.wav")
		return true
	end
end)
-