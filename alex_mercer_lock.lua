- Target lock for a possessed Alex Mercer, the client half (the server: drg_alex_mercer.lua MercerLockThink, NW2
-- MercerLock). Tab locks instead of opening the scoreboard; the camera turns onto the target (the game's {AutoTarget}
-- camera); a mouse flick switches to the next target left / right; a reticle on it; his head follows it
-- (prototype head_tracking/targeting: jointLookAt {Head}, yaw within 60°, pitch -45..45°, blend 0.1 s).
-- (user 2026-11-04: "таргет лок как в игре сделать", alex_mercer_lock_game) with the game's keyboard rules: "HOLD [key] and MOVE the [mouse] to SWITCH TARGETS": only with Tab held, and then the mouse doesn't turn the
-- view; the view turns to the target only in the game camera's target mode, 1.5 s from a new target, 0.9 s over 11 m/s, then the mouse is free again and the lock stays (the DLL 0x10343590: for a mouse, input type 3)

local function possessedMercer()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply.DrG_GetPossessing then return end
	local ent = ply:DrG_GetPossessing()
	if IsValid(ent) and ent:GetClass() == "drg_alex_mercer" then return ent end
end

-- no scoreboard while possessing him: Tab is the lock (on / off)
local tabHeld = false
hook.Add("ScoreboardShow", "alex_mercer_lock", function()
	if possessedMercer() then
		tabHeld = true
		net.Start("alex_mercer_lock")
		net.WriteUInt(0, 2)
		net.SendToServer()
		return true
	end
end)
hook.Add("ScoreboardHide", "alex_mercer_lock", function()
	tabHeld = false
	if possessedMercer() then
		-- (Tab let go: the game's Target released - the climb's relax pose ends)
		net.Start("alex_mercer_lock")
		net.WriteUInt(3, 2)
		net.SendToServer()
		return true
	end
end)

-- the camera: the view turns onto the target (a little above Mercer's eyes, looking slightly down so both stay in
-- frame); the mouse's own turn adds up, a flick of 15° within ~0.15 s asks for the next target that way
-- (user: the camera shook while fighting close to the target) aimed from a steady point over his feet, not the
-- animated head, at a smoothed target point; within ~4 m the turn eases off and the pitch stops chasing it
-- (user 2026-11-06: "лок на щупальца не сделан" - the reticle stood on her whole body's box, the view on her middle) a part locked (his NW2 MercerLockPart: Greene's segment N): its joint
local function partPos(ent, tgt)
	local part = IsValid(ent) and ent:GetNW2Int("MercerLockPart", 0) or 0
	local b = part > 0 and IsValid(tgt) and tgt:LookupBone(string.format("Slug_%02d_Spine_5", part))
	return b and tgt:GetBonePosition(b) or nil
end
local lastT, lastYaw, lastPitch, flick, nextSwitch = 0, nil, nil, 0, 0
local aimPt, aimTgt
hook.Add("CreateMove", "alex_mercer_lock", function(cmd)
	local ent = possessedMercer()
	local tgt = ent and ent:GetNW2Entity("MercerLock")
	if not IsValid(tgt) then lastYaw = nil return end
	local now = SysTime()
	local dt = math.Clamp(now - lastT, 0, 0.1)
	lastT = now
	local ang = cmd:GetViewAngles()
	local lg = GetConVar("alex_mercer_lock_game")
	local gameRules = lg and lg:GetBool()
	if lastYaw and (tabHeld or not gameRules) then
		flick = flick * math.exp(-dt / 0.15) + math.AngleDifference(ang.y, lastYaw)
		if math.abs(flick) > 15 and now > nextSwitch then
			net.Start("alex_mercer_lock")
			net.WriteUInt(flick > 0 and 1 or 2, 2)
			net.SendToServer()
			flick, nextSwitch = 0, now + 0.35
		end
	else
		flick = 0
	end
	if gameRules then
		if tabHeld and lastYaw then
			ang.y, ang.p = lastYaw, lastPitch
			cmd:SetViewAngles(ang)
		end
		local gc = GetConVar("alex_mercer_camera_game")
		local st = ent.MercerChase
		-- (user 2026-11-04: "девостаторы не должны были входить в этот список") on a devastator it steers as before; MercerDevOn: alex_mercer_chasecam.lua
		if gc and gc:GetBool() and st and st.mode ~= 6 and not ent:GetNW2Bool("MercerDevOn") then
			lastYaw, lastPitch = ang.y, ang.p
			return
		end
	end
	local tp = partPos(ent, tgt) or tgt:WorldSpaceCenter()
	if aimTgt ~= tgt or not aimPt then aimPt, aimTgt = tp, tgt end
	aimPt = LerpVector(1 - math.exp(-8 * dt), aimPt, tp)
	local pivot = ent:GetPos() + Vector(0, 0, 64)
	local to = aimPt - pivot
	local flat = Vector(to.x, to.y, 0):Length()
	local near = math.Clamp((flat - 60) / 160, 0, 1) -- 0 within 1.5 m .. 1 from 5.6 m
	if flat < 160 then to.z = to.z * flat / 160 end -- close in: no steep pitch from his own bobbing
	local want = to:Angle()
	local k = 1 - math.exp(-Lerp(near, 3, 10) * dt)
	local dy = math.AngleDifference(want.y, ang.y)
	if math.abs(dy) < Lerp(near, 6, 0.5) then dy = 0 end -- a dead zone: no twitching while trading blows
	ang.y = ang.y + dy * k
	ang.p = ang.p + (math.Clamp(math.NormalizeAngle(want.p) + 8, -60, 70) - ang.p) * k
	ang.r = 0
	cmd:SetViewAngles(ang)
	lastYaw, lastPitch = ang.y, ang.p
end)

