- Plays a node of Prototype's own behaviour graph (exported to ALEX_MERCER_GRAPH by tools/figexport.py):
-- every animation track has a time window and a frame range, exactly as the game stores them, and the
-- player sets sequence + cycle every tick instead of letting Source free-run the animation.
-- Directional blends (ALEX_MERCER_DIRBLEND, the game's 85860039 tracks: center + forward/right/back/left)
-- play the entry that matches the horizontal velocity relative to the facing.
ALEX_MERCER_PLAYER = ALEX_MERCER_PLAYER or {}
local P = ALEX_MERCER_PLAYER
local FPS = 30
local M2U = 39.37

local function frames(anim)
	return (ALEX_MERCER_FRAMES and ALEX_MERCER_FRAMES[string.lower(anim)]) or 2
end

-- end time of a track inside the node (seconds); math.huge for open-ended cyclic tracks
local function trackEnd(tr)
	if tr.stop >= 0 then return tr.stop end
	if tr.cyclic then return math.huge end
	local f1 = tr.f1 >= 0 and tr.f1 or frames(tr.anim) - 1
	return tr.start + math.abs(f1 - tr.f0) / (FPS * math.max(math.abs(tr.rate), 0.01))
end

local function fullBody(tracks)
	local out = {}
	for _, tr in ipairs(tracks) do
		if tr.part == "" then out[#out + 1] = tr end
	end
	return out
end

function P.Has(path) return ALEX_MERCER_GRAPH and ALEX_MERCER_GRAPH[path] ~= nil end

function P.Duration(path)
	local d = 0
	for _, tr in ipairs(fullBody(ALEX_MERCER_GRAPH[path] or {})) do d = math.max(d, trackEnd(tr)) end
	return d
end

-- opts: loop (restart when finished), block (no locomotion while playing), next (path to chain),
-- nextOpts, hold (keep the last frame), exitAfter (s: movement input may cancel the node after that,
-- the game's "exit_passive" opportunity), air (an airborne pose the air logic may replace)
function P.Start(ent, path, opts)
	local tracks = ALEX_MERCER_GRAPH and ALEX_MERCER_GRAPH[path]
	if not tracks then return P.StartBlend(ent, path, opts) end
	local fb = fullBody(tracks)
	if #fb == 0 then return false end
	ent.MercerNode = {path = path, tracks = fb, t0 = CurTime(), opts = opts or {}}
	if P.Debug then P.Debug(ent, "start", path) end
	return true
end

-- Directional blend node. opts.duration (s) makes it one-shot (the game's track window), otherwise it
-- loops; opts.full = horizontal speed (m/s) where the directional entries take over from the center.
function P.StartBlend(ent, path, opts)
	local b = ALEX_MERCER_DIRBLEND and ALEX_MERCER_DIRBLEND[path]
	if not b then return false end
	ent.MercerNode = {path = path, blend = b, t0 = CurTime(), opts = opts or {}}
	if P.Debug then P.Debug(ent, "blend", path) end
	return true
end

function P.Stop(ent)
	if P.Debug and ent.MercerNode then P.Debug(ent, "stop", ent.MercerNode.path) end
	ent.MercerNode = nil
end

function P.Playing(ent, path)
	return ent.MercerNode ~= nil and (path == nil or ent.MercerNode.path == path)
end

function P.Elapsed(ent)
	return ent.MercerNode and CurTime() - ent.MercerNode.t0 or 0
end

-- may movement input end the current node (the game's exit_passive)?
function P.CanExit(ent)
	local st = ent.MercerNode
	return st ~= nil and st.opts.exitAfter ~= nil and CurTime() - st.t0 >= st.opts.exitAfter
end

-- may a press (Attack, Special, Action) end the current node (the game's exit_active, at its own time)? Earlier than movement, often
function P.CanPress(ent)
	local st = ent.MercerNode
	if not st then return false end
	local t = CurTime() - st.t0
	if st.opts.exitAfter ~= nil and t >= st.opts.exitAfter then return true end
	return st.opts.pressAfter ~= nil and t >= st.opts.pressAfter
end

local function blendEntry(ent, st)
	local b = st.blend
	local v = ent:GetVelocity()
	v.z = 0
	local speed = v:Length() / M2U
	local full = st.opts.full or 2.5
	local want = "center"
	if speed > full * 0.5 then
		local f, r = ent:GetForward(), ent:GetRight()
		local vf, vr = v:Dot(f), v:Dot(r)
		if math.abs(vf) >= math.abs(vr) then want = vf >= 0 and "forward" or "back"
		else want = vr >= 0 and "right" or "left" end
	end
	-- hysteresis: switch only when the new direction held for a moment (the game blends weights)
	if st.entry == nil then
		st.entry = want
	elseif want ~= st.entry then
		if st.pending ~= want then st.pending, st.pendingSince = want, CurTime() end
		if CurTime() - st.pendingSince > 0.15 then st.entry, st.pending = want, nil end
	else
		st.pending = nil
	end
	return b[st.entry] or b.center
end

local function sampleBlend(ent, st)
	local e = blendEntry(ent, st)
	local t = CurTime() - st.t0
	local n = frames(e.anim)
	local f1 = e.f1 >= 0 and e.f1 or n - 1
	local span = math.max(f1 - e.f0, 1)
	local done = false
	local frame
	if st.opts.duration then
		-- one-shot window: the whole frame range spread over the track's duration
		local k = math.Clamp(t / st.opts.duration, 0, 1)
		frame = e.f0 + span * k
		done = t >= st.opts.duration
	else
		frame = e.f0 + (t * FPS * math.abs(e.rate)) % span
	end
	return e.anim, math.Clamp(frame / math.max(n - 1, 1), 0, 1), done
end

-- Blending. Source's client blends every sequence change itself (CSequenceTransitioner, over min(fadeout of the old,
-- fadein of the new) from the QC, set from the graph's track blend times in tools/build_all.py FADEIN / FADEOUT).
-- The claws' nodes are frames of ONE anim (alex_claw_4hitcombo: the combo links jump up to 1 m on a hand), so for
-- the anims in SEQBLEND a frame jump restarts the sequence (ResetSequence bumps the new-sequence parity of a
-- non-looping sequence) and the client blends that jump the same way.
-- (Overlay layers were tried for this: with no FrameAdvance during graph nodes the client stopped latching the
-- layers AND the base cycle until the node ended - frozen poses in jumps / elbow drop / wall run. Removed.)
local JUMP_FRAMES = 2.5 -- a frame jump bigger than this is a pose jump
P.SEQBLEND = {alex_claw_4hitcombo = true, alex_claw_groundspike = true, alex_blades_attack_a = true,
	alex_blades_attack_b = true, alex_blades_attack_c = true, alex_blades_attack_d = true, alex_blades_dash = true,
	-- (the windups a tap cuts: their release is a frame jump in the same anim)
	alex_pnch_3hit_combo = true, alex_special_knee_left = true, alex_special_spin_kick_right = true, alex_special_axe_handle = true,
	-- (a tap skips the hold: the release is a frame jump too)
	alex_special_mach_breaker = true, alex_special_spin_kick_left = true, alex_special_backhand_left = true, alex_kick_1 = true,
	alex_hammer_air_elbow = true, alex_ground_stomp = true, alex_kick_stomp_mir = true, alex_weap_2hnd_throw = true,
	alex_blades_air_attack = true, alex_hammer_4hit_combo = true, alex_hammer_3hit_combo = true,
	alex_hammer_devastator = true, alex_whip_3hitcombo = true, alex_whip_3hitcombo_max = true, alex_whip_sweep = true,
	alex_whip_sweep_max = true, alex_whip_longshot = true, alex_whip_pullback = true, alex_hammer_air_toss = true,
	alex_bullet_smash_stomp = true,
	alex_kick_air_straight_enemy_grind_gv = true, -- man_grind: loop 15-25 -> its kick 35
	-- (user 2026-11-04: "рванно" in his jumps) his fall's: no change of sequence, no blend. The client's log: long_D 84 -> 63 x399, the air pose's loop (hands 25 u, pelvis 10 u, a
	-- frame there is 1.6 u) and a run jump's end into it; charged_stand 66 -> 75 x225, a charged jump's end into the fall (hands 20 u)
	alex_loco_jump_long_d = true, alex_loco_jump_charged_stand = true,
	-- (user 2026-11-04: "Пусть все анимации проверит где есть вот эти неровности и резкость, пусть все уберёт"; tools/anim_jerk_audit.py) a node started again on its own anim, or a blend's
	-- loop coming round: the whole body in one tick. An air dash again from mid-dash 39 u (x1753 in the log), the pedal 26 u, the critical pain's cut 15 -> 31 57 u (the game blends that one, its track's
	-- blendIn 0.1667), the long jumps' side poses' wrap 41-57 u, the parkour exits' 23-46 u, the grab's fall 40 u. No strike's own start here: alex_kick_air_straight's stay as they are
	alex_loco_aerial_dash = true, alex_loco_pedal_straight = true, alex_loco_jump_tact_fwd_right = true, alex_dev_charge = true, alex_dev_critical_pain = true,
	alex_loco_parkour_step_left = true, alex_loco_parkour_step_right = true, alex_loco_parkour_small_basic = true, alex_loco_wall_slide = true,
	alex_loco_jump_long_d_2 = true, alex_loco_jump_long_d_fwd = true, alex_loco_jump_long_back = true, alex_loco_jump_long_left = true, alex_loco_jump_long_right = true,
	alex_loco_jump_long_charged = true, alex_loco_grap_dash_gv = true, alex_loco_grap_jump_b_gv = true, alex_wall_run_up_split = true}

-- frames per second the track advances
local function trackFps(tr)
	if tr.stop >= 0 and tr.stop > tr.start then
		local f1 = tr.f1 >= 0 and tr.f1 or frames(tr.anim) - 1
		return math.abs(f1 - tr.f0) / (tr.stop - tr.start)
	end
	return FPS * math.abs(tr.rate)
end

function P.BlendThink() end -- (kept for callers; nothing to do without overlay layers)

-- returns anim name, cycle (0..1), finished
function P.Sample(ent)
	local st = ent.MercerNode
	if not st then return end
	if st.blend then return sampleBlend(ent, st) end
	local t = CurTime() - st.t0
	local tr, done
	for _, x in ipairs(st.tracks) do
		if t >= x.start and t < trackEnd(x) then tr = x break end
	end
	if not tr then
		tr = st.tracks[#st.tracks]
		done = true
		t = math.min(t, trackEnd(tr))
	end
	local n = frames(tr.anim)
	local f1 = tr.f1 >= 0 and tr.f1 or n - 1
	local frame
	if tr.stop >= 0 and tr.stop > tr.start then
		local k = math.Clamp((t - tr.start) / (tr.stop - tr.start), 0, 1)
		if tr.rate < 0 then frame = f1 - (f1 - tr.f0) * k else frame = tr.f0 + (f1 - tr.f0) * k end
	else
		local adv = (t - tr.start) * FPS * math.abs(tr.rate)
		local span = math.max(f1 - tr.f0, 1)
		if tr.cyclic then frame = tr.f0 + adv % span else frame = math.min(tr.f0 + adv, f1) end
	end
	return tr.anim, math.Clamp(frame / math.max(n - 1, 1), 0, 1), done, tr
end

-- Called from ENT:BodyUpdate. Returns true while a node drives the body.
function P.Update(ent)
	local st = ent.MercerNode
	if not st then return false end
	local anim, cycle, done, tr = P.Sample(ent)
	if done then
		if st.opts.loop then
			st.t0 = CurTime()
			anim, cycle, _, tr = P.Sample(ent)
		elseif st.opts.next then
			if not P.Start(ent, st.opts.next, st.opts.nextOpts) then ent.MercerNode = nil return false end
			anim, cycle, _, tr = P.Sample(ent)
		elseif st.opts.hold then
			-- keep the last frame until someone stops the node
		else
			if P.Debug then P.Debug(ent, "done", st.path) end
			ent.MercerNode = nil
			if st.opts.onDone then st.opts.onDone(ent) end
			return ent.MercerNode ~= nil and P.Update(ent) or false
		end
	end
	-- BODYPIN anims (tools/build_all.py): their body's own turn was baked out of the model; the entity takes it here,
	-- from the node's start yaw, so at the end it already faces where the body does (no snap round)
	local by = SERVER and ALEX_MERCER_BODYYAW and ALEX_MERCER_BODYYAW[string.lower(anim)]
	if by and #by > 0 then
		local f = cycle * (frames(anim) - 1)
		local i = math.Clamp(math.floor(f), 0, #by - 1)
		local j = math.min(i + 1, #by - 1)
		local y = Lerp(math.Clamp(f - i, 0, 1), by[i + 1], by[j + 1])
		if st.byAnim ~= anim then st.byAnim, st.byYaw0 = anim, ent:GetAngles().y end
		ent:SetAngles(Angle(0, st.byYaw0 + y - by[1], 0))
	end
	local seq = ent:LookupSequence(anim)
	if seq < 0 then
		if P.Debug then P.Debug(ent, "MISSING SEQUENCE " .. tostring(anim), st.path) end
		ent.MercerNode = nil
		return false
	end
	-- a frame jump inside a SEQBLEND anim: restart it so the client blends the jump like a sequence change
	local jump = false
	if SERVER and tr and P.SEQBLEND[string.lower(anim)] and ent:GetSequence() == seq then
		local last = ent.MercerGPLast
		if last ~= nil and last.seq == seq and CurTime() - last.t < 0.1 and CurTime() - (ent.MercerReblendT or 0) > 0.025 then
			local n = frames(anim)
			-- a finished (held) track stands still
			local adv = last.fin and 0 or trackFps(last.tr) * (CurTime() - last.t) * (st.opts.speed or 1)
			local expect = ent:GetCycle() + adv / math.max(n - 1, 1)
			jump = math.abs(cycle - expect) * (n - 1) > JUMP_FRAMES
		end
	elseif SERVER and st.blend and P.SEQBLEND[string.lower(anim)] and ent:GetSequence() == seq and CurTime() - (ent.MercerReblendT or 0) > 0.025 then
		-- (a directional blend has no track: its loop's wrap and a node's end into it, against what is on him now; a tick is half a frame)
		jump = math.abs(cycle - ent:GetCycle()) * (frames(anim) - 1) > JUMP_FRAMES
	end
	if SERVER and tr then
		ent.MercerGPLast = {t = CurTime(), seq = seq, tr = tr,
			fin = done or CurTime() - ent.MercerNode.t0 >= trackEnd(tr)}
	end
	if jump then ent.MercerReblendT = CurTime() end
	if jump then
		if P.Debug then P.Debug(ent, "reblend", anim) end
		ent:ResetSequence(seq)
	end
	if ent:GetSequence() ~= seq then ent:ResetSequence(seq) end
	-- (user 2026-10-28, multiplayer: run starts / jumps very jerky) at rate 0 a client only moves the pose when an
	-- update arrives (20-30 a second, some lost): in multiplayer the track's own speed is sent (its frames per second /
	-- the sequences' 30, reversed for a backwards track, 0 on a held frame) so the client plays on between updates and
	-- the server's cycle corrects it; single player keeps 0 (unchanged)
	local pr = 0
	if SERVER and tr and not done and not game.SinglePlayer() and tr.f0 ~= tr.f1 then
		pr = trackFps(tr) / FPS * (tr.rate < 0 and -1 or 1) * (st.opts.speed or 1)
	end
	ent:SetPlaybackRate(pr)
	-- (user 2026-10-22: the anim tore at the wall's top - alex_wall_run_top held on its last frame flickered to
	-- frame 0: a looping sequence's cycle 1 is its 0) a held last frame stops just short of 1
	-- (2026-10-27, the flying kick hunt - client trace: the server held cycle 0.528, the client fell to 0.004 = frame 0
	-- the moment it stopped changing, and stayed there: "a ball" all day) a held frame never stands still: every other
	-- tick 0.0004 lower (1/70 of a frame here, unseen), so the client keeps taking the server's cycle
	-- (user 2026-10-28: runs / jumps got uneven) only a frame that really stands still is wiggled; a playing anim's
	-- cycle is left exactly as sampled
	local c = math.min(cycle, 0.999)
	if SERVER then
		local held = ent.MercerGPSeq == seq and math.abs(c - (ent.MercerGPCyc or -1)) < 0.00001
		ent.MercerGPSeq, ent.MercerGPCyc = seq, c
		if held then
			ent.MercerGPWiggle = not ent.MercerGPWiggle
			if ent.MercerGPWiggle then c = math.max(0, c - 0.0004) end
		end
	end
	ent:SetCycle(c)
	return true
end

function P.CurrentAnim(ent)
	if not ent.MercerNode then return end
	return (P.Sample(ent))
end

-- (user 2026-11-04, the same) DrGBase's own update (every 0.1 s, and at once when he leaves or lands on the ground) asks for the node's anim and, the body not on it yet, starts it at
-- cycle 0: until the next BodyUpdate he stood on frame 0 of it. The log: alex_loco_jump_land_heavy frame 0, then 8 or 9, x371 of 2337, a hand 72 u in a tick at its fade of 0.033. So the node's
-- anim goes on here with its real frame, and DrGBase has nothing to start
function P.EnterNow(ent)
	if not ent.MercerNode then return end
	local anim, cycle = P.Sample(ent)
	if not anim then return end
	local seq = ent:LookupSequence(anim)
	if seq >= 0 and ent:GetSequence() ~= seq then
		ent:ResetSequence(seq)
		ent:SetCycle(math.min(cycle, 0.999))
	end
	return anim
end
-