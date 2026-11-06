- Prototype's minimap, the game's own minimapHUD (protohud.gfx -> tools/hudexport.py minimapHUD ->
-- lua/alex_mercer/hud_minimaphud.lua + materials/alex_mercer/hud/*), played by lua/alex_mercer/swfplayer.lua.
-- The game's engine fills its "map" with the drawn Manhattan; here the circle shows the GMod map under him from above,
-- whatever the map. An orthographic camera looks straight down, north up, over a wider square than the disc shows,
-- RT_HZ times a second; each frame the disc samples it turned to the view and shifted by how far he moved since -
-- so it turns and slides smoothly. Outdoors the camera sits high (under the sky: the buildings read as dark blocks,
-- the game's schematic); with a ceiling right over him it stays under it (rooms show their floor). Greyed into the
-- game's look. Marks: the people around him. The movie's ring / overlay over it; its player arrow turns with his
-- facing, its north tag round the ring. Placement: minimapHUD at (169.45, 592) on the 1280 x 720 stage, locked left /
-- bottom (AdjustForScreenDimensions: mHLock LOCK_MIN, mVLock LOCK_MAX). Drawn by ENT:PossessionHUD.
include("alex_mercer/swfplayer.lua")
include("alex_mercer/hud_minimaphud.lua")
include("alex_mercer/hud_awarenesshud.lua")
include("alex_mercer/hud_perceptionhud.lua")
ALEX_MERCER_MINIMAP = ALEX_MERCER_MINIMAP or {}
local M = ALEX_MERCER_MINIMAP
local SWF = ALEX_MERCER_SWF
local MOVIE = ALEX_MERCER_HUD and ALEX_MERCER_HUD.minimapHUD

local Enabled = CreateClientConVar("alex_mercer_minimap", "1", true, false, "Alex Mercer: the game's minimap (1 = on)")

local HUD_X, HUD_BOTTOM = 169.45, 720 - 592 -- (x from the left, y from the bottom of the 1280 x 720 stage)
local CX, CY, R_MAP = 5, -1.5, 67 -- the ring's centre and the map disc's radius in the movie (60 left a gap: the ring's inner edge is ~67.6, measured on the user's screenshot)
-- (user 2026-10-28: "bigger - the circle and the map in it, too much space shown") the minimap drawn x SIZE about its
-- ring's centre; VIEW_R 1800 -> 1100
local SIZE = 1.15 -- (1.35 was too big)
local VIEW_R = 1100 -- world units from his place to the disc's edge (~28 m)
local RT_R = VIEW_R + 1080 -- the snapshot's half size: the round disc turns inside it, 1080 units left for the slide
local INDOOR = 400 -- a ceiling closer than this over him = indoors: the camera stays under it
-- (user 2026-10-28: since the minimap, the effects and anims went jerky - 20 full scene renders a second, the
-- particles drawn - and stepped - in them too) 10 snapshots a second, of the map's brushes only (M.rendering hooks)
local RT_SIZE, RT_HZ = 512, 10
local SHOT_MOVE, SHOT_T = 700, 3 -- (the disc is round: it turns inside RT_R - VIEW_R = 1080 units of margin)
local SEGS = 48

local rt, rtMat
local function target()
	if rt then return rt, rtMat end
	rt = GetRenderTarget("alex_mercer_minimap_rt2", RT_SIZE, RT_SIZE)
	-- (no alpha: the world writes nothing usable there - the disc was see-through)
	rtMat = CreateMaterial("alex_mercer_minimap_mat2", "UnlitGeneric", {["$basetexture"] = rt:GetName(),
		["$vertexcolor"] = 1, ["$ignorez"] = 1})
	return rt, rtMat
end

-- the game's schematic look: grey, contrasted, darkened
-- (user 2026-10-28: the darker try hid the dark places - back to the grey one)
local LOOK = {["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0, ["$pp_colour_brightness"] = -0.06,
	["$pp_colour_contrast"] = 1.45, ["$pp_colour_colour"] = 0.05, ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0,
	["$pp_colour_mulb"] = 0}

local lastRender, shotPos = 0, nil
-- the snapshot draws the world's brushes alone: no models, effects / particles, sky or the viewer
local function skip() if M.rendering then return true end end
hook.Add("PreDrawOpaqueRenderables", "AlexMercerMinimap", skip)
hook.Add("PreDrawTranslucentRenderables", "AlexMercerMinimap", skip)
hook.Add("PreDrawEffects", "AlexMercerMinimap", skip)
hook.Add("PreDrawSkyBox", "AlexMercerMinimap", skip)
hook.Add("PreDrawHalos", "AlexMercerMinimap", skip)
hook.Add("PrePlayerDraw", "AlexMercerMinimap", skip)
-- the camera's height: just under a near ceiling, else high under the sky (never above it: out of the world nothing draws)
local function cameraZ(pos)
	local up = util.TraceLine({start = pos + Vector(0, 0, 60), endpos = pos + Vector(0, 0, 4000), mask = MASK_SOLID_BRUSHONLY})
	if up.Hit and not up.HitSky and up.HitPos.z - pos.z < INDOOR then return up.HitPos.z - 8 end
	return math.min(up.HitPos.z - 16, pos.z + 3000)
end
local function shoot(ent)
	local tex = target()
	local pos = ent:GetPos()
	render.PushRenderTarget(tex)
	render.Clear(18, 18, 20, 255, true, true)
	-- north up: Angle(90, 90, 0) looks down with +Y at the top, +X at the right
	M.rendering = true
	render.RenderView({origin = Vector(pos.x, pos.y, cameraZ(pos)), angles = Angle(90, 90, 0), x = 0, y = 0, w = RT_SIZE,
		h = RT_SIZE, ortho = {left = -RT_R, right = RT_R, top = -RT_R, bottom = RT_R}, znear = 4, zfar = 40000,
		drawviewmodel = false, drawhud = false, dopostprocess = false, drawmonitors = false, bloomtone = false})
	M.rendering = false
	DrawColorModify(LOOK)
	render.PopRenderTarget()
	shotPos = pos
end

-- the disc: each rim point's world place (his place + the view-turned offset) looked up in the north-up snapshot
-- (2026-11-04: five Vectors a point, 240 a frame for the Lua collector: on plain numbers, the points kept)
local poly = {}
for i = 1, SEGS do poly[i] = {} end
local function disc(cx, cy, r, pos, fwd, rgt, mat)
	local px, py, fx, fy, rx, ry, sx, sy = pos.x, pos.y, fwd.x, fwd.y, rgt.x, rgt.y, shotPos.x, shotPos.y
	for i = 0, SEGS - 1 do
		local a = i / SEGS * math.pi * 2
		local c, s = math.cos(a), math.sin(a)
		local p = poly[i + 1]
		-- (screen up = the view's forward)
		p.x, p.y = cx + c * r, cy + s * r
		p.u, p.v = 0.5 + (px + (rx * c - fx * s) * VIEW_R - sx) / (2 * RT_R), 0.5 - (py + (ry * c - fy * s) * VIEW_R - sy) / (2 * RT_R)
	end
	surface.SetMaterial(mat)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawPoly(poly)
end

-- the people around him: NPCs / nextbots red, other players blue; a dot on the disc, clamped to its rim
local MARK_ENEMY, MARK_PLAYER = Color(235, 40, 30), Color(70, 150, 255)
local function marks(ent, cx, cy, r, s, pos, fwd, rgt)
	for _, e in ipairs(ents.FindInSphere(pos, VIEW_R * 1.3)) do
		if e ~= ent and IsValid(e) and (e:IsNPC() or e:IsNextBot() or (e:IsPlayer() and e ~= LocalPlayer() and e:Alive()))
			and not e:GetNoDraw() then
			local d = e:GetPos() - pos
			local sx, sy = d:Dot(rgt) / VIEW_R, -d:Dot(fwd) / VIEW_R
			local len = math.sqrt(sx * sx + sy * sy)
			if len > 0.92 then sx, sy = sx / len * 0.92, sy / len * 0.92 end
			local col = e:IsPlayer() and MARK_PLAYER or MARK_ENEMY
			local sz = 3.2 * s
			draw.RoundedBox(sz, cx + sx * r - sz, cy + sy * r - sz, sz * 2, sz * 2, col)
		end
	end
end

-- (user 2026-10-28: "the detection mark right of the minimap, yellow, showing the disguise change") the game's
-- awarenessHUD (protohud.gfx, at (266.1, 533.15) on the stage, left / bottom locked like the minimap): its lens
-- mcAwareness.mcLens plays IDLE / WATCHED (amber) / BLOWN (red) by NW2 MercerAware (0 safe, 1 hunted unseen,
-- 2 seen - the server's cover, ENT:MercerAwareThink), its mcShutter closes and opens on a change of look (NW2
-- MercerDisgSwapT); its meter mcAwareness.mcMeter.mcBar stands at the suspicion (NW2 MercerAwarePct, the game's
-- SetAwarenessPercent: gotoAndStop(percent)). (user: always on, as in the game - the lens shut when nothing's up)
-- Placed out with the minimap's SIZE from its ring's centre
local AWARE = ALEX_MERCER_HUD and ALEX_MERCER_HUD.awarenessHUD
if AWARE then AWARE.stencil = true end -- (its masks by their outlines: swfplayer.lua)
local AW_X, AW_Y = 266.1, 533.15
local LENS = {[0] = "IDLE", [1] = "WATCHED", [2] = "BLOWN"}
local aw, awState, awSwap, shutterOpenT, awPct
local function drawAwareness(ent)
	if not AWARE then return end
	local st = ent:GetNW2Int("MercerAware", 0)
	if not aw then
		aw, awState, awSwap, shutterOpenT = SWF.New(AWARE), nil, ent:GetNW2Float("MercerDisgSwapT", 0), nil
	end
	local lens = aw:Child("mcAwareness.mcLens")
	if lens and awState ~= st then
		local first = awState == nil
		awState = st
		lens:GotoAndPlay(LENS[st])
		-- (user 2026-10-28: "at rest it must not glow") the lens's frame scripts (build/as2_aw_506.txt), which this
		-- player doesn't run: IDLE -> shutter / red / amber CLOSE; WATCHED -> shutter OPEN, flare OPEN, red CLOSE,
		-- amber OPEN; BLOWN -> shutter OPEN, flare OPEN, red OPEN, amber CLOSE. The first time straight to the closed
		-- frames (no closing flash)
		local function go(name, label, closed)
			local c = aw:Child("mcAwareness.mcLens." .. name)
			if not c then return end
			if first and closed then c:GotoAndStop(closed) else c:GotoAndPlay(label) end
		end
		if st == 0 then
			go("mcShutter", "CLOSE", "CLOSED")
			go("mcRedFlare", "CLOSE", "CLOSED")
			go("mcAmberFlare", "CLOSE", "CLOSED")
			local fl = aw:Child("mcAwareness.mcLens.mcFlare")
			if fl then fl:GotoAndStop(0) end
		else
			go("mcShutter", "OPEN")
			go("mcFlare", "OPEN")
			go("mcRedFlare", st == 2 and "OPEN" or "CLOSE", st == 2 and nil or "CLOSED")
			go("mcAmberFlare", st == 1 and "OPEN" or "CLOSE", st == 1 and nil or "CLOSED")
		end
	end
	local swap = ent:GetNW2Float("MercerDisgSwapT", 0)
	if swap ~= awSwap then
		awSwap = swap
		-- (a blink of the shutter: shut and open again when open, open and shut again when shut - IDLE keeps it shut)
		local sh = aw:Child("mcAwareness.mcLens.mcShutter")
		if sh then sh:GotoAndPlay(st == 0 and "OPEN" or "CLOSE") end
		shutterOpenT = RealTime() + 0.4
	end
	local bar = aw:Child("mcAwareness.mcMeter.mcBar")
	-- (AS2's gotoAndStop(percent): frame `percent`, 1-based)
	-- (smooth: the server's 0.25 s steps followed per frame with an exponential ease - no steps, no constant-speed
	-- jumps; user: "smooth when it ebbs too")
	local target = ent:GetNW2Int("MercerAwarePct", 0)
	awPct = Lerp(1 - math.exp(-RealFrameTime() * 3), awPct or target, target)
	-- (the ease never quite arrives: at it within half a percent; the game's bar turns red only on its last frame -
	-- full - so a full meter must reach it - user 2026-10-28: "the line stays yellow")
	if math.abs(awPct - target) < 0.5 then awPct = target end
	-- (user 2026-10-28: "the line doesn't turn red at once") blown / seen by the hunters (BLOWN): full and red at once,
	-- the ease is only for the suspicion's climb and ebb
	if st == 2 then awPct = target end
	if bar then bar:GotoAndStop(math.Clamp(math.Round(awPct) - 1, 0, 99)) end
	if shutterOpenT and RealTime() >= shutterOpenT then
		shutterOpenT = nil
		local sh = aw:Child("mcAwareness.mcLens.mcShutter")
		if sh then sh:GotoAndPlay(st == 0 and "CLOSE" or "OPEN") end
	end
	local s0 = ScrH() / 720
	local s = s0 * SIZE
	local cxs, cys = HUD_X + CX, 720 - HUD_BOTTOM + CY -- (the ring's centre on the stage)
	local x = (cxs + (AW_X - cxs) * SIZE) * s0
	local y = ScrH() - (720 - (cys + (AW_Y - cys) * SIZE)) * s0
	aw:Advance(RealFrameTime())
	aw:Draw({s, 0, 0, s, x, y})
end

-- (user 2026-10-28: "show Mercer's icon with the consumed one's - the disguise") the game's perceptionHUD
-- (protohud.gfx at (101.8, 463.25), its AS2: SetDisguiseByName(slot, name) -> mcDisguise<slot>.mcIcon
-- gotoAndStop(name) (MILITARY / ALEX / PEDESTRIAN / TANK / HELICOPTER / NONE), a real look plays the slot's
-- mcSwitchOverlay and shows its BG, NONE hides the BG; ActivateAlarm / ActivateUnblown -> BG ALERT / SAFE).
-- The big slot (mcDisguise0) = the look he wears, the small one (mcDisguise1) = the other (Alex when disguised,
-- else the stored look or NONE); the cover blown / restored plays the big slot's ALERT / SAFE. mcHint (the console
-- d-pad hint) hidden
local PERC = ALEX_MERCER_HUD and ALEX_MERCER_HUD.perceptionHUD
if PERC then PERC.stencil = true end
local PC_X, PC_Y = 101.8, 463.25
local pc, pcIcons, pcBlown, pcOverlayT, pcPulseT
local function setSlot(slot, name, animate)
	local ic = pc:Child("mcDisguise" .. slot .. ".mcIcon")
	if ic then ic:GotoAndStop(name) end
	local bg = pc:Child("mcDisguise" .. slot .. ".BG")
	if bg then bg.hidden = name == "NONE" end
	local ov = pc:Child("mcDisguise" .. slot .. ".mcSwitchOverlay")
	if ov then
		ov.hidden = not (animate and name ~= "NONE")
		if not ov.hidden then
			ov:GotoAndPlay(0)
			pcOverlayT = RealTime() + 1
		end
	end
end
local function drawPerception(ent)
	if not PERC then return end
	local disg = ent:GetNW2Bool("MercerDisguised")
	local kind = ent:GetNW2String("MercerDisguiseKind", "")
	local other = kind ~= "" and kind or "NONE"
	local big, small = disg and other or "ALEX", disg and "ALEX" or other
	local first = not pc
	if first then
		pc, pcIcons, pcBlown, pcOverlayT = SWF.New(PERC), {}, false, nil
		local h = pc:Child("mcHint")
		if h then h.hidden = true end
	end
	if pcIcons[0] ~= big then setSlot(0, big, not first) pcIcons[0] = big end
	if pcIcons[1] ~= small then setSlot(1, small, false) pcIcons[1] = small end
	if pcOverlayT and RealTime() >= pcOverlayT then
		pcOverlayT = nil
		for _, sl in ipairs({0, 1}) do
			local ov = pc:Child("mcDisguise" .. sl .. ".mcSwitchOverlay")
			if ov then ov.hidden = true end
		end
	end
	-- (user 2026-10-28: "blown in disguise - the disguise burns red") while the look is blown its slot's BG pulses
	-- ALERT (the game's one-shot red pulse, replayed every 0.9 s): the big slot while he wears it, the small one once
	-- he is Mercer again; SAFE once the cover is back
	local blown = ent:GetNW2Bool("MercerBlown")
	local slot = disg and 0 or 1
	if blown and not first and (blown ~= pcBlown or RealTime() >= (pcPulseT or 0)) then
		pcPulseT = RealTime() + 0.9
		local bg = pc:Child("mcDisguise" .. slot .. ".BG")
		if bg then bg:GotoAndPlay("ALERT") end
	elseif not blown and pcBlown and not first then
		for _, sl in ipairs({0, 1}) do
			local bg = pc:Child("mcDisguise" .. sl .. ".BG")
			if bg then bg:GotoAndPlay("SAFE") end
		end
	end
	pcBlown = blown
	local s0 = ScrH() / 720
	local s = s0 * SIZE
	local cxs, cys = HUD_X + CX, 720 - HUD_BOTTOM + CY
	local x = (cxs + (PC_X - cxs) * SIZE) * s0
	local y = ScrH() - (720 - (cys + (PC_Y - cys) * SIZE)) * s0
	pc:Advance(RealFrameTime())
	pc:Draw({s, 0, 0, s, x, y})
end

local hud
function M.Draw(ent)
	if not IsValid(ent) then return end
	if not MOVIE or not Enabled:GetBool() then
		drawPerception(ent)
		return drawAwareness(ent)
	end
	local s0 = ScrH() / 720
	local s = s0 * SIZE
	-- (scaled about the ring's centre: the movie's origin moves so the centre stays where the game has it)
	local ox, oy = HUD_X * s0 + CX * (s0 - s), ScrH() - HUD_BOTTOM * s0 + CY * (s0 - s)
	local viewYaw = EyeAngles().y
	local pos = ent:GetPos()
	-- (user 2026-10-28: still uneven running in places - a snapshot of a dense city is heavy) the north-up snapshot
	-- needn't follow the turn: a new one only once he is SHOT_MOVE units from the last one's place, or every SHOT_T s
	if not shotPos or (RealTime() - lastRender >= 1 / RT_HZ
		and (pos:Distance2DSqr(shotPos) > SHOT_MOVE * SHOT_MOVE or RealTime() - lastRender >= SHOT_T)) then
		lastRender = RealTime()
		shoot(ent)
	end
	local va = Angle(0, viewYaw, 0)
	local fwd, rgt = va:Forward(), va:Right()
	local _, mat = target()
	local cx, cy, r = ox + CX * s, oy + CY * s, R_MAP * s
	disc(cx, cy, r, pos, fwd, rgt, mat)
	marks(ent, cx, cy, r, s, pos, fwd, rgt)
	if not hud then
		hud = SWF.New(MOVIE)
		hud:GotoAndPlay("INTRO")
	end
	-- the movie's own map image is the game's Manhattan, its markers the engine's: off
	local map = hud:Child("map")
	if map then map.hidden = true end
	-- the arrow: his facing against the view's (screen up = the view); the north tag: where +Y (the map's north) lies
	local pl = hud:Child("player")
	if pl then pl.rotation = -math.AngleDifference(ent:GetAngles().y, viewYaw) end
	local north = hud:Child("north")
	if north then north.rotation = -math.AngleDifference(90, viewYaw) end
	hud:Advance(RealFrameTime())
	hud:Draw({s, 0, 0, s, ox, oy})
	drawPerception(ent)
	drawAwareness(ent)
end
-