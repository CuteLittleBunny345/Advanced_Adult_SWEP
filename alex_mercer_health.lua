- Prototype's health bar, the game's own animated healthHUD (protohud.gfx -> tools/hudexport.py healthHUD --white 262
-- --blank 248,250,257 -> lua/alex_mercer/hud_healthhud.lua + materials/alex_mercer/hud/*), played by
-- lua/alex_mercer/swfplayer.lua. The movie's bar layers sit under masks its engine moves from code; here they follow
-- DrGBase's networked health and MercerCrit:
--   BGMask the whole bar, normHPMask / EKGMask the health (the left part, up to the critical mass marker at 674 of
--   305..905), damageHPMask the damage just taken (orange: waits 0.4 s, then drains), cMassMask the critical mass
--   (cyan, from the marker on: consuming past full health), gainHPMask the piece just gained.
-- Its ShowDevastatorDisplay states (normHealth, its critMassIndicator and mcIcon): Static, Surge (some critical
-- mass), SurgeWithDev (critical mass full), Critical (low health), Update_Health / Update_Crit while they rise,
-- then Done_Health / Done_Crit. The frame scripts' gotoAndPlay loops are set as sprite jumps. mcScanlines (pool
-- textures not shipped) hidden. Drawn by ENT:PossessionHUD (which keeps DrGBase's own bar away).
include("alex_mercer/swfplayer.lua")
include("alex_mercer/hud_healthhud.lua")
ALEX_MERCER_HEALTH = ALEX_MERCER_HEALTH or {}
local H = ALEX_MERCER_HEALTH
local SWF = ALEX_MERCER_SWF
local MOVIE = ALEX_MERCER_HUD and ALEX_MERCER_HUD.healthHUD

if MOVIE then
	local function jumps(id, t) if MOVIE.sprites[id] then MOVIE.sprites[id].jumps = t end end
	jumps(295, {[7] = "Static", [99] = "Surge", [189] = "SurgeWithDev", [245] = "Critical", [259] = "Update_Health",
		[273] = "Update_Crit"})
	jumps(256, {[39] = "Surge", [96] = "Critical"})
	jumps(275, {[38] = "Surge", [69] = "Critical"})
end

-- (user 2026-10-27: "the biomass filling the bar is too abrupt, smoother") a rise of the health / the critical mass
-- eases in (exponential, this time constant - about 0.5 s to settle); a drop stays instant (the damage trail shows it)
local RISE_TAU = 0.15
-- the bar's still shading (H.Draw): the edges' share of the filled length, the middle band's, the colours (with alpha)
local SHADE_ON = false
local SHADE_EDGE, SHADE_MID = 0.22, 0.3
local SHADE_HP, SHADE_CRIT = Color(70, 0, 0, 170), Color(0, 55, 75, 170)
local GRAD_L, GRAD_C = Material("gui/gradient"), Material("gui/center_gradient")
-- the health's running glow (its width in bar units, the time to cross, its colour) and the underline's thick parts
-- (the start step's length, their height below the bar, their colour) - read off the game's own bar
local GLOW_W, GLOW_T, GLOW_COL = 60, 1.8, Color(255, 40, 30, 200)
-- the biomass blink over the health: a pulse every BLINK_T s up to alpha BLINK_A, the critical mass's cyan
local BLINK_T, BLINK_ON, BLINK_A, BLINK_COL = 1.4, 0.4, 170, Color(0, 255, 255)
local BLINK_WHITE = Color(255, 255, 255, 255) -- the critical mass's own flash on the same pulse (alpha: its share)
local BLINK_OVER = 4 -- (bar units the flash reaches past the health, over the seam)
local BLINK_DX, BLINK_DY = 0, 0 -- (pixel nudge of the blink, should it still sit off)
local TRAIL_DELAY = 0.4 -- s the damage piece waits
local TRAIL_RATE = 0.6 -- of the health part per second as it drains
local GAIN_TIME = 0.6 -- s the gain piece shows
local UPD_TIME = 0.5 -- s an Update_ state holds after the last rise
local DONE_TIME = 14 / 30 -- the Done_ states' 14 frames
local X0, XC, X1 = 305, 674, 905 -- the bar in normHealth: health X0..XC, critical mass XC..X1
local HUD_X, HUD_Y = 82.85, 47.25 -- healthHUD on the 1280 x 720 stage

local function play(inst, lab)
	if inst and not inst:GotoAndPlay(lab) and lab == "SurgeWithDev" then inst:GotoAndPlay("Surge") end
end

local state = setmetatable({}, {__mode = "k"})
function H.Draw(ent)
	if not MOVIE then return end
	local s = ScrH() / 720
	local maxhp = math.max(1, ent:GetNW2Int("DrGBaseMaxHealth", ent:GetMaxHealth()))
	local hp = math.Clamp(ent:GetNW2Int("DrGBaseHealth", ent:Health()), 0, maxhp)
	local f = hp / maxhp
	local crit = math.Clamp(ent:GetNW2Float("MercerCrit", 0), 0, 1)
	local now = CurTime()
	local st = state[ent]
	if not st then
		st = {shown = f, trail = f, hold = 0, gainT = -10, gainFrom = f, crit = crit, critUpT = -10, hud = SWF.New(MOVIE),
			fEase = f, critEase = crit}
		state[ent] = st
	end
	-- the eased values the bar draws (rises only)
	local k = 1 - math.exp(-RealFrameTime() / RISE_TAU)
	st.fEase = f < st.fEase and f or Lerp(k, st.fEase, f)
	st.critEase = crit < st.critEase and crit or Lerp(k, st.critEase, crit)
	local fDraw, critDraw = st.fEase, st.critEase
	if f < st.shown - 0.0005 then st.hold = now + TRAIL_DELAY end
	if f > st.shown + 0.002 then st.gainT, st.gainFrom = now, math.min(st.gainFrom, st.shown) end
	if now - st.gainT > GAIN_TIME then st.gainFrom = f end
	st.shown = f
	if f >= st.trail then
		st.trail = f
	elseif now > st.hold then
		st.trail = math.max(f, st.trail - TRAIL_RATE * FrameTime())
	end
	if crit > st.crit + 0.002 then st.critUpT = now end
	-- (user 2026-10-27: "the biomass should go away nicely" - it shields the health now) its lost piece as the health's:
	-- the orange damage layer stays on it 0.4 s, then drains at the same rate
	st.critTrail = st.critTrail or crit
	if crit < st.crit - 0.0005 then st.critHold = now + TRAIL_DELAY end
	if crit >= st.critTrail then
		st.critTrail = crit
	elseif now > (st.critHold or 0) then
		st.critTrail = math.max(crit, st.critTrail - TRAIL_RATE * FrameTime())
	end
	st.crit = crit

	-- the display state
	local hud = st.hud
	-- (user 2026-10-28: SurgeWithDev paints the whole bar solid cyan, the health hidden - the blue blink is drawn by
	-- H.Draw over everything instead) the bar keeps Surge; the indicator / icon below still take the crit states
	-- (user: no animation) Surge = the heartbeat (EKG spike + the hood pulsing) is the normal state; Static is still
	local base = f < 0.25 and "Critical" or "Surge"
	local want = base
	if now - st.critUpT < UPD_TIME then
		want = "Update_Crit"
	elseif now - st.gainT < UPD_TIME then
		want = "Update_Health"
	elseif st.mode == "Update_Crit" or st.mode == "Update_Health" then
		want = st.mode == "Update_Crit" and "Done_Crit" or "Done_Health"
	elseif (st.mode == "Done_Crit" or st.mode == "Done_Health") and now - (st.modeT or 0) < DONE_TIME then
		want = st.mode
	end
	local nh = hud:Child("normHealth")
	if want ~= st.mode then
		st.mode, st.modeT = want, now
		-- (user 2026-10-27: "from the second consume the whole bar is blue - the real health doesn't show") the bar itself
		-- never takes SurgeWithDev's all-cyan look: the health keeps its colour, the critical mass its own cyan part;
		-- the indicator and the icon still show the devastator ready
		-- (user 2026-10-28: "take the pulse animation off the bar") the bar itself is Static instead of Surge (its EKG
		-- heartbeat); the icon / indicator keep their states
		play(nh, want == "Surge" and "Static" or want)
		play(nh and nh:Child("critMassIndicator"), want)
		play(hud:Child("mcIcon"), want)
	end

	-- the masks
	if nh then
		local W = XC - X0
		local function span(name, a, b)
			local k = nh:Child(name)
			if k then
				local c = k.clipX
				if c then
					c[1], c[2] = a, b
				else
					k.clipX = {a, b}
				end
			end
		end
		-- (user: too long, full health filled only part of it) the bar (its background + underline) ends where full
		-- health does; critical mass grows it on to the right
		-- (the critical mass's damage piece: the orange layer reaches on past the marker to its trail)
		local critBar = math.max(critDraw, st.critTrail)
		span("BGMask", X0, XC + (X1 - XC) * critBar)
		span("damageHPMask", X0, st.critTrail > critDraw + 0.001 and XC + (X1 - XC) * st.critTrail or X0 + W * st.trail)
		span("cMassMask", XC, XC + (X1 - XC) * critDraw)
		-- (user 2026-10-28, the game's bar: the thick strip under the critical mass, stepping out at its start) the
		-- movie's own critMassBottomMask, never opened before
		span("critMassBottomMask", XC, XC + (X1 - XC) * critDraw)
		span("normHPMask", X0, X0 + W * fDraw)
		span("EKGMask", X0, X0 + W * fDraw)
		if now - st.gainT < GAIN_TIME then
			span("gainHPMask", X0 + W * st.gainFrom, X0 + W * fDraw)
		else
			span("gainHPMask", X0, X0)
		end
		local sl = nh:Child("mcScanlines")
		if sl then sl.hidden = true end
	end
	hud:Advance(RealFrameTime())
	hud:Draw({s, 0, 0, s, HUD_X * s, HUD_Y * s})

	-- (user 2026-10-28: "a still gradient - at the start, the middle and the end, a colour darker than the red bar; the
	-- same on the biomass, darker") over each filled part: a dark edge fading in from its start, a soft dark band in its
	-- middle, a dark edge fading out to its end - dark red on the health, dark teal on the critical mass. The bar: the
	-- 600 x 10 quad at normHealth (305, -10), normHealth at (-238, 34) in healthHUD
	local ox, oy = HUD_X - 238, HUD_Y + 34
	local function shade(a, b, col)
		local w = b - a
		if w <= 1 then return end
		local y0, h = (oy - 10) * s, 10 * s
		render.SetScissorRect(math.floor((ox + a) * s), math.floor(y0), math.ceil((ox + b) * s), math.ceil(y0 + h), true)
		surface.SetDrawColor(col.r, col.g, col.b, col.a)
		local e = w * SHADE_EDGE
		surface.SetMaterial(GRAD_L) -- (opaque on its left, clear on its right)
		surface.DrawTexturedRect((ox + a) * s, y0, e * s, h)
		surface.DrawTexturedRectRotated((ox + b - e * 0.5) * s, y0 + h * 0.5, e * s, h, 180)
		surface.SetMaterial(GRAD_C)
		local m = w * SHADE_MID
		surface.DrawTexturedRect((ox + a + (w - m) * 0.5) * s, y0, m * s, h)
		render.SetScissorRect(0, 0, 0, 0, false)
	end
	local hpEnd = X0 + (XC - X0) * fDraw
	-- (user 2026-10-28: the dark shading is out - SHADE_ON brings it back)
	if SHADE_ON then
		shade(X0, hpEnd, SHADE_HP)
		if critDraw > 0.001 then shade(XC, XC + (X1 - XC) * critDraw, SHADE_CRIT) end
	end
	-- (user 2026-10-28, the game's own bar: a bright red glow keeps running right along the health) the glow: a
	-- GLOW_W-wide band crossing the health every GLOW_T s, additive-looking bright red, clipped to the health part
	if hpEnd > X0 + 2 then
		local y0, h = (oy - 10) * s, 10 * s
		local span = hpEnd - X0 + GLOW_W
		local c = X0 - GLOW_W * 0.5 + (RealTime() % GLOW_T) / GLOW_T * span
		render.SetScissorRect(math.floor((ox + X0) * s), math.floor(y0), math.ceil((ox + hpEnd) * s), math.ceil(y0 + h), true)
		surface.SetMaterial(GRAD_C)
		surface.SetDrawColor(GLOW_COL.r, GLOW_COL.g, GLOW_COL.b, GLOW_COL.a)
		surface.DrawTexturedRect((ox + c - GLOW_W * 0.5) * s, y0, GLOW_W * s, h)
		render.SetScissorRect(0, 0, 0, 0, false)
	end
	-- (user 2026-10-28: "with biomass the bar blinks blue - the blink above the other gradients") with any critical mass
	-- the health part pulses cyan over everything (drawn last), BLINK_T s a pulse, fading to nothing between
	if critDraw > 0.001 and hpEnd > X0 + 1 then
		-- (user 2026-10-28: too fast - a longer pause between the blinks) a BLINK_ON s flash every BLINK_T s
		local ph = RealTime() % BLINK_T
		local a = ph < BLINK_ON and BLINK_A * math.sin(ph / BLINK_ON * math.pi) or 0
		-- (user: a thin red line stayed between the health and the biomass) the flash runs on into the critical mass
		hpEnd = hpEnd + BLINK_OVER
		surface.SetDrawColor(BLINK_COL.r, BLINK_COL.g, BLINK_COL.b, a)
		-- (user: "a bit higher and to the left") DrawRect truncates: each edge rounded to its own nearest pixel - the
		-- bar's 600 x 10 fill at normHealth (305, -10)
		local bx0, bx1 = math.Round((ox + X0) * s), math.Round((ox + hpEnd) * s)
		local by0, by1 = math.Round((oy - 10) * s), math.Round(oy * s)
		surface.DrawRect(bx0 + BLINK_DX, by0 + BLINK_DY, bx1 - bx0, by1 - by0)
		-- (user 2026-10-28: "when the health blinks blue, the biomass itself blinks white at that moment") the critical
		-- mass part flashes white on the same pulse
		local cx0, cx1 = math.Round((ox + XC) * s), math.Round((ox + XC + (X1 - XC) * critDraw) * s)
		if cx1 > cx0 then
			surface.SetDrawColor(BLINK_WHITE.r, BLINK_WHITE.g, BLINK_WHITE.b, a * BLINK_WHITE.a / 255)
			surface.DrawRect(cx0 + BLINK_DX, by0 + BLINK_DY, cx1 - cx0, by1 - by0)
		end
	end
end
-