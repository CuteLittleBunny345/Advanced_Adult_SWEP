- Client-side feel for a possessed Alex Mercer: speed FOV, motion blur while sprinting, dust kicked up
-- behind the feet (like the game's sprint).

local function possessedMercer()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply.DrG_GetPossessing then return end
	local ent = ply:DrG_GetPossessing()
	if IsValid(ent) and ent:GetClass() == "drg_alex_mercer" then return ent end
end

-- (user) playing as him: none of GMod's own player HUD - the health / suit bars bottom left, the crosshair; his own
-- health bar (alex_mercer_health.lua) stays
local HIDE = {CHudHealth = true, CHudBattery = true, CHudSuitPower = true, CHudCrosshair = true, CHudDamageIndicator = true,
	CHudPoisonDamageIndicator = true, CHudSquadStatus = true}
hook.Add("HUDShouldDraw", "AlexMercerHideHUD", function(name)
	if HIDE[name] and possessedMercer() then return false end
end)

-- Camera shake: the game's cameraShakeRequest {magnitude} {duration} (small / medium / large) and the hit kicks,
-- sent by ENT:MercerShake. DrGBase's possession view replaces the engine's, so util.ScreenShake / ViewPunch never
-- reach it: they are added to that view here. "fast" shakes: ~22 Hz, falling off quadratically.
local SHAKE_AMP = {0.6, 1.5, 3.0}    -- degrees (small / medium / large)
local SHAKE_POS = {0.5, 1.5, 3.5}    -- units
local SHAKE_DUR = {0.25, 0.45, 0.9}  -- seconds
local SHAKE_HZ = 22
local KICK_DUR = 0.22
-- (user 2026-11-04: "почему все тряски экрана пропали") this was a local table: a refresh of this file with the game open gave the net.Receive below a new one while the view went on reading the old one, no shake at all until the next map load
-- (the wrap further down was made once, at InitPostEntity). In his game from 17:01, when this file changed, to the map load of 18:47: sv.db's cookies of InitPostEntity weren't there until then
ALEX_MERCER_SHAKES = ALEX_MERCER_SHAKES or {}
local shakes = ALEX_MERCER_SHAKES
net.Receive("alex_mercer_shake", function()
	local m, d = net.ReadUInt(2), net.ReadUInt(2)
	local kp, ky = net.ReadFloat(), net.ReadFloat()
	local now = CurTime()
	if m > 0 then
		shakes[#shakes + 1] = {t0 = now, amp = SHAKE_AMP[m], pos = SHAKE_POS[m], dur = SHAKE_DUR[math.max(d, 1)],
			ph = math.random() * 100}
	end
	if kp ~= 0 or ky ~= 0 then shakes[#shakes + 1] = {t0 = now, kick = Angle(kp, ky, 0), dur = KICK_DUR} end
	if #shakes > 24 then table.remove(shakes, 1) end
end)

local function shakeView(view)
	local now = CurTime()
	local ang, off = Angle(), Vector()
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local k = 1 - (now - s.t0) / s.dur
		if k <= 0 then
			table.remove(shakes, i)
		elseif s.kick then
			-- the kick snaps in, then eases back
			local e = math.min(1, (now - s.t0) / 0.04) * k * k
			ang = ang + s.kick * e
		else
			local a = s.amp * k * k
			local t = (now - s.t0) * SHAKE_HZ * 2 * math.pi + s.ph
			ang.p = ang.p + a * math.sin(t)
			ang.y = ang.y + a * 0.6 * math.sin(t * 1.31 + 1.7)
			ang.r = ang.r + a * 0.5 * math.sin(t * 0.87 + 4.1)
			off.z = off.z + s.pos * k * k * math.sin(t * 1.13 + 2.3)
			off.x = off.x + s.pos * 0.5 * k * k * math.sin(t * 0.77 + 0.4)
		end
	end
	if #shakes > 0 then
		view.angles = (view.angles or Angle()) + ang
		view.origin = (view.origin or Vector()) + off
	end
end

-- punchinCamera (ENT:MercerPunchIn, the Bullet Dive): the camera in to dolly x its distance from him, the view to zoom x its
-- FOV, tIn s there, tOut s back by tEnd; a new one goes on from where the last has got to
-- (also dolly, zoom, the re-aim's blend and its aim point, his frame: the game camera, alex_mercer_chasecam.lua)
local punch
local function punchNow()
	if not punch then return 1, 1, 0 end
	local p, t = punch, CurTime() - punch.t0
	if t >= p.tEnd then
		punch = nil
		return 1, 1, 0
	end
	if t > p.tEnd - p.tOut then
		local k = (p.tEnd - t) / p.tOut
		return Lerp(k, 1, p.d), Lerp(k, 1, p.z), Lerp(k, 0, p.ra), p.ax, p.ay, p.az
	end
	local k = p.tIn > 0 and math.min(1, t / p.tIn) or 1
	return Lerp(k, p.d0, p.d), Lerp(k, p.z0, p.z), Lerp(k, p.ra0, p.ra), Lerp(k, p.ax0, p.ax), Lerp(k, p.ay0, p.ay), Lerp(k, p.az0, p.az)
end
-- 0x103416e0: from where the last one has got to; the aim point moves only while one is aimed, else it is there at once
local function punchSet(tEnd, tIn, tOut, dolly, zoom, reAim, ax, ay, az)
	local d0, z0, ra0, px, py, pz = punchNow()
	local aimed = ra0 > 0
	ax, ay, az = ax or 0, ay or 0.6, az or 0
	if aimed and not reAim then ax, ay, az = px, py, pz end
	punch = {t0 = CurTime(), tEnd = tEnd, tIn = tIn, tOut = tOut, d = dolly, z = zoom, d0 = d0, z0 = z0, ra = reAim and 1 or 0, ra0 = ra0,
		ax = ax, ay = ay, az = az, ax0 = aimed and px or ax, ay0 = aimed and py or ay, az0 = aimed and pz or az}
end
ALEX_MERCER_PUNCHNOW, ALEX_MERCER_PUNCHSET = punchNow, punchSet
net.Receive("alex_mercer_punchin", function()
	local tEnd, tIn, tOut, dolly, zoom = net.ReadFloat(), net.ReadFloat(), net.ReadFloat(), net.ReadFloat(), net.ReadFloat()
	if net.ReadBool() then
		-- (the item's reAim 1 and its aim point: the view goes up on him, a consume of a Hunter's S37)
		local ax, ay, az = net.ReadFloat(), net.ReadFloat(), net.ReadFloat()
		punchSet(tEnd, tIn, tOut, dolly, zoom, true, ax, ay, az)
	else
		punchSet(tEnd, tIn, tOut, dolly, zoom)
	end
end)
local function punchView(view, ent, fov)
	local d, z = punchNow()
	if d == 1 and z == 1 then return end
	view.fov = (view.fov or fov) * z
	local c = ent:WorldSpaceCenter()
	if view.origin then view.origin = c + (view.origin - c) * d end
end

-- Widen DrGBase's possession view with speed (wraps its CalcView hook once it exists).
local fovBoost = 0
-- (2026-11-04, a player: "some addon conflict with the fov changing") Done once at InitPostEntity, the wrap was lost for good to anything setting that hook after it, and never made if the hook came later: his camera still came from
-- ENT:PossessorView, his FOV and his shakes did not. So looked at again every second; nothing happens while the hook is this one (another addon's wrap of it: this goes round that too, the view marked so it is done once)
-- (user 2026-11-04, the shakes: a refresh of this file left the view in the old file's wrap) each wrap remembers what it wrapped, and a refreshed file goes round the old wrap to that
ALEX_MERCER_CALCVIEW_WRAPS = ALEX_MERCER_CALCVIEW_WRAPS or setmetatable({}, {__mode = "k"})
local WRAPS = ALEX_MERCER_CALCVIEW_WRAPS
local wrapped
local function wrapCalcView()
	local hooks = hook.GetTable().CalcView
	local cur = hooks and hooks["DrGBasePossessionCalcView"]
	if not cur or cur == wrapped then return end
	local orig = WRAPS[cur] or cur
	wrapped = function(ply, origin, angles, fov, znear, zfar)
		local view = orig(ply, origin, angles, fov, znear, zfar)
		local ent = possessedMercer()
		-- (a new mark: a wrap from before this one, which can't be gone round, marks AlexMercer and has its own empty table of shakes)
		if view and ent and not view.AlexMercerDone then
			view.AlexMercerDone = true
			local gc = GetConVar("alex_mercer_camera_game")
			if gc and gc:GetBool() and ALEX_MERCER_CHASECAM then
				-- (user 2026-11-04) the game's chase camera: its own FOV, the punch's zoom in it (the dolly went in its distance)
				fovBoost = 0
				local _, z = punchNow()
				view.fov = ALEX_MERCER_CHASECAM.Fov(ent, z)
			else
				local speed = ent:GetVelocity():Length()
				-- (user: the camera pulled too far out) at most +6° from ~10 m/s (was +15° from 6 m/s)
				fovBoost = Lerp(math.min(1, FrameTime() * 3), fovBoost, math.Clamp((speed - 400) / 500, 0, 1) * 6)
				view.fov = (view.fov or fov) + fovBoost
				punchView(view, ent, fov)
			end
			shakeView(view)
			-- (the NPC pack: its scenes' cameras, the Mother's body in the way: lua/autorun/client/prototype_mother_scene.lua. Nothing without the pack)
			if PROTO_SCENE_VIEW then PROTO_SCENE_VIEW(ent, view) end
		end
		return view
	end
	WRAPS[wrapped] = orig
	hook.Add("CalcView", "DrGBasePossessionCalcView", wrapped)
end
hook.Add("InitPostEntity", "AlexMercerWrapCalcView", wrapCalcView)
-- (here, not at InitPostEntity: a refresh of this file has no InitPostEntity, and the timer would go on with the old file's function)
timer.Create("AlexMercerWrapCalcView", 1, 0, wrapCalcView)
wrapCalcView()

-- (Removed: DrawMotionBlur while sprinting - the user found it hard on the eyes. To be replaced by the
-- game's own radial blur once its parameters are extracted.)
hook.Remove("RenderScreenspaceEffects", "AlexMercerSpeedBlur")

-- (user 2026-11-04, a video of the game) the light smoke behind him while sprinting, by eye since October, gone: the game's is the step's dark dust, alex_mercer_vfx.lua. Removed by name: a refresh of this file leaves an old hook on
hook.Remove("Think", "AlexMercerSprintDust")

-- Falling: the game's radialBlur item on prototype_air's fall node (fadeIn 2 s, intensity 5 -> 10, fadeOut 1 s),
-- here a zoom blur of the screen for the possessor while Mercer falls faster than 10 m/s. Off: alex_mercer_radialblur 0
local RadialBlur = CreateClientConVar("alex_mercer_radialblur", "1", true, false, "Radial blur while falling (Alex Mercer)")
local blurMat = CreateMaterial("alex_mercer_radialblur", "UnlitGeneric", {["$basetexture"] = "_rt_FullFrameFB",
	["$translucent"] = "1", ["$vertexalpha"] = "1", ["$vertexcolor"] = "1", ["$ignorez"] = "1"})
local blurK, fallTime = 0, 0
hook.Add("RenderScreenspaceEffects", "AlexMercerFallBlur", function()
	if not RadialBlur:GetBool() then return end
	local ply = LocalPlayer()
	local ent = IsValid(ply) and ply.DrG_GetPossessing and ply:DrG_GetPossessing()
	local dt = FrameTime()
	local falling = IsValid(ent) and ent:GetClass() == "drg_alex_mercer" and ent:GetVelocity().z < -10 * 39.37
		and not ent:GetNW2Bool("MercerGlide") and not ent:GetNW2Bool("MercerWall")
	fallTime = falling and fallTime + dt or 0
	-- fade in over 2 s of falling, out over 1 s
	blurK = falling and math.min(1, blurK + dt / 2) or math.max(0, blurK - dt)
	if blurK <= 0.01 then return end
	local speed = IsValid(ent) and -ent:GetVelocity().z / 39.37 or 0
	local intensity = Lerp(math.Clamp(fallTime / 5, 0, 1), 5, 10) * math.Clamp(speed / 40, 0.4, 1) * blurK
	render.UpdateScreenEffectTexture()
	blurMat:SetTexture("$basetexture", render.GetScreenEffectTexture())
	local w, h = ScrW(), ScrH()
	cam.Start2D()
	surface.SetMaterial(blurMat)
	for i = 1, 6 do
		local sc = 1 + intensity * 0.004 * i
		local dw, dh = w * sc, h * sc
		surface.SetDrawColor(255, 255, 255, 40 * blurK / (1 + i * 0.35))
		surface.DrawTexturedRect((w - dw) * 0.5, (h - dh) * 0.5, dw, dh)
	end
	cam.End2D()
end)
-