-- the reticle = the game's lockTargetHUD (protohud.gfx, tools/hudexport.py -> lua/alex_mercer/hud_locktargethud.lua), driven as the engine drives it: prototypeenginef.dll 0x104c81d0 StartLock, 0x104c82d0 EndLock, 0x104c8510 its clock, 0x104c8eb0 its frame, 0x104c7c50 its health bar, with the movie's scripts (build/as2_171.txt).
-- (user 2026-11-04: "hud таргетлока у нас старый остался, тоесть у нас он без анимаций, и нужно как в игре сделать"; since 2026-10-06 it stood still and tinted red, the pulse and the white fill taken for faults)
-- A new lock, state 1, 0.2 s: its sound, mcLargeBracket's INTRO at the middle of the screen, the corners in a small square (+-18) on the target. State 0: until the target is on the screen, 1 s at most. State 2, 0.2 s: the big bracket's OUTRO; the shadow's corners fly from a
-- rectangle of +-250, +-275 at the screen's middle to that square. State 3, 0.2 s: the corners open out to the target's box. State 5: they stay on it, the health bar over it. The next target, state 4, 0.2 s (READ: the message's +0x75 taken for "the next target": the big bracket is left out and the shadow starts from the last target): the shadow's small square goes from the last target to this one, then state 3.
-- Let go: all gone at once, as the engine throws the corners off the stage; its sound. Off the screen (the middle outside 10-90 % across, 12-92 % down, or behind the camera): the arrow at 0.425, 0.41 of the screen from its middle instead of the corners.
-- Each corner's own loop is THREAT or NONTHREAT, its pulse running inward; its white fill shows unless the screen's limit has pushed that corner in (mcSolidFillBracket._visible). The health bar, a threat's: mcHealth 35 over the box, from state 3 on, healthMask._x = (1 - hp) * -120.
-- The box stays this file's: the target's collision box projected, x0.8, x0.9 (the game's number comes with its message, not read). mcSwitchReticule isn't here: nothing found that shows it in a lock. Stage 1280 x 720, scaled to the screen height.
include("alex_mercer/swfplayer.lua")
include("alex_mercer/hud_locktargethud.lua")
include("alex_mercer/hud_mclargebracket.lua")
local SWF = ALEX_MERCER_SWF
local HOME, FAR_X, FAR_Y, OVER, MASK = 18, 250, 275, 35, -120
-- each state's time and the next one: 0x104c8cb4, 0x104c8590
local DUR = {[0] = 1, 0.2, 0.2, 0.2, 0.2, 20}
local NEXT = {[0] = 2, 0, 3, 5, 3}
local clip, big, clipTgt, isThreat, lastX, lastY, fromX, fromY
local state, clock, ended = 5, 0, false
local CORNERS = {"reticule.corner_TL", "reticule.corner_TR", "reticule.corner_BR", "reticule.corner_BL"}
local FRIENDLY = {"citizen", "alyx", "barney", "kleiner", "eli", "mossman", "monk", "vortigaunt", "dog", "breen"}
local function threat(e)
	local c = e:GetClass()
	for _, f in ipairs(FRIENDLY) do if c:find(f, 1, true) then return false end end
	return true
end
local function setState(s)
	-- (0x104c7d90: leaving 0, or 1 for anything but 0: ShowLargeBracket(false))
	if big and (state == 0 or (state == 1 and s ~= 0)) then big:GotoAndPlay("OUTRO") end
	state, clock, ended = s, 0, false
end
local function setThreat(on)
	isThreat = on
	local lab = on and "THREAT" or "NONTHREAT"
	for _, c in ipairs(CORNERS) do
		local k = clip:Child(c)
		if k then k:GotoAndPlay(lab) end
	end
end
local function startLock(tgt)
	local movie = ALEX_MERCER_HUD and ALEX_MERCER_HUD.lockTargetHUD
	if not movie then return end
	-- (the corner's frames 14 and 29: gotoAndPlay, its loops)
	local sp = movie.sprites[157]
	if sp then sp.jumps = {[14] = "THREAT", [29] = "NONTHREAT"} end
	clip = clip or SWF.New(movie)
	local nextOne = IsValid(clipTgt)
	clip:GotoAndPlay("ALEX_DEFAULT")
	local k = clip:Child("reticule")
	if k then k:GotoAndPlay("INTRO") end
	k = clip:Child("mcTargetInfo.mcHealth")
	if k then k:GotoAndPlay("INTRO") end
	k = clip:Child("mcTargetInfo.mcOffscreenArrow")
	if k then k:GotoAndStop("DEFAULT") end
	k = clip:Child("mcTargetInfo.mcAmmo")
	if k then k.hidden = true end
	setThreat(threat(tgt))
	if nextOne and lastX then
		fromX, fromY = lastX, lastY
		setState(4)
	else
		local bm = ALEX_MERCER_HUD.mcLargeBracket
		if bm then
			big = big or SWF.New(bm)
			big:GotoAndPlay("INTRO")
		end
		setState(1)
	end
	clipTgt = tgt
	surface.PlaySound("mercer/fx/ui_hud_target_lock.wav")
end
local function endLock()
	clipTgt = nil
	if not clip then return end
	clip:GotoAndStop("NOTHING")
	setState(5)
	surface.PlaySound("mercer/fx/ui_hud_target_release.wav")
end
local function put(parent, name, x, y)
	local k = parent:Child(name)
	if not k then return end
	local p = k.place
	if not p then
		p = {0, 0}
		k.place = p
	end
	p[1], p[2] = x, y
	return k
end
-- 0x104c7af0: a corner off the middle (cx) inside the limits
local function pull(v, c, lo, hi)
	if c + v > hi then v = hi - c end
	if c + v < lo then v = lo - c end
	return v
end
local function corner(name, x, y, inside)
	local k = put(clip, name, x, y)
	local f = k and k:Child("mcSolidFillBracket")
	if f then f.hidden = not inside end
end
local function healthOf(e)
	local mx = e:GetNW2Int("DrGBaseMaxHealth", e:GetMaxHealth())
	if mx <= 0 then return 0 end
	return math.Clamp(e:GetNW2Int("DrGBaseHealth", e:Health()) / mx, 0, 1)
end
-- the frame's matrices: nothing made anew a frame (swfplayer.lua's own rule)
local MC, MB = {0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 0}
local lockPartAt
local function lockFrame(tgt, dt, s)
	-- 0x104c8510
	if ended then
		ended = false
		local n = NEXT[state]
		if n then setState(n) end
	end
	clock = clock + dt
	local d = DUR[state]
	if d and clock > d then clock, ended = d, true end
	local th = threat(tgt)
	if th ~= isThreat then setThreat(th) end
	local W, H = ScrW() / s, ScrH() / s
	-- the target's box on screen (its collision bounds' 8 corners projected)
	-- (a vehicle: its box turns with it, and it is big - a corner behind the camera mustn't lose the reticle, nor the reticle fill the screen when it is close: at most this many stage pixels from its centre)
	local mn, mx, pos = tgt:OBBMins(), tgt:OBBMaxs(), tgt:GetPos()
	local prop = tgt:GetMoveType() == MOVETYPE_VPHYSICS
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	local mid = tgt:WorldSpaceCenter():ToScreen()
	-- (a segment: a box of 2 m round its joint)
	if lockPartAt then mn, mx, pos, prop, mid = Vector(-40, -40, -40), Vector(40, 40, 40), lockPartAt, false, lockPartAt:ToScreen() end
	local seen, whole = mid.visible, true
	for i = 0, 7 do
		local c = Vector(i % 2 == 0 and mn.x or mx.x, i % 4 < 2 and mn.y or mx.y, i < 4 and mn.z or mx.z)
		local sp = (prop and tgt:LocalToWorld(c) or pos + c):ToScreen()
		if sp.visible then
			x0, y0, x1, y1 = math.min(x0, sp.x), math.min(y0, sp.y), math.max(x1, sp.x), math.max(y1, sp.y)
		else
			whole = false
		end
	end
	local cx, cy, hw, hh
	if seen then
		-- (a corner behind the camera: round its middle)
		if x0 == math.huge then x0, y0, x1, y1 = mid.x, mid.y, mid.x, mid.y end
		if whole or prop then
			cx, cy = (x0 + x1) / 2 / s, (y0 + y1) / 2 / s
		else
			cx, cy = mid.x / s, mid.y / s
		end
		-- the box in stage pixels, a little inside the hull's corners (its box is wider than the body); at least the small square (0x104c9540)
		hw, hh = math.max(HOME, (x1 - x0) / 2 / s * 0.8), math.max(HOME, (y1 - y0) / 2 / s * 0.9)
		if prop then hw, hh = math.min(hw, 300), math.min(hh, 220) end
	end
	local xmin, xmax, ymin, ymax = 0.1 * W, 0.9 * W, 0.12 * H, 0.92 * H
	local off = not seen or cx < xmin or cx > xmax or cy < ymin or cy > ymax
	local ret, shad, info, arrow = clip:Child("reticule"), clip:Child("shadowReticule"), clip:Child("mcTargetInfo"), clip:Child("mcTargetInfo.mcOffscreenArrow")
	if not ret or not shad or not info or not arrow then return end
	ret.hidden, arrow.hidden = off, not off
	local lx, ly
	if off then
		shad.hidden = true
		put(clip, "mcTargetInfo", 0, 0)
		local nx, ny
		if seen then
			nx, ny = cx / W - 0.5, cy / H - 0.5
		else
			local to, a = (lockPartAt or tgt:WorldSpaceCenter()) - EyePos(), EyeAngles()
			nx, ny = to:Dot(a:Right()), -to:Dot(a:Up())
		end
		local ax, ay = math.abs(nx), math.abs(ny)
		if ax < 1e-5 and ay < 1e-5 then return end
		local k = math.min(ax >= 1e-5 and 0.425 / ax or 100000, ay >= 1e-5 and 0.41 / ay or 100000)
		nx, ny = nx * k, ny * k
		arrow.rotation = 90 - math.deg(math.atan2(-ny, nx)) - 90
		lx, ly = (0.5 + nx) * W, (0.5 + ny) * H
	else
		lx, ly = cx, cy
		-- the corners by the screen's limits, each one's fill by whether it was pushed
		local ax0, ay0, ax1, ay1 = pull(-hw, cx, xmin, xmax), pull(-hh, cy, ymin, ymax), pull(hw, cx, xmin, xmax), pull(hh, cy, ymin, ymax)
		local rx0, ry0, rx1, ry1 = ax0, ay0, ax1, ay1
		local k = math.min(clock / DUR[state], 1)
		local i = 1 - k
		if state == 0 or state == 1 or state == 2 or state == 4 then
			rx0, ry0, rx1, ry1 = -HOME, -HOME, HOME, HOME
		elseif state == 3 then
			rx0, ry0, rx1, ry1 = -HOME * i + ax0 * k, -HOME * i + ay0 * k, HOME * i + ax1 * k, HOME * i + ay1 * k
		end
		corner("reticule.corner_TL", rx0, ry0, ax0 == -hw and ay0 == -hh)
		corner("reticule.corner_TR", rx1, ry0, ax1 == hw and ay0 == -hh)
		corner("reticule.corner_BR", rx1, ry1, ax1 == hw and ay1 == hh)
		corner("reticule.corner_BL", rx0, ry1, ax0 == -hw and ay1 == hh)
		shad.hidden = state ~= 2 and state ~= 4
		if not shad.hidden then
			local sx, sy, ox, oy
			if state == 2 then
				sx, sy = FAR_X * i + HOME * k, FAR_Y * i + HOME * k
				ox, oy = (W / 2 - cx) * i, (H / 2 - cy) * i
			else
				sx, sy = HOME, HOME
				ox, oy = (fromX - cx) * i, (fromY - cy) * i
			end
			put(clip, "shadowReticule.corner_TL", ox - sx, oy - sy)
			put(clip, "shadowReticule.corner_TR", ox + sx, oy - sy)
			put(clip, "shadowReticule.corner_BR", ox + sx, oy + sy)
			put(clip, "shadowReticule.corner_BL", ox - sx, oy + sy)
		end
		put(clip, "mcTargetInfo", (rx0 + rx1) * 0.5, ry0 - OVER)
	end
	-- 0x104c7c50
	local bar = clip:Child("mcTargetInfo.mcHealth")
	if bar then
		local hp = healthOf(tgt)
		bar.hidden = not (state ~= 0 and state ~= 1 and state ~= 2 and hp > 0 and isThreat)
		local m = not bar.hidden and bar:Child("healthMask")
		if m then
			local c = m.clipX
			if not c then
				c = {0, 0}
				m.clipX = c
			end
			c[1], c[2] = -59 + (1 - hp) * MASK, 61 + (1 - hp) * MASK
		end
	end
	if not off then lastX, lastY = lx, ly end
	-- (0x104c9744: state 0 waits for the screen)
	if state == 0 and not off then setState(2) end
	clip:Advance(dt)
	MC[1], MC[4], MC[5], MC[6] = s, s, lx * s, ly * s
	clip:Draw(MC)
end
hook.Add("HUDPaint", "alex_mercer_lock", function()
	local ent = possessedMercer()
	local tgt = ent and ent:GetNW2Entity("MercerLock")
	local dt = RealFrameTime()
	local s = ScrH() / 720
	if IsValid(tgt) then
		if tgt ~= clipTgt then startLock(tgt) end
		lockPartAt = partPos(ent, tgt)
		if clip and clipTgt == tgt then lockFrame(tgt, dt, s) end
	elseif clipTgt ~= nil then
		endLock()
	end
	-- the big bracket plays on by itself, over the lock's depth; anchored to the screen's middle where the stage has it (653, 352)
	if big and big.frame ~= 0 and big.frame < 33 then
		big:Advance(dt)
		MB[1], MB[4], MB[5], MB[6] = s, s, ScrW() / 2 + 13 * s, ScrH() / 2 - 8 * s
		big:Draw(MB)
	end
end)

-- the head on the target: a world rotation of the Head bone and all under it, about the head, blended 0.1 s
local function headChain(ent)
	local mdl = ent:GetModel()
	if ent.MercerLookMdl == mdl then return ent.MercerLookChain end
	local head = ent:LookupBone("Head")
	local chain = {}
	if head then
		for b = 0, ent:GetBoneCount() - 1 do
			local q = b
			while q and q >= 0 do
				if q == head then chain[#chain + 1] = b break end
				q = ent:GetBoneParent(q)
			end
		end
	end
	ent.MercerLookMdl, ent.MercerLookChain = mdl, chain
	return chain
end
local function headLook(ent)
	local tgt = ent:GetNW2Entity("MercerLock")
	local now = CurTime()
	-- (2026-11-04: in the Super Soldier's hands the anim has his head: this turned it about the world's up on a body thrown about)
	local on = IsValid(tgt) and not ent:GetNW2Bool("MercerWall") and not ent:GetNW2Bool("MercerSeized")
	ent.MercerLookW = math.Approach(ent.MercerLookW or 0, on and 1 or 0, math.max(0, now - (ent.MercerLookLast or now)) / 0.1)
	ent.MercerLookLast = now
	-- (user 2026-11-06: a segment of Greene's locked, MercerLockPart: the view on it)
	if on then
		local part = ent:GetNW2Int("MercerLockPart", 0)
		local b = part > 0 and tgt:LookupBone(string.format("Slug_%02d_Spine_5", part))
		ent.MercerLookPos = b and tgt:GetBonePosition(b) or tgt:WorldSpaceCenter() + Vector(0, 0, tgt:OBBMaxs().z * 0.3)
	end
	local w, look = ent.MercerLookW, ent.MercerLookPos
	if w <= 0 or not look then return end
	local chain = headChain(ent)
	local hm = chain[1] and ent:GetBoneMatrix(chain[1])
	if not hm then return end
	local pivot = hm:GetTranslation()
	local to = (look - pivot):Angle()
	local yaw = ent:GetAngles().y
	local dy = math.Clamp(math.AngleDifference(to.y, yaw), -60, 60) * w
	local dp = math.Clamp(math.NormalizeAngle(to.p), -45, 45) * w
	local A, B = Matrix(), Matrix()
	A:SetAngles(Angle(dp, yaw + dy, 0))
	B:SetAngles(Angle(0, yaw, 0))
	local R = A * B:GetInverseTR()
	for _, b in ipairs(chain) do
		local m = ent:GetBoneMatrix(b)
		if m then
			local nm = R * m
			nm:SetTranslation(pivot + R * (m:GetTranslation() - pivot))
			ent:SetBoneMatrix(b, nm)
		end
	end
end
timer.Create("alex_mercer_lock_head", 1, 0, function()
	for _, e in ipairs(ents.FindByClass("drg_alex_mercer")) do
		if not e.MercerLookCb then e.MercerLookCb = e:AddCallback("BuildBonePositions", headLook) end
	end
end)
-