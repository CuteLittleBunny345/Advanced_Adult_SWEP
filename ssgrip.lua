- The NPC pack's Super Soldier seizes him (2026-11-03). Only drg_proto_supersoldier.lua calls these: nothing without the
-- pack; alex_mercer_hunter_grab off: he can't be seized. His half of //supersoldier's grapple S33-S60, its counters S1556 /
-- S1664 and his reversal S1670-S1672 (build/graph_supersoldier.txt, graph_hitreaction_n.txt): the pack's side owns the scene,
-- each tick it puts his Motion_Root on its R_Wrist_Grapple (grabSlotUpdateAttachment, no offsets) until it lets go; his
-- _rcv / _gv plays on his own clock, started with its half. After the slot is let go his node runs out, then the ones
-- queued (the receiver's sequence items), his root moved by their move items; then he is his own again.
if not ALEX_MERCER_FRAMES or not ALEX_MERCER_GRAPH then return end
local M2U = 39.37
local GP = ALEX_MERCER_PLAYER
local G = ALEX_MERCER_GRAPH
for name, n in pairs({supersol_grap_stomp_rcv = 178, supersol_grap_aroundtheworld_001_rcv = 71,
	supersol_grap_backbreaker_002_rcv = 114, alex_grap_air_slam_rcv = 49, alex_grap_air_float_rcv = 55}) do
	ALEX_MERCER_FRAMES[name] = ALEX_MERCER_FRAMES[name] or n
end
local function tr(t0, t1, anim, rate, f0, f1)
	return {start = t0, stop = t1, anim = anim, rate = rate, f0 = f0, f1 = f1, cyclic = false, part = "", blendin = 0, blendout = 0}
end
-- S36, S44, S47, S50
G["mercer/ss/start"] = {tr(0, -1, "supersol_grap_start_rcv", 1, 0, -1)}
G["mercer/ss/stomp"] = {tr(0, -1, "supersol_grap_stomp_rcv", 1, 28, 71)}
G["mercer/ss/atw"] = {tr(0, -1, "supersol_grap_aroundtheworld_001_rcv", 1, 20, 55)}
G["mercer/ss/backbreaker"] = {tr(0, 2.2667, "supersol_grap_backbreaker_002_rcv", 1, 14, 83)}
-- S59 (gethit_kd_1 x1.2 6-17, its move 7 m in 0.2667 s), S60 (alex_breakfall_flip, 3 m in 0.5 s)
G["mercer/ss/kd"] = {tr(0, -1, "gethit_kd_1", 1.2, 6, 17)}
G["mercer/ss/recover"] = {tr(0, 0.4333, "alex_breakfall_flip", 1, 0, 11), tr(0.4333, 0.8, "alex_breakfall_flip", 1, 11, 23),
	tr(0.8, 1.067, "alex_breakfall_flip", 1, 23, 26), tr(1.067, 1.2, "alex_breakfall_flip", 1, 26, 31)}
-- S1664: the block's grab counter; S1556, S1557: the counter of his air blow
G["mercer/ss/counter"] = {tr(0, 0.4, "supersol_combat_counter_attack_rcv", 1, 2, 15), tr(0.4, 0.9, "supersol_combat_counter_attack_rcv", 1, 15, 26),
	tr(0.9, -1, "gethit_kd_4", 1, 0, 17)}
G["mercer/ss/air_counter"] = {tr(0, -1, "supersol_grap_air_counter_rcv", 1, 0, 41)}
G["mercer/ss/air_counter_kd"] = {tr(0, 1, "gethit_kd_5", 1, 0, 21)}
-- S1670-S1672: his reversal
G["mercer/ss/rev1"] = {tr(0, -1, "supersol_grap_reversal_gv", 1, 6, -1)}
G["mercer/ss/rev2"] = {tr(0, 0.5667, "supersol_grap_reversal_gv", 1, 6, 25), tr(0.5667, 1.833, "alex_grap_knee_head_gv", 1, 3, -1)}
G["mercer/ss/rev3"] = {tr(0, 0.5667, "supersol_grap_reversal_gv", 1, 6, 25), tr(0.5667, 1.333, "alex_special_spin_kick_right", 1, 3, 30)}
-- S109, S113, S117, S121: the jump attack's air slam
G["mercer/ss/air_slam"] = {tr(0, 0.3333, "alex_grap_air_slam_rcv", 1, 0, 20)}
G["mercer/ss/air_slam_fall"] = {tr(0, 0.4333, "alex_grap_air_slam_rcv", 1, 21, 39), tr(0.4333, 30, "alex_grap_air_slam_rcv", 1, 39, 40)}
G["mercer/ss/air_slam_down"] = {tr(0, 0.1, "alex_grap_air_slam_rcv", 1, 41, 46), tr(0.1, 0.2, "alex_grap_air_slam_rcv", 1, 46, 49)}
G["mercer/ss/air_float"] = {tr(0, 2.667, "alex_grap_air_float_rcv", 1, 0, 54)}
-- the move items of the queued nodes: {until, metres back}
local MOVES = {["mercer/ss/kd"] = {0.2667, 7}, ["mercer/ss/recover"] = {0.5, 3}}
-- what his knockback doesn't break either (the pack's Hunters' list of his own fields)
local BUSY = {"MercerGrab", "MercerGrind", "MercerHToss", "MercerClawSpike", "MercerSkid", "MercerAirSlam", "MercerAirThrow",
	"MercerDevPunchSt", "MercerDive", "MercerBullet"}
local BUSY_NW = {"MercerHolding", "MercerCharging"}
-- (2026-11-04, user: "мерсер все таки бывает кривой в руках у суперсолдата в захвата и т.д.") Source's client fades a change of sequence over 0.2 s (these anims have the QC's default; CSequenceTransitioner, as remembered from the SDK:
-- the old sequence's weight 3 x^2 - 2 x^3, x = 1 - dt / 0.2, bones blended in their parents' space), the entity goes at once. So what's drawn over the fade is the new place under the old pose: tools/sspair_client.py has his root
-- up to 68 u off its hand and its body up to 103 u off, 0.15-0.3 s at each change of step, on tables that read 0.00 u; and at the end of his nodes his body thrown 136 u past where he is (gethit_kd_1) or turned 90 deg too far (the backbreaker's
-- and around the world's root turns) and sliding back. Now the places follow the fade: his root over the two poses' roots, by the same weight. Not seen in game; the 0.2 s and the curve are from memory of the SDK.
local FADE = 0.2
local function fadeOld(dt)
	local x = 1 - dt / FADE
	if x <= 0 then return 0 end
	return x * x * (3 - 2 * x)
end

-- taken, or refused (he is in something that owns his body); up = it may carry him off the ground
function ENT:MercerSeize(ss, node, up)
	local cv = GetConVar("alex_mercer_hunter_grab")
	if not (cv and cv:GetBool()) or self:Health() <= 0 or (self.IsPlayingAnimation and self:IsPlayingAnimation()) then return false end
	for _, k in ipairs(BUSY) do
		if self[k] then return false end
	end
	for _, k in ipairs(BUSY_NW) do
		if self:GetNW2Bool(k) then return false end
	end
	if self.MercerFight then self:MercerFightEnd() end
	if self.MercerFKick then self:MercerFKickEnd() end
	self.MercerStomp, self.MercerElbow, self.MercerAirDash = nil, nil, nil
	if self.MercerSprintOn then self:MercerSprintEnd() end
	if self.MercerHitCancel then self:MercerHitCancel() end
	if self:GetNW2Bool("MercerWall") and self.MercerStopWall then self:MercerStopWall() end
	if self.MercerObj and self.MercerObjDrop then self:MercerObjDrop() end
	if self.MercerGun and self.MercerGunDrop then self:MercerGunDrop() end
	self.MercerGrab = {hunter = ss, phase = "sseized", t0 = CurTime(), placeT = CurTime(), from = self:GetPos(), fromA = self:GetAngles(),
		grav = self.loco:GetGravity(), stepH = self.loco.GetStepHeight and self.loco:GetStepHeight()}
	self:MercerCombatEvent()
	self.loco:SetGravity(0)
	self.loco:SetVelocity(Vector(0, 0, 0))
	self:SetNotSolid(true)
	-- (the engine's ground constraint, as remembered from the SDK: within the step height of the floor it snaps the feet down, and if his update comes after its think in the tick that beats the place it gives him: his
	-- entity runs up to 10 u over the floor in the reversals, 45 in the air counter. Whether it does depends on who spawned first. As his vault's flight does)
	if self.MercerGrab.stepH then self.loco:SetStepHeight(1) end
	-- (for the client: alex_mercer_lock.lua's head on the target stays off)
	self:SetNW2Bool("MercerSeized", true)
	if up then self:LeaveGround() end
	self:MercerSeizedNode(node)
	return true
end
-- the next of his half, with its next one
function ENT:MercerSeizedNode(node)
	local g = self.MercerGrab
	if not g or g.phase ~= "sseized" then return end
	g.node, g.nodeT, g.nodeD, g.nodeFrom = node, CurTime(), GP.Duration(node), self:GetPos()
	GP.Start(self, node, {block = true, hold = true})
end
-- his root now, in the world: off his anim's table (alex_mercer/grabpair.lua), never his bones - on the server they are a cache up to 0.1 s old, from
-- where he stood then, and posing him from them runs him off (he is what moves them)
local function rootNow(self)
	local anim, cycle = GP.Sample(self)
	anim = anim and string.lower(anim)
	if not anim then return end
	local f = cycle * ((ALEX_MERCER_FRAMES[anim] or 2) - 1)
	local bp, ba = ALEX_MERCER_GRABROOT(self, anim, f)
	return bp, ba, anim, f
end
-- his Motion_Root on (pos, ang), from where he stood over 0.1 s (BY EYE: the game's attachment snaps within its grab's reach). He stays upright: its hand's
-- yaw alone, the root's place exact (its hand tilts up to 32 deg in the air float, 16 in the air counter, near none in the rest). fade: his next anim's root stands elsewhere (the Supreme's ride):
-- the entity gets there over the client's 0.2 s fade from the last pose, the body stays put
function ENT:MercerSeizedPlace(pos, ang, fade)
	local g = self.MercerGrab
	if not g or g.phase ~= "sseized" or g.let then return end
	g.placeT = CurTime()
	-- (his half taken off him by anything of his own that stops or starts a node: back, on its clock - without it nothing here knows where his root is)
	local st = self.MercerNode
	if (not st or st.path ~= g.node) and GP.Start(self, g.node, {block = true, hold = true}) then self.MercerNode.t0 = g.nodeT end
	local bp, ba, anim, f = rootNow(self)
	if not bp then return end
	local lp, la = WorldToLocal(bp, ba, self:GetPos(), self:GetAngles())
	-- (the root the client shows over its fade from his last anim)
	if anim ~= g.fadeAnim then
		if g.fadeAnim then g.oldAnim, g.oldF, g.oldT = g.fadeAnim, g.fadeF, CurTime() end
		g.fadeAnim = anim
	end
	g.fadeF = f
	local w = g.oldT and not fade and fadeOld(CurTime() - g.oldT) or 0
	local op, oa
	if w > 0 then op, oa = ALEX_MERCER_GRABROOT(self, g.oldAnim, g.oldF) end
	if op then
		local olp, ola = WorldToLocal(op, oa, self:GetPos(), self:GetAngles())
		lp = LerpVector(w, lp, olp)
		la = LerpAngle(w, la, ola)
	end
	local _, ia = WorldToLocal(vector_origin, angle_zero, lp, la)
	local _, ea = LocalToWorld(vector_origin, ia, pos, ang)
	lp:Rotate(Angle(0, ea.y, 0))
	local k = math.Clamp((CurTime() - g.t0) / 0.1, 0, 1)
	local at = LerpVector(k, g.from, pos - lp)
	if fade and g.nodeFrom then at = LerpVector(math.Clamp((CurTime() - g.nodeT) / 0.2, 0, 1), g.nodeFrom, at) end
	self:SetPos(at)
	self:SetAngles(Angle(0, LerpAngle(k, g.fromA, ea).y, 0))
end
-- the root's place given to the entity: the next anim stands on its own root, at its first frame (its own start there is no move in the game: gethit_kd_1 from frame 6 stands 81 u back). nx: that node, the entity going over with the client's
-- fade to it: FADE; no next: at once (his root at the end of those stands at 0: nothing to see)
function ENT:MercerSeizedSettle(nx, over)
	local g = self.MercerGrab
	local bp, ba = rootNow(self)
	if not bp then return end
	local tr = nx and G[nx] and G[nx][1]
	local np, na
	if tr then np, na = ALEX_MERCER_GRABROOT(self, string.lower(tr.anim), tr.f0) end
	local ep, ea = self:GetPos(), self:GetAngles()
	local lo, ao = WorldToLocal(bp, ba, ep, ea)
	local ln, an = Vector(0, 0, lo.z), Angle(0, 0, 0)
	if np then ln, an = WorldToLocal(np, na, ep, ea) end
	g.glide = {t0 = CurTime(), x = bp.x, y = bp.y, yaw = ba.y, lo = lo, ln = ln, yo = ao.y, yn = an.y}
	g.glide.p, g.glide.a = self:MercerSeizedGlideAt(g.glide, 1)
	if not nx and not over then self:MercerSeizedGlideStep(g, 0) end
end
-- where the entity stands with the old pose's weight w, its root where it was
function ENT:MercerSeizedGlideAt(d, w)
	local a = d.yaw - (d.yn + math.AngleDifference(d.yo, d.yn) * w)
	local off = LerpVector(w, d.ln, d.lo)
	off.z = 0
	off:Rotate(Angle(0, a, 0))
	return Vector(d.x - off.x, d.y - off.y, 0), a
end
-- what else moves him meanwhile (his move items, a fall) stays his
function ENT:MercerSeizedGlideStep(g, w)
	local d = g.glide
	w = w or fadeOld(CurTime() - d.t0)
	local p, a = self:MercerSeizedGlideAt(d, w)
	self:SetPos(self:GetPos() + (p - d.p))
	self:SetAngles(Angle(0, self:GetAngles().y + math.AngleDifference(a, d.a), 0))
	d.p, d.a = p, a
	if w <= 0 then g.glide = nil end
end
-- the scene's clock held back by this much (the pack's side, its counter's window): his half stays with its; rate: what a multiplayer client plays on at between updates
function ENT:MercerSeizedClock(shift, rate)
	local g = self.MercerGrab
	if not g or g.phase ~= "sseized" or g.let then return end
	g.nodeT = g.nodeT + shift
	local st = self.MercerNode
	if st and st.path == g.node then
		st.t0 = st.t0 + shift
		st.opts.speed = rate
	end
end
function ENT:MercerSeizedRestore(g)
	self:SetNotSolid(false)
	if g.grav or g.grav2 then self.loco:SetGravity(g.grav or g.grav2) end
	g.grav, g.grav2 = nil, nil
	if g.stepH then self.loco:SetStepHeight(g.stepH) end
	g.stepH = nil
	-- (his grab over: called from MercerHunterGrabEnd)
	if self.MercerGrab ~= g then self:SetNW2Bool("MercerSeized", false) end
end
-- the slot let go: on his own, what is queued after his node; vel, grav: flung off (a jump item's flight)
function ENT:MercerSeizedLet(queue, vel, grav)
	local g = self.MercerGrab
	if not g or g.phase ~= "sseized" or g.let then return end
	g.let, g.queue = true, queue or {}
	if vel then
		g.grav2 = g.grav
		self:SetNotSolid(false)
		g.grav = nil
		if g.stepH then self.loco:SetStepHeight(g.stepH) end
		g.stepH = nil
		self.loco:SetGravity(grav)
		self:LeaveGround()
		self.loco:SetVelocity(vel)
		return
	end
	self:MercerSeizedRestore(g)
end
function ENT:MercerSeizedThink(g, e, t)
	if self:Health() <= 0 then return self:MercerHunterGrabEnd() end
	if not g.let then
		-- (its side gone quiet: free)
		if CurTime() - g.placeT > 0.35 then return self:MercerHunterGrabEnd() end
		return true
	end
	if g.grav2 and self:IsOnGround() and CurTime() - g.nodeT > 0.2 then
		self.loco:SetGravity(g.grav2)
		g.grav2 = nil
	end
	if g.glide then self:MercerSeizedGlideStep(g) end
	local dt = CurTime() - g.nodeT
	local mv = MOVES[g.node]
	if mv and dt < mv[1] then self:MercerShove(self:GetForward() * (-mv[2] / mv[1] * M2U * FrameTime())) end
	if dt < g.nodeD then return true end
	local nx = table.remove(g.queue, 1)
	self:MercerSeizedSettle(nx)
	if not nx then return self:MercerHunterGrabEnd() end
	self:MercerSeizedNode(nx)
	return true
end
-- (2026-11-04, the user: "сделает так чтоб суперсолдата тоже можно было кидать как хантера на прогиб на лкм") His throw on its back. NOT the game's on this body: holding/grabbing/supersoldiers S64-S67 have no such throw, the anim and its items are the Hunter's S21 (alex_grap_brawl_directional_throw_gv 0-40 x1.1, let go at 0.7667 s; its half tools/ss_suplex.py, BY EYE to its size). Attack alone: Action stays S287's. The window as the Hunter's hold's and S287's: 0.1667-0.6667 s, a press before it held for it. The anim itself has it down behind him, with no flight. The turn to where he aims is S67's. Its items as his other throw has them; the punch-in left out as there
local SUPLEX_RCV = "supersol_grap_suplex_rcv"
function ENT:MercerSSSuplexInput(g, kind)
	local e, t = g.hunter, CurTime() - g.t0
	if kind ~= "a" or g.phase ~= "ssgrab" or g.let or t > 0.6667 or not isfunction(e.HunterLetGo) or e:LookupSequence(SUPLEX_RCV) < 0 then return end
	if t < 0.1667 then
		if not g.pend then
			g.pend = true
			self:Timer(0.1667 - t, function(ent)
				if ent.MercerGrab == g then ent:MercerSSSuplexInput(g, kind) end
			end)
		end
		return
	end
	self:MercerCombatEvent()
	self:SetNW2String("ProtoCounterKey", "")
	self:MercerHunterStep("mercer/hunter_throw")
	g.phase, g.t0, g.d, g.node = "sssuplex", CurTime(), GP.Duration("mercer/hunter_throw"), "mercer/hunter_throw"
	self:MercerVO("alex_jump_sml_start", 1, 0.1)
	GP.Start(self, "mercer/hunter_throw", {block = true, hold = true})
	self:Timer(0.3333, function(ent) ent:MercerCue("whoosh_small") end)
	self:Timer(0.5, function(ent) ent:MercerCue("power_whoosh") end)
end
-- his end of a throw of it, this one or S67's. The anim's over with him turned (158 deg here, 41 there): the entity under his root over the client's fade, the body stays. (The Hunter's at once with EF_NOINTERP stops the fade, but that flag lasts the one server frame: with two ticks to a client frame it isn't seen, and his old pose stands turned as much again on the new angles for 0.2 s. S67's had no flag: 41 deg in a tick, every time)
function ENT:MercerSSOut(g)
	if not g.outT then
		g.outT = CurTime()
		self:MercerSeizedSettle(nil, true)
		GP.Stop(self)
		self:UpdateAnimation()
	end
	if g.glide then self:MercerSeizedGlideStep(g) end
	if g.glide then return true end
	return self:MercerHunterGrabEnd()
end
function ENT:MercerSSSuplexThink(g, e, t)
	local p = self:GetPossessor()
	if t < 0.4 and IsValid(p) then
		self:SetAngles(Angle(0, math.ApproachAngle(self:GetAngles().y, self:MercerAimVector(p):Angle().y, 1200 * FrameTime()), 0))
	end
	if not g.let then
		-- (its entity on his by the line the pair's anims give, off the tables at every frame but two: R_Wrist_Grapple turns 47 deg a frame at frames 10-13 and its Motion_Root doesn't follow, a hand's place would hop it 21 u off the floor, tilted 25 deg, for 0.1 s. His visible hands have no such turn, nor the client's attachment here)
		local anim, cycle = GP.Sample(self)
		anim = anim and string.lower(anim)
		if anim then
			local own = cycle * ((ALEX_MERCER_FRAMES[anim] or 2) - 1)
			local ep = LocalToWorld(Vector(48.4 + 0.132 * own, 0.1 - 0.064 * own, 0), angle_zero, self:GetPos(), self:GetAngles())
			e:HunterHeldPose(SUPLEX_RCV, own, ep, Angle(0, self:GetAngles().y + 180, 0), true)
		end
		if t >= 0.7667 then
			g.let = true
			e:HunterLetGo()
		end
	end
	if t < g.d then
		self:MercerHunterRootMove(g)
		return true
	end
	return self:MercerSSOut(g)
end
-