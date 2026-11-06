- The consume's tendrils (prototype_consume consume/stuff/tendrils_from_parent/<set>: tendrilFromParent items, run
-- by the giver's "execute" at the finisher's own time). Each lashes out of one of his joints to one of the victim's:
-- it leaves his joint turned zAxisRotation about the line to the target and xAxisRotation away from it, curls round
-- (circleRadius) and homes in, growing at forwardVelocity, and holds the joint on the pulled body too; when that joint
-- starts to flow into him it is gone. All by the engine's code, layoutGame. Drawn with the game's drawable alex_tendril (Tendril_Segment x segmentCount + the spike,
-- tendril_color): models/mercer/alex_tendril.mdl (tools/build_tendril.py) - a chain of bones laid along the curve
-- every frame. The victim's joints come from its puppet (the game's skeleton, alex_mercer_victim.lua).

ALEX_MERCER_TENDRILS = ALEX_MERCER_TENDRILS or {}
local TD = ALEX_MERCER_TENDRILS
local MDL = "models/mercer/alex_tendril.mdl"
local M2U = 39.37
local S = 39.3701 -- the model's segment: 1 game metre
local N = 10      -- the model's chain
local SPIKE = 0.1761 -- Tendril_SpikeShape's length (m)

-- {begin s, scale, his joint, its joint, forwardVelocity, reverseVelocity, circleRadius, zAxisRotation,
--  xAxisRotation, segmentCount, wave {waveSpeed, waveLength, waveAmplitude}}
local SETS = {
	chest_punch = {
		{0, 0.3, "Spine_3", "Pelvis", 2, 2, 0.3, 60, 160, 10},
		{0.0667, 0.2, "Hip_R", "Neck", 4, 4, 0.3, 90, 70, 10},
		{0.1, 0.5, "Pelvis", "Hip_L", 4, 4, 0.2, 45, 45, 10},
		{0.1333, 0.3, "Spine_2", "Spine_2", 5, 5, 0.2, -90, 45, 10},
	},
	head_stomp = {
		{0, 0.4, "Spine_3", "Pelvis", 2, 2, 0.2, 60, 120, 10},
		{0.0667, 0.4, "Hip_R", "Hip_R", 4, 4, 0.2, 90, 70, 10},
		{0.1, 0.5, "Pelvis", "Hip_L", 4, 4, 0.2, 45, 70, 10},
		{0.1333, 0.3, "Spine_2", "Spine_2", 5, 5, 0.3, -90, 70, 10},
	},
	beatdown = {
		{0, 0.3, "Spine_3", "Pelvis", 2, 2, 0.3, 60, 120, 10},
		{0.0333, 0.6, "Hip_L", "Shoulder_L", 4, 4, 0.3, -90, 90, 10},
		{0.0667, 0.2, "Hip_R", "Knee_R", 4, 4, 0.3, 90, 70, 10},
	},
	wave = {
		{0.1667, 0.5, "Spine_2", "Shoulder_R", 4, 5, 0.472, -99.5, 90, 5, {10, 5, 0.1, 0.1, 0.1}},
	},
	-- the Hunter's consume and the Leader's (prototype holding/grabbing/brawler/consumes S38, S51: the same five `tendril` items of his node, each by the item's own numbers:
	-- 2 - 3 m/s out, 6 m/s back from 1.333 s, wide curls). The body's joints come off the body itself (TD.Start's pup)
	hunter_consume = {
		-- (user 2026-11-05: "почему они такие тонкие и без анимок". By the game's own code: layoutGame. The wave: {speed m/s, length m, amplitude m, ramp up, ramp down}; then its timeReverse, s from its own start)
		{0.3333, 0.5, "Spine_2", "Spine_3", 2.7, 6, 0.75, -50, -115, 10, {0.2, 2, 0.5, 0.2, 0.2}, 1.333},
		{0.3333, 0.4, "Clavicle_R", "Spine_3", 3, 6, 0.4, 40, 115, 10, {0.1, 10, 0.1, 0.2, 0.2}, 1.333},
		{0.3, 0.55, "Spine_2", "Shoulder_R", 2.25, 6, 0.5, -100, 100, 10, {0.1, 7, 1, 0.2, 0.2}, 1.333},
		{0.3333, 0.4, "Spine_3", "Spine_2", 2.25, 6, 0.4, -85, 115, 10, {0.5, 2, 0.5, 0.2, 0.2}, 1.333},
		{0.3333, 0.4, "Spine_2", "Spine_1", 2, 6, 0.4, -60, 115, 10, {0.5, 5, 0.2, 0.1, 0.1}, 1.333},
	},
}
-- each finisher's set and the receiver's execute time (s from the node's start)
TD.FINISHERS = {
	chest_punch = {"chest_punch", 1.167}, smash_throw = {"chest_punch", 1.167}, knee_head = {"wave", 1},
	head_stomp = {"head_stomp", 1.133}, beatdown = {"beatdown", 3.333}, crush_head = {"chest_punch", 1.667},
	headsmush = {"wave", 2.033}, headdrop = {"wave", 1.933}, heart_to_head = {"chest_punch", 1.333},
	lash = {"head_stomp", 1.7}, readjust = {"chest_punch", 1.167}, hunter_consume = {"hunter_consume", 0},
}

-- the devastators' tendrils (graph_devastator, tendril items: start joint (his), the target's joint, scale,
-- forwardVelocity, reverseVelocity, circleRadius, rotations, segmentCount, wave): Critical Pain (the target nodes
-- #5836bf..: out of his wrists, thick, 5 / 15 segments) and the Tendril Barrage (default store: shoulders / spine);
-- one per target, at random from its set
local DEV = {
	cp = {
		{0, 1, "Wrist_R", "Spine_3", 35, 200, 0.5, 50, 50, 5, {3, 14, 0.5}},
		{0, 1.5, "Wrist_R", "Spine_3", 30, 200, 0.5, 180, -50, 5, {5, 10, 0.3}},
		{0, 2, "Wrist_L", "Spine_3", 30, 200, 0.5, 180, 50, 15, {2, 16, 0.15}},
		{0, 1.6, "Wrist_L", "Spine_3", 30, 200, 0.5, 90, -50, 5, {7, 7, 0.4}},
		{0, 2, "Wrist_L", "Spine_3", 30, 200, 0.5, 120, 50, 5, {2, 12, 0.25}},
		{0, 1, "Wrist_R", "Spine_3", 30, 200, 0.5, 50, -50, 5, {3, 14, 0.5}},
		{0, 1.5, "Wrist_R", "Spine_3", 30, 200, 0.5, 180, 50, 5, {5, 10, 0.3}},
		{0, 2, "Wrist_R", "Spine_3", 30, 200, 0.5, 180, -50, 15, {2, 16, 0.15}},
	},
	-- (the pack's Supreme Hunter, its critical: graph_supreme_hunter M961-965 at Mercer - out of its Spine_3, x2, 15 m/s, back at 20, 15 segments -
	-- and its store {tendrils} M133-137 at the rest, x0.25 out of its shoulders and spine; their forward velocity is 0 in the items: drawn at the barrage's 30, BY EYE)
	sh = {
		{0, 2, "Spine_3", "Spine_3", 15, 20, 1, 0, 0, 15, {6, 12, 1}},
		{0, 2, "Spine_3", "Shoulder_L", 15, 20, 1, 0, 0, 15, {2, 15, 1}},
		{0, 2, "Spine_3", "Shoulder_R", 15, 20, 1, -90, -90, 15, {4, 13, 0.5}},
		{0, 0.25, "Shoulder_R", "Spine_3", 30, 20, 1, 0, 0, 15, {3, 14, 0.5}},
		{0, 0.25, "Shoulder_L", "Spine_3", 30, 16, 1, 270, 5, 15, {5, 10, 0.3}},
		{0, 0.25, "Spine_1", "Spine_3", 30, 22, 1, 180, 0, 15, {2, 16, 0.15}},
		{0, 0.25, "Spine_3", "Spine_3", 30, 18, 1, 0, 0, 15, {7, 7, 0.4}},
		{0, 0.25, "Spine_2", "Spine_3", 30, 14, 1, 90, 0, 15, {2, 12, 0.25}},
	},
	tb = {
		{0, 0.4, "Shoulder_R", "Spine_3", 30, 1000, 1, 0, 0, 10, {3, 14, 0.5}},
		{0, 0.7, "Shoulder_L", "Spine_3", 30, 350, 1, 270, 5, 10, {5, 10, 0.3}},
		{0, 0.5, "Spine_1", "Spine_3", 30, 350, 1, 180, 0, 10, {2, 16, 0.15}},
		{0, 0.6, "Spine_3", "Spine_3", 30, 350, 1, 0, 0, 10, {7, 7, 0.4}},
		{0, 0.35, "Spine_2", "Spine_3", 30, 350, 1, 90, 0, 10, {2, 12, 0.25}},
	},
}

local active = {}
local TB_REV = 40 -- m/s: the Tendril Barrage's draw-back (user: slower than the graph's 350-1000; the video)

-- the game's joint on any body: his own / the victim puppet's names; an HL2 skeleton's equivalent; its centre
local VB = {Spine_3 = "ValveBiped.Bip01_Spine2", Spine_2 = "ValveBiped.Bip01_Spine1", Spine_1 = "ValveBiped.Bip01_Spine",
	Pelvis = "ValveBiped.Bip01_Pelvis", Neck = "ValveBiped.Bip01_Neck1", Head = "ValveBiped.Bip01_Head1",
	Hip_L = "ValveBiped.Bip01_L_Thigh", Hip_R = "ValveBiped.Bip01_R_Thigh", Knee_L = "ValveBiped.Bip01_L_Calf",
	Knee_R = "ValveBiped.Bip01_R_Calf", Ankle_L = "ValveBiped.Bip01_L_Foot", Ankle_R = "ValveBiped.Bip01_R_Foot",
	Shoulder_L = "ValveBiped.Bip01_L_UpperArm", Shoulder_R = "ValveBiped.Bip01_R_UpperArm"}
local function bonePos(e, name)
	if not IsValid(e) then return end
	local b = e:LookupBone(name) or (VB[name] and e:LookupBone(VB[name]))
	local m = b and e:GetBoneMatrix(b)
	if m then return m:GetTranslation() end
	if name == "Motion_Root" then return e:GetPos() end
	return e:WorldSpaceCenter()
end

-- a devastator tendril at a target (net from the server)
net.Receive("alex_mercer_tendril", function()
	local m, target = net.ReadEntity(), net.ReadEntity()
	local set, idx, t1, tRev = net.ReadString(), net.ReadUInt(5), net.ReadFloat(), net.ReadFloat()
	local it = DEV[set] and DEV[set][idx]
	-- (user: some Critical Pain tendrils came in from the side, bent - the game's all go one way) no turn / curl off
	-- the wrist: straight out at the target
	if it and set == "cp" then it = {it[1], it[2], it[3], it[4], it[5], it[6], 0, 0, 0, it[10], it[11]} end
	if it and IsValid(m) and IsValid(target) then
		-- the Tendril Barrage's are the wet, thick ones (user: slimy, glossy, bigger)
		-- (user 2026-10-22: the barrage's tendrils "not the right colour" - the wet look was ours) the game's own
		-- tendril material for all; the barrage's kept thicker (user: bigger)
		-- (user: the barrage's tendrils went back into him too fast - the graph's 350-1000 m/s) drawn back at 60 m/s
		active[#active + 1] = {m = m, pup = target, it = it, t1 = t1, tRev = tRev, rev = set == "tb" and TB_REV or nil}
	end
end)

-- the Tendril Barrage's burst (graph_effects sonic_clap/critical): besides the target tendrils, eight Persistent
-- tendril effects at yaw 0, +-45, +-90, +-135, 180 for 0.6667 s (life 2 s) - they lash out all round whoever is near;
-- sonic_clap/retract (t1 + 1.9333) draws them back. Each direction a fan of three (low into the ground, level, up),
-- ending where they strike the world. The red burst at the clap: blood mist / steam thrown out and up, blood where
-- the tendrils strike.
local RING_YAW = {0, -45, -135, -90, -180, -225, 90, 45}
local debrisMoving
local zoomBlurs
local RING_PITCH = {-28, -6, 18}
local RING_JOINT = {"Shoulder_R", "Shoulder_L", "Spine_1", "Spine_3", "Spine_2"}
local function redBurst(m)
	if not IsValid(m) then return end
	local o = bonePos(m, "Spine_2") or m:WorldSpaceCenter()
	local em = ParticleEmitter(o)
	if not em then return end
	for i = 1, 36 do
		local d = VectorRand()
		d.z = math.abs(d.z) * 0.5
		d:Normalize()
		local p = em:Add("particle/particle_smokegrenade", o + d * 12)
		if p then
			p:SetVelocity(d * math.Rand(350, 900))
			p:SetAirResistance(220)
			p:SetGravity(Vector(0, 0, -40))
			p:SetDieTime(math.Rand(1.4, 2.6))
			p:SetStartAlpha(math.random(170, 230))
			p:SetEndAlpha(0)
			p:SetStartSize(math.Rand(25, 45))
			p:SetEndSize(math.Rand(120, 200))
			p:SetRoll(math.Rand(0, 360))
			p:SetRollDelta(math.Rand(-1, 1))
			p:SetColor(math.random(28, 50), math.random(0, 4), math.random(0, 4)) -- (user: black-red, not pink)
		end
	end
	for i = 1, 12 do
		local p = em:Add("particle/smokesprites_000" .. math.random(9), o + VectorRand() * 20)
		if p then
			p:SetVelocity(Vector(math.Rand(-80, 80), math.Rand(-80, 80), math.Rand(120, 260)))
			p:SetAirResistance(60)
			p:SetDieTime(math.Rand(2, 3.2))
			p:SetStartAlpha(110)
			p:SetEndAlpha(0)
			p:SetStartSize(30)
			p:SetEndSize(math.Rand(140, 220))
			p:SetRoll(math.Rand(0, 360))
			p:SetRollDelta(math.Rand(-0.5, 0.5))
			p:SetColor(38, 12, 12)
		end
	end
	em:Finish()
	for i = 1, 6 do
		local ed = EffectData()
		ed:SetOrigin(o + VectorRand() * 30)
		util.Effect("BloodImpact", ed)
	end
end

-- debrisMoving001 (startup_effects; sonic_clap/critical and /retract, 8 Persistent items over 0.6667 s): big biomass
-- clumps (3.5 +- 1 m, 16 +- 1 frames, 0.8 a frame on each of the 8) - (user 2026-10-22: they come out of the centre
-- WITH the tendrils and are drawn back in with them, dark like all the other biomass) thrown from him along the
-- spokes at the tendrils' 30 m/s (forwardVelocity), dying where a spoke ends; at the draw-back laid on what is left of
-- each spoke and pulled in at its 40 m/s (TB_REV), dying as they reach him. The dark biomass = debrisTransform002's
-- look (charge), not the hot one (user: too light, pink)
local CLUMP = {b = {size = 10, sizeVar = 10}}
debrisMoving = function(m, retract, spokes)
	local V = ALEX_MERCER_VFX
	if not (V and V.Emit and V.EMITTERS and V.EMITTERS.charge) or #spokes == 0 then return end
	local E = V.EMITTERS
	local acc = 0
	for f = 0, 19 do
		timer.Simple(f / 30, function()
			if not IsValid(m) then return end
			local o = bonePos(m, "Spine_2") or m:WorldSpaceCenter()
			-- (user 2026-10-22: too many at the burst) the burst a third of the 8 items' 0.8 a frame, the draw-back all
			acc = acc + 0.8 * (retract and 8 or 2.5)
			local n = math.floor(acc)
			acc = acc - n
			for _ = 1, n do
				local sp = spokes[math.random(#spokes)]
				local d, L = sp[1], sp[2]
				if retract then
					-- on the part of the spoke not yet drawn in, coming in with it
					local left = L - TB_REV * f / 30
					if left > 1 then
						local r = math.Rand(0.3, 1) * left
						V.Emit(E.charge, o + d * (r * M2U), d, nil, 1, 1, {b = CLUMP.b, vel = d * (-TB_REV * M2U),
							life = r / TB_REV, drag = 0})
					end
				else
					local s = math.Rand(0.5, 1) * 30
					V.Emit(E.charge, o + VectorRand() * 12, d, nil, 1, 1, {b = CLUMP.b, vel = d * (s * M2U),
						life = math.min(math.Rand(0.35, 0.6), L / s), drag = 0})
				end
			end
		end)
	end
end

-- (user 2026-10-22, the graph + the game's video 1:34-1:41) the barrage: the dark ball swelling out of him, then the
-- devastator track's spokes - minTargetCount 60 less the targets (their own tendrils come from the server) - STRAIGHT,
-- evenly round him: randomHeightArc 80 (in the air -40..40 deg), minHeightArcOnGround 5 (on the ground 5..40 deg), out
-- to the first surface, the track's radius 30 m at most; held, drawn back at sonic_clap/retract
local GOLD = math.pi * (3 - math.sqrt(5))
local shimmers = {}
net.Receive("alex_mercer_tendril_ring", function()
	local m, t1, tRev, air, n = net.ReadEntity(), net.ReadFloat(), net.ReadFloat(), net.ReadBool(), net.ReadUInt(7)
	if not IsValid(m) then return end
	local o = bonePos(m, "Spine_2") or m:WorldSpaceCenter()
	local tb = DEV.tb
	-- (user 2026-10-22: they kept going down) randomHeightArc 80 = the whole arc, 40 above and below the horizon;
	-- minHeightArcOnGround 5: on the ground 5..40 up
	local zlo, zhi = math.sin(math.rad(air and -40 or 5)), math.sin(math.rad(40))
	local spokes = {}
	for i = 0, n - 1 do
		-- a Fibonacci spiral over the band of heights: even spokes, no clumps
		local z = zhi - (zhi - zlo) * (i + 0.5) / n
		local rr = math.sqrt(math.max(0, 1 - z * z))
		local th = GOLD * i + math.Rand(-0.08, 0.08)
		local d = Vector(math.cos(th) * rr, math.sin(th) * rr, z)
		local tr = util.TraceLine({start = o, endpos = o + d * 30 * M2U, filter = m, mask = MASK_SOLID_BRUSHONLY})
		spokes[#spokes + 1] = {d, tr.Fraction * 30}
		local base = tb[math.random(#tb)]
		local it = {0, math.Rand(0.35, 0.7), RING_JOINT[math.random(#RING_JOINT)], nil, base[5], base[6], 0, 0, 0,
			base[10], base[11]}
		local x = {m = m, b = tr.HitPos, it = it, t1 = t1 + math.Rand(0, 0.06), tRev = tRev, rev = TB_REV}
		active[#active + 1] = x
		if tr.Hit then
			-- (user: every tendril strikes) where a spoke hits the world: a crush of dust and chips, the impact's sound
			local hp, hn, far = tr.HitPos, tr.HitNormal, tr.Fraction * 30
			timer.Simple(math.max(0, x.t1 - CurTime()) + far / base[5], function()
				local V = ALEX_MERCER_VFX
				if V and V.Emit and V.EMITTERS then
					local E = V.EMITTERS
					if E.crush_dust then V.Emit(E.crush_dust, hp + hn * 4, hn, nil, 0.6) end
					if E.crush_chunks then V.Emit(E.crush_chunks, hp + hn * 4, hn, nil, 0.8) end
				end
				if i % 2 == 0 then
					sound.Play("physics/concrete/concrete_impact_hard" .. math.random(3) .. ".wav", hp, 80, math.random(85, 110), 0.8)
				end
			end)
		end
	end
	timer.Simple(math.max(0, t1 - CurTime()), function()
		if not IsValid(m) then return end
		redBurst(m)
		debrisMoving(m, false, spokes)
		-- sonic_clap/critical's shockWave001 is the slams' ring; the devastator bubble (shockWave002, the huge
		-- landings') round him as the tendrils burst out
		local V = ALEX_MERCER_VFX
		if V and V.Wave then V.Wave(2, bonePos(m, "Spine_2") or m:WorldSpaceCenter(), 2.5) end
		-- the dark ball of tendrils swelling out first (the video's first 0.4 s)
		local V = ALEX_MERCER_VFX
		if V and V.Emit and V.EMITTERS and V.EMITTERS.charge then
			V.Emit(V.EMITTERS.charge, bonePos(m, "Spine_2") or m:WorldSpaceCenter(), Vector(0, 0, 1), nil, 3.5, 12)
		end
		-- sonic_clap/critical radialBlur: duration 0.5 s, intensity 100 -> 0, size 0 -> 2, falloff 0 -> 10
		zoomBlurs[#zoomBlurs + 1] = {m = m, t0 = CurTime(), dur = 0.5, i = {1, 0}, s = {0, 2}, f = {0, 10}}
		-- (user: the space warps with the tendrils) the ripples go out with them at 30 m/s, fading
		shimmers[#shimmers + 1] = {m = m, t0 = CurTime(), dur = 1, r = {0, 30}, a = {0.3, 0.05}}
	end)
	timer.Simple(math.max(0, tRev - CurTime()), function()
		if not IsValid(m) then return end
		debrisMoving(m, true, spokes)
		-- sonic_clap/retract radialBlur: duration 1 s, intensity 0 -> 30, size 30 -> 2, falloff 0 -> 10
		zoomBlurs[#zoomBlurs + 1] = {m = m, t0 = CurTime(), dur = 1, i = {0, 0.3}, s = {30, 2}, f = {0, 10}}
		-- and come back in with them at 40 m/s
		shimmers[#shimmers + 1] = {m = m, t0 = CurTime(), dur = 0.75, r = {30, 0}, a = {0.15, 0.3}}
	end)
end)

-- (user 2026-10-22) the explosion's caught drawn in by its tendrils and consumed: their client ragdolls (found by
-- their owner's index as the engine makes them) pulled at his chest at the tendrils' 40 m/s, a trail of biomass
-- after them; arriving (or stuck / 2.5 s) they burst into dark biomass and are gone
local ragOf, pulls = {}, {}
hook.Add("CreateClientsideRagdoll", "AlexMercerTBRags", function(owner, rag)
	if IsValid(owner) then ragOf[owner:EntIndex()] = rag end
end)
local function burst(p, n)
	local V = ALEX_MERCER_VFX
	if V and V.Emit and V.EMITTERS and V.EMITTERS.charge then
		V.Emit(V.EMITTERS.charge, p, Vector(0, 0, 1), nil, 2.2, n)
		if V.EMITTERS.hit_bio then V.Emit(V.EMITTERS.hit_bio, p, Vector(0, 0, 1), nil, 1.5, 3) end
	end
end
local function addPull(m, rag)
	if not IsValid(rag) or rag.MercerPulled or rag:GetNoDraw() then return end
	rag.MercerPulled = true
	pulls[#pulls + 1] = {m = m, rag = rag, t0 = CurTime(), best = math.huge, bestT = CurTime()}
end
net.Receive("alex_mercer_tb_pull", function()
	local m, n = net.ReadEntity(), net.ReadUInt(6)
	local list = {}
	for i = 1, n do list[i] = ragOf[net.ReadUInt(16)] end
	if not IsValid(m) then return end
	for _, rag in ipairs(list) do addPull(m, rag) end
	-- (user: "to clear the NPCs' bodies off the map") every death ragdoll lying within 30 m too
	local c0 = m:WorldSpaceCenter()
	for _, rag in ipairs(ents.FindByClass("class C_ClientRagdoll")) do
		if #pulls >= 40 then break end
		if rag:WorldSpaceCenter():Distance(c0) < 30 * M2U then addPull(m, rag) end
	end
end)
hook.Add("Think", "AlexMercerTBPull", function()
	if #pulls == 0 then return end
	local now = CurTime()
	for i = #pulls, 1, -1 do
		local q = pulls[i]
		if not (IsValid(q.m) and IsValid(q.rag)) then
			table.remove(pulls, i)
		else
			local tp = bonePos(q.m, "Spine_2") or q.m:WorldSpaceCenter()
			local c = q.rag:WorldSpaceCenter()
			local dist = c:Distance(tp)
			if dist < q.best - 10 then q.best, q.bestT = dist, now end
			if q.eat then
				-- inside him: shrinking into his chest
				local k = (now - q.eat) / 0.3
				if k >= 1 then
					burst(tp, 6)
					q.rag:SetNoDraw(true)
					q.rag:Remove()
					table.remove(pulls, i)
				else
					q.rag:SetModelScale(math.max(0.05, 1 - k), 0)
					for b = 0, q.rag:GetPhysicsObjectCount() - 1 do
						local ph = q.rag:GetPhysicsObjectNum(b)
						if IsValid(ph) then ph:SetVelocity((tp - ph:GetPos()) * 10) end
					end
				end
			elseif dist < 50 then
				q.eat = now
				burst(c, 8)
			elseif now - q.t0 > 2.5 or now - q.bestT > 0.6 then
				-- stuck / too long: dissolved where it is
				burst(c, 10)
				q.rag:SetNoDraw(true)
				q.rag:Remove()
				table.remove(pulls, i)
			else
				for b = 0, q.rag:GetPhysicsObjectCount() - 1 do
					local ph = q.rag:GetPhysicsObjectNum(b)
					if IsValid(ph) then
						ph:EnableGravity(false)
						ph:Wake()
						local to = tp - ph:GetPos()
						ph:SetVelocity(to:GetNormalized() * math.min(TB_REV * M2U, to:Length() * 6))
					end
				end
				local V = ALEX_MERCER_VFX
				if V and V.Emit and V.EMITTERS and V.EMITTERS.charge and now >= (q.fx or 0) then
					q.fx = now + 0.05
					V.Emit(V.EMITTERS.charge, c, (tp - c):GetNormalized(), nil, 1.2, 1)
				end
			end
		end
	end
end)

-- the radialBlur: round the point (him), inside size m and fading out over the falloff beyond it, the frame drawn
-- again and again a little larger (a zoom blur, averaged copies), its strength the intensity (100 = 1)
local ZB = CreateMaterial("alex_mercer_zoomblur2", "UnlitGeneric", {["$basetexture"] = "_rt_FullFrameFB",
	["$translucent"] = "1", ["$vertexalpha"] = "1", ["$vertexcolor"] = "1", ["$ignorez"] = "1"})
-- (the video: the air rippling round the tendrils) a refracting ring that goes out / comes back with them - the
-- game's fxdistortion_shockwave normal map (round, flat at its edges: the shimmer one showed as a hard pink square,
-- user's clip 2026-10-22)
local ZS = CreateMaterial("alex_mercer_tb_shimmer3", "Refract", {["$normalmap"] = "alex_mercer/fx/fxdistortion_shockwave",
	["$refractamount"] = "0", ["$refracttint"] = "[1 1 1]", ["$nocull"] = "1"})
zoomBlurs = {}
local SEG, COPIES = 32, 8
local function blurNow(z, now)
	local e = (now - z.t0) / z.dur
	if e >= 1 or not IsValid(z.m) then return nil end
	return Lerp(e, z.i[1], z.i[2]), Lerp(e, z.s[1], z.s[2]), Lerp(e, z.f[1], z.f[2])
end
hook.Add("RenderScreenspaceEffects", "AlexMercerZoomBlur", function()
	if #zoomBlurs == 0 then return end
	local now = CurTime()
	local W, H = ScrW(), ScrH()
	for zi = #zoomBlurs, 1, -1 do
		local z = zoomBlurs[zi]
		local I, S, F = blurNow(z, now)
		if not I then
			table.remove(zoomBlurs, zi)
		elseif I > 0.005 then
			local c = z.m:WorldSpaceCenter()
			local sp = c:ToScreen()
			local dist = EyePos():Distance(c)
			local rIn, rOut
			if dist <= (S + F) * M2U then
				-- the camera inside the blur's sphere: the whole screen
				rIn, rOut = S * M2U >= dist and W * 2 or 0, W * 2
			else
				local ed = (c + EyeAngles():Right() * ((S + F) * M2U)):ToScreen()
				local px = math.sqrt((ed.x - sp.x) ^ 2 + (ed.y - sp.y) ^ 2)
				rOut, rIn = px, px * S / (S + F)
			end
			if sp.visible and rOut > 2 then
				local cx, cy = sp.x, sp.y
				render.UpdateScreenEffectTexture()
				cam.Start2D()
				render.SetMaterial(ZB)
				for j = 1, COPIES do
					local s = 1 + j * 0.035 * I
					local a = 255 / (j + 1)
					local function vtx(px, py, al)
						mesh.Position(Vector(px, py, 0))
						mesh.TexCoord(0, (cx + (px - cx) / s) / W, (cy + (py - cy) / s) / H)
						mesh.Color(255, 255, 255, al)
						mesh.AdvanceVertex()
					end
					mesh.Begin(MATERIAL_TRIANGLES, SEG * 3)
					for q = 0, SEG - 1 do
						local a0, a1 = q / SEG * 2 * math.pi, (q + 1) / SEG * 2 * math.pi
						local c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
						vtx(cx, cy, a)
						vtx(cx + c0 * rIn, cy + s0 * rIn, a)
						vtx(cx + c1 * rIn, cy + s1 * rIn, a)
						vtx(cx + c0 * rIn, cy + s0 * rIn, a)
						vtx(cx + c0 * rOut, cy + s0 * rOut, 0)
						vtx(cx + c1 * rOut, cy + s1 * rOut, 0)
						vtx(cx + c0 * rIn, cy + s0 * rIn, a)
						vtx(cx + c1 * rOut, cy + s1 * rOut, 0)
						vtx(cx + c1 * rIn, cy + s1 * rIn, a)
					end
					mesh.End()
				end
				cam.End2D()
			end
		end
	end
end)
hook.Add("PostDrawTranslucentRenderables", "AlexMercerZoomShimmer", function(depth, sky)
	if depth or sky or #shimmers == 0 then return end
	local now = CurTime()
	for i = #shimmers, 1, -1 do
		local s = shimmers[i]
		local e = (now - s.t0) / s.dur
		if e >= 1 or not IsValid(s.m) then
			table.remove(shimmers, i)
		else
			local r = math.max(Lerp(e, s.r[1], s.r[2]), 0.5)
			ZS:SetFloat("$refractamount", Lerp(e, s.a[1], s.a[2]))
			render.UpdateRefractTexture()
			render.SetMaterial(ZS)
			local c = bonePos(s.m, "Spine_2") or s.m:WorldSpaceCenter()
			render.DrawQuadEasy(c, (EyePos() - c):GetNormalized(), r * 2 * M2U, r * 2 * M2U, Color(255, 255, 255, 255), 0)
		end
	end
end)

-- Critical Pain's distortion (user 2026-10-22: "in place, a few metres ahead, as in the game"): critical_pain/effects
-- distortionObject004 over 2.333 s on his root 0.536 m ahead, pointing along the aim, biases emission x5, life x0.7,
-- speed x1.5, size x1.5. Its two emitters (startup_effects): distortionShape 0.4 a frame, distortion1Shape 0.2 a frame
-- (spinning), each 15 frames, 2.7 m x size curve 0 -> 3.06, alpha 255 252 222 125 0, 0.2 m a frame along the
-- emitter, 5 deg spread - so the air warps in a body some 3 m deep and up to 12 m across in front of him, staying
-- there while it lasts. Drawn with the game's shockwave normal map (round, soft-edged), untinted (user: no pink).
-- And critical_pain/effects' shockWave001 (0-0.6667 s, on Wrist_L, the sonic wave): its distortionShape, one ring
-- burst at the fire, 15 frames, 2.7 m x 0.5 -> 2.5, alpha 255 252 222 125 0 - round the hand, across the beam
local CPD = CreateMaterial("alex_mercer_cp_dist2", "Refract", {["$normalmap"] = "alex_mercer/fx/fxdistortion_shockwave",
	["$refractamount"] = "0", ["$refracttint"] = "[1 1 1]", ["$nocull"] = "1"})
local CPW_SIZE = {0.5, 0.921, 1.447, 1.974, 2.5}
local cpWaves = {}
local CPD_SIZE = {0, 0.905, 1.584, 2.161, 3.063}
local CPD_ALPHA = {255, 252, 222, 125, 0}
local function curve5(c, k)
	local x = math.Clamp(k, 0, 1) * 4
	local i = math.min(math.floor(x), 3)
	return c[i + 1] + (c[i + 2] - c[i + 1]) * (x - i)
end
local cpDist, cpParts = {}, {}
ALEX_MERCER_CPWAVE = function(m, aim) cpWaves[#cpWaves + 1] = {m = m, aim = aim, t0 = CurTime()} end
-- (user 2026-10-22: too big and in place, like a landing - in the game a sonic cannon) the emitter's 1 m a frame (its
-- Xn) x the speed bias 1.5 = 45 m/s out of his hands: each ring grows from nothing to ~12 m over its 15 m flight - a
-- widening cone of rippling air; the shader's distortion_amount 5 strong
local CPD_LIFE, CPD_SPEED, CPD_BASE = 15 / 30 * 0.7, 1 * 30 * 1.5, 2.7 * 1.5
hook.Add("Think", "AlexMercerCPDistortionEmit", function()
	if #cpDist == 0 then return end
	local now, dt = CurTime(), FrameTime()
	for i = #cpDist, 1, -1 do
		local d = cpDist[i]
		if not IsValid(d.m) or now > d.t1 then
			table.remove(cpDist, i)
		elseif now >= d.t0 then
			-- 0.4 + 0.2 a frame (30 fps) x the emission bias 5
			d.acc = (d.acc or 0) + (0.4 + 0.2) * 5 * 30 * dt
			local hl, hr = bonePos(d.m, "Wrist_L"), bonePos(d.m, "Wrist_R")
			local o = (hl and hr) and (hl + hr) * 0.5 or d.m:GetPos() + d.aim * (0.536 * M2U) + Vector(0, 0, 0.9 * M2U)
			while d.acc >= 1 and #cpParts < 64 do
				d.acc = d.acc - 1
				local a = d.aim:Angle()
				a = Angle(a.p + math.Rand(-5, 5), a.y + math.Rand(-5, 5), 0)
				cpParts[#cpParts + 1] = {p = Vector(o), v = a:Forward() * (CPD_SPEED * M2U), t0 = now,
					life = CPD_LIFE * math.Rand(0.9, 1.1), rot = math.Rand(0, 360), spin = math.random() < 0.33 and math.Rand(-200, 200) or 0}
			end
			d.acc = math.min(d.acc, 1)
		end
	end
end)
hook.Add("PostDrawTranslucentRenderables", "AlexMercerCPDistortion", function(depth, sky)
	if depth or sky or (#cpParts == 0 and #cpWaves == 0) then return end
	local now = CurTime()
	render.UpdateRefractTexture()
	render.SetMaterial(CPD)
	for i = #cpWaves, 1, -1 do
		local w = cpWaves[i]
		local k = (now - w.t0) / 0.5
		if k >= 1 or not IsValid(w.m) then
			table.remove(cpWaves, i)
		else
			local p = bonePos(w.m, "Wrist_L") or w.m:WorldSpaceCenter()
			local sz = 2.7 * curve5(CPW_SIZE, k) * M2U
			CPD:SetFloat("$refractamount", 0.2 * curve5(CPD_ALPHA, k) / 255)
			render.DrawQuadEasy(p, w.aim, sz, sz, color_white, 0)
			render.DrawQuadEasy(p, -w.aim, sz, sz, color_white, 0)
		end
	end
	for i = #cpParts, 1, -1 do
		local q = cpParts[i]
		local k = (now - q.t0) / q.life
		if k >= 1 then
			table.remove(cpParts, i)
		else
			local sz = CPD_BASE * curve5(CPD_SIZE, k) * M2U
			if sz > 1 then
				CPD:SetFloat("$refractamount", 0.3 * curve5(CPD_ALPHA, k) / 255)
				render.DrawQuadEasy(q.p + q.v * (now - q.t0), (EyePos() - q.p):GetNormalized(), sz, sz,
					color_white, q.rot + q.spin * (now - q.t0))
			end
		end
	end
end)

-- Critical Pain's antic (the game's video 1:54-1:55): writhing tendrils grow over him from the feet up into a cocoon
-- round his body, drawn back as it fires - 22, out of his legs, hips, spine, shoulders and arms, each to a point
-- round him (0.3-0.65 m off his surface), thin (0.25-0.5), curling (circle 0.3, waves)
local COCOON_J = {"Ankle_L", "Ankle_R", "Knee_L", "Knee_R", "Hip_L", "Hip_R", "Pelvis", "Spine_1", "Spine_2",
	"Spine_3", "Shoulder_L", "Shoulder_R", "Elbow_L", "Elbow_R", "Wrist_L", "Wrist_R"}
net.Receive("alex_mercer_tendril_cocoon", function()
	local m, t0, tRev = net.ReadEntity(), net.ReadFloat(), net.ReadFloat()
	if not IsValid(m) then return end
	for i = 1, 22 do
		local j = COCOON_J[(i - 1) % #COCOON_J + 1]
		local p = bonePos(m, j) or m:WorldSpaceCenter()
		local up = math.Clamp((p.z - m:GetPos().z) / 72, 0, 1)
		local dir = VectorRand()
		dir.z = dir.z * 0.6
		dir:Normalize()
		local b = p + dir * math.Rand(12, 26)
		local it = {0, math.Rand(0.25, 0.5), j, nil, 6, 20, 0.3, math.Rand(0, 360), math.Rand(30, 90), 10, {math.Rand(3, 7), 8, 0.3}}
		active[#active + 1] = {m = m, b = b, it = it, t1 = t0 + up * 1.0 + math.Rand(0, 0.15), tRev = tRev}
	end
end)

-- Critical Pain's beam (graph_devastator tendrilDevastator: tendrilCount 10 over attackTimeDuration 1.333 s): a stream
-- out of his wrists - a Critical Pain set's tendril every 0.1333 s through the attack - into the victim and on
-- through it (user: "into the victim, forward without stopping, a beam out of his hands"), else along the aim; each
-- grows at its 30-35 m/s up to 200 m (the world stops it), all drawn back at the item's end
net.Receive("alex_mercer_tendril_beam", function()
	local m, target, aim, t1, tRev = net.ReadEntity(), net.ReadEntity(), net.ReadVector(), net.ReadFloat(), net.ReadFloat()
	if not IsValid(m) then return end
	-- critical_pain/effects' distortionObject004 (2.333 s) in front of him
	local flat = Vector(aim.x, aim.y, 0)
	cpDist[#cpDist + 1] = {m = m, aim = flat:IsZero() and m:GetForward() or flat:GetNormalized(), t0 = t1, t1 = t1 + 2.333}
	timer.Simple(math.max(0, t1 - CurTime()), function() if IsValid(m) then ALEX_MERCER_CPWAVE(m, aim) end end)
	-- (the game's video 1:56-1:58: at the launch a cloud of dark smoke, black biomass and chunks)
	-- critical_pain/effects at the fire, out of Wrist_L (user 2026-10-22: "the effects that go with it"):
	-- debrisTransform001 twice (0-0.3333 s: speed x2, size x3; 0-1 s: rate x2, life x2, speed x5 +-3, size x5, green /
	-- blue x0.6), biasDebrisConcrete001 (0-0.3333 s: rate x2, speed x2 +-2, size x0.35 +-0.35) and debrisTransform002
	-- (0-0.1667 s: life x0.1, size x7 +-7 - a flash of huge biomass)
	timer.Simple(math.max(0, t1 - CurTime()), function()
		local V = ALEX_MERCER_VFX
		if not (IsValid(m) and V and V.Emit and V.EMITTERS) then return end
		local E = V.EMITTERS
		local h = bonePos(m, "Wrist_L") or m:WorldSpaceCenter()
		if E.debris then
			V.Emit(E.debris, h, aim, nil, 1, 15, {b = {speed = 2, speedVar = 1, size = 3, sizeVar = 0}})
			V.Emit(E.debris, h, aim, nil, 1, 30, {b = {life = 2, lifeVar = 2, speed = 5, speedVar = 3, size = 5, sizeVar = 0,
				g = 0.6, b = 0.6}})
		end
		if E.concrete then
			V.Emit(E.concrete, h, aim, nil, 1, 16, {b = {speed = 2, speedVar = 2, size = 0.35, sizeVar = 0.35}})
		end
		if E.charge then V.Emit(E.charge, h, aim, nil, 1, 3, {b = {life = 0.1, lifeVar = 0.1, size = 7, sizeVar = 7}}) end
	end)
	-- (the video: one thick, tight bundle with dark smoke along it) three per step, within +-4 deg, and smoke puffs
	-- along the line
	local n = 0
	for t = t1, tRev - 0.2, 0.1333 do
		for k3 = 1, 3 do
			n = n + 1
			local s = DEV.cp[(n - 1) % #DEV.cp + 1]
			timer.Simple(math.max(0, t - CurTime()) + math.Rand(0, 0.06), function()
				if not IsValid(m) then return end
				local o = bonePos(m, s[3]) or m:WorldSpaceCenter()
				local dir = aim
				if IsValid(target) then
					local tp = bonePos(target, "Spine_3") or target:WorldSpaceCenter()
					dir = (tp + VectorRand() * 3 - o):GetNormalized()
				end
				-- (user 2026-10-22: not fanning out) one tight bundle - a hair of spread only
				local ang = dir:Angle()
				ang = Angle(ang.p + math.Rand(-0.6, 0.6), ang.y + math.Rand(-0.6, 0.6), 0)
				local tr = util.TraceLine({start = o, endpos = o + ang:Forward() * 200 * M2U, filter = {m, target},
					mask = MASK_SOLID_BRUSHONLY})
				-- (straight out along the beam: no turn / curl off the wrist - user)
				local it = {0, s[2], s[3], nil, s[5], s[6], 0, 0, 0, s[10], s[11]}
				active[#active + 1] = {m = m, b = tr.HitPos, it = it, t1 = CurTime(), tRev = tRev}
				local V = ALEX_MERCER_VFX
				if V and V.Emit and V.EMITTERS and V.EMITTERS.land_smoke then
					local reach = math.min(o:Distance(tr.HitPos), 25 * M2U)
					local p = o + ang:Forward() * math.Rand(1.5 * M2U, reach)
					V.Emit(V.EMITTERS.land_smoke, p, -ang:Forward(), nil, 1.6, 1)
				end
			end)
		end
	end
end)

-- his set from t0 (the node's start); tRev: when they draw back on a body that never gets a ragdoll (TD.Retarget takes it off the others)
function TD.Start(m, pup, name, t0, tRev)
	local f = TD.FINISHERS[name]
	local set = f and SETS[f[1]]
	if not set then return end
	for _, it in ipairs(set) do
		active[#active + 1] = {m = m, pup = pup, it = it, t1 = t0 + f[2] + it[1], tRev = tRev, game = true}
	end
end
-- the body went over from its puppet to its pulled body (consumeBody): what holds the one holds the other, till its joints shrink or it is gone, no time to go back by
function TD.Retarget(pup, body)
	for _, x in ipairs(active) do
		if x.pup == pup then x.pup, x.tRev = body, nil end
	end
end

-- the curve (Hermite) from a to b: leaving a along d0 (|ma|), arriving along the line (|mb|)
local function curve(a, b, d0, ma, mb, s)
	local s2, s3 = s * s, s * s * s
	local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
	local f = b - a
	local fl = f:Length()
	if fl > 0 then f:Mul(1 / fl) end
	return a * h00 + d0 * (ma * h10) + b * h01 + f * (mb * h11)
end

-- (user: the devastators cost a lot of FPS) the bone matrices are the tendril's own, refilled every frame instead
-- of new ones (dst), the curve kept while its ends stay put, the arc-length look-up a binary search
local function frameMatrix(p, t, n, ws, ls, dst)
	local b = t:Cross(n)
	dst = dst or Matrix()
	dst:SetUnpacked(n.x * ws, b.x * ws, t.x * ls, p.x,
		n.y * ws, b.y * ws, t.y * ls, p.y,
		n.z * ws, b.z * ws, t.z * ls, p.z,
		0, 0, 0, 1)
	return dst
end

-- The game's tendril, as prototypeenginef.dll has it (AbstractTendrilAction: the update 0x10138520, the path 0x10135740, a point on it 0x10134c50, the wave 0x1008d450):
-- * the path, again each frame, from his joint a to its joint b: straight when neither rotation is set. Else it leaves a along (sin x sin z, -sin x cos z, cos x) in the frame right, up, toward b, on a circle of circleRadius on the
--   side toward b (the radius cut to the centre's distance if b is inside), round until it faces b, then straight to b, all at forwardVelocity;
-- * the chain: segmentCount points, a snake: the head at the time so far (at b once there, it waits there), each next a fixed step behind it (the path's length / the count), the root on a. So its links keep their length as it grows;
-- * from timeReverse on (s from its own start; none on the finishers' tendrilFromParent items) or when the target is gone, the path is left: each point runs at reverseVelocity after the next one toward the root, the last one into a and
--   gone. A tendrilFromParent with its target's joint shrinking (the body flowing into him) is gone at once: the update's check of the joint's scale, 0x10138541;
-- * the wave, on a copy of the points: up, square to the line a b, amplitude x smoothstep(da / (da + db) / rampUp) x smoothstep(db / (da + db) / rampDown) x sin(2 pi (da - speed t) / length), da db the point's distances to a and b in metres;
-- * the width: exactly the item's scale on the mesh (the shader's point0.w, point1.w = 0).
-- The shader lays each link on a Catmull-Rom through these; here each is a straight run between two bones (a 5-link set: two runs, its midpoint between).
local function gamePath(x, a, b)
	local it = x.it
	local P = x.path or {}
	x.path = P
	local to = b - a
	local dist = to:Length()
	local f = dist > 0.01 and to * (1 / dist) or Vector(1, 0, 0)
	local speed = it[5] * M2U
	P.a, P.b, P.f, P.speed = a, b, f, speed
	local n = math.max(it[10], 1)
	local zr, xr = math.rad(it[8]), math.rad(it[9])
	if math.abs(zr) < 1e-5 and math.abs(xr) < 1e-5 then
		P.Tarc, P.p0, P.dir, P.Tall, P.step = 0, a, f, dist / speed, dist / n / speed
		return P
	end
	local up = math.abs(f.z) > 0.999 and Vector(1, 0, 0) or Vector(0, 0, 1)
	local r = f:Cross(up)
	r:Normalize()
	local u = r:Cross(f)
	local sx, cx, sz, cz = math.sin(xr), math.cos(xr), math.sin(zr), math.cos(zr)
	local d0 = r * (sx * sz) + u * (-sx * cz) + f * cx
	d0:Normalize()
	local side = f - d0 * f:Dot(d0)
	if side:LengthSqr() < 1e-8 then side = r end
	side:Normalize()
	local R = math.max(it[7], 0.01) * M2U
	local Tu, Tw0 = to:Dot(d0), to:Dot(side)
	local D = math.sqrt(Tu * Tu + (Tw0 - R) * (Tw0 - R))
	for _ = 1, 5 do
		if D <= 0 or R <= D then break end
		R = D
		D = math.sqrt(Tu * Tu + (Tw0 - R) * (Tw0 - R))
	end
	local q = D > 0 and math.Clamp(R / D, 0, 1) or 1
	local th = (math.atan2(Tw0 - R, Tu) + math.asin(q)) % (2 * math.pi)
	local p0 = a + d0 * (R * math.sin(th)) + side * (R * (1 - math.cos(th)))
	local line = b - p0
	local ll = line:Length()
	P.d0, P.side, P.R, P.w = d0, side, R, speed / R
	P.Tarc, P.p0, P.dir = th / P.w, p0, ll > 0.01 and line * (1 / ll) or f
	P.Tall = P.Tarc + ll / speed
	-- (the step: the arc counted by the angle between its ends, as the engine does)
	P.step = (ll + R * math.min(th, 2 * math.pi - th)) / n / speed
	return P
end
local function gamePoint(P, t)
	if t < P.Tarc then
		local q = P.w * t
		return P.a + P.d0 * (P.R * math.sin(q)) + P.side * (P.R * (1 - math.cos(q)))
	end
	if t >= P.Tall then return P.b end
	return P.p0 + P.dir * ((t - P.Tarc) * P.speed)
end
local function smooth01(u)
	if u <= 0 then return 0 end
	if u >= 1 then return 1 end
	return (3 - 2 * u) * u * u
end
local function layoutGame(x, now)
	local it = x.it
	local a = bonePos(x.m, it[3])
	if not a then
		x.done = true
		return
	end
	local e, b = x.pup, nil
	if IsValid(e) then
		-- (the pulled body isn't drawn on its first frame, nor out of the view: its bones built first, once a frame by its own cache)
		if e.MercerBody then e:SetupBones() end
		local bi = e:LookupBone(it[4]) or (VB[it[4]] and e:LookupBone(VB[it[4]]))
		local bm = bi and e:GetBoneMatrix(bi)
		-- a tendrilFromParent (no timeReverse of its own; a `tendril`, the Hunter's, has no such check): against the joint's scale on this body, a scaled model's is no 1. 2 % under: what a frame's rounding doesn't reach
		if bm and not it[12] then
			local sc = bm:GetScale()
			local k = sc.x + sc.y + sc.z
			if x.sE ~= e then x.sE, x.s0 = e, k end
			if k < x.s0 * 0.98 then
				x.done = true
				return
			end
		end
		b = bm and bm:GetTranslation() or bonePos(e, it[4])
	end
	if b then
		x.lastB = b
	else
		x.back = x.back or now
		b = x.lastB
		if not b then
			x.done = true
			return
		end
	end
	local P = gamePath(x, a, b)
	local pos = x.pos or {}
	x.pos = pos
	if not x.back and ((x.tRev and now >= x.tRev) or (it[12] and now - x.t1 > it[12])) then x.back = now end
	if not x.back then
		local th = math.min(now - x.t1, P.Tall)
		local n = -1
		for i = 0, it[10] - 1 do
			local ti = th - i * P.step
			if ti <= 0 then break end
			pos[i] = gamePoint(P, ti)
			n = i
		end
		x.n = n
	else
		local dt = now - (x.lastT or now)
		local go = it[6] * M2U * dt
		local n = x.n or -1
		local i = 0
		while i <= n do
			local to = (i == n) and a or pos[i + 1]
			local d = to - pos[i]
			local l = d:Length()
			if go >= l then
				pos[i] = Vector(to)
				if i == n then n = n - 1 end
			else
				pos[i] = pos[i] + d * (go / l)
			end
			i = i + 1
		end
		x.n = n
	end
	x.lastT = now
	local n = x.n or -1
	if n < 0 then
		if x.back then x.done = true end
		return
	end
	-- the wave
	local chain = x.chain or {}
	x.chain = chain
	local wave = it[11]
	local f = P.f
	local w = Vector(-f.x * f.z, -f.y * f.z, 1 - f.z * f.z)
	if w:LengthSqr() < 1e-6 then w = Vector(1, 0, 0) end
	w:Normalize()
	local tau = now - x.t1
	for i = 0, n do
		local p = pos[i]
		if wave and wave[3] > 0 and wave[1] > 0 and wave[2] > 0 then
			local da, db = p:Distance(a) / M2U, p:Distance(b) / M2U
			local sum = math.max(da + db, 1e-4)
			local k = wave[3] * smooth01(da / sum / wave[4]) * smooth01(db / sum / wave[5])
			p = p + w * (k * M2U * math.sin(2 * math.pi * (da - wave[1] * tau) / wave[2]))
		end
		-- (root first: chain[0] = a, chain[m] the head)
		chain[n - i + 1] = p
	end
	chain[0] = a
	local m = n + 1
	-- (the set of 5 links, up to 53 cm each: the bones to spare on the midpoints of the shader's Catmull-Rom, 60 deg between straight links otherwise. The mesh repeats twice as often along it as the game's)
	if it[10] * 2 <= N then
		local c2 = x.chain2 or {}
		x.chain2 = c2
		for i = 0, m - 1 do
			c2[2 * i] = chain[i]
			c2[2 * i + 1] = (chain[i] + chain[i + 1]) * 0.5625 - (chain[math.max(i - 1, 0)] + chain[math.min(i + 2, m)]) * 0.0625
		end
		c2[2 * m] = chain[m]
		chain, m = c2, 2 * m
	end
	-- the bones along it
	local ws = it[2]
	local out = x.mats or {}
	x.mats = out
	local nrm = x.nrm or Vector(0, 1, 0)
	for i = 0, m do
		local p = chain[i]
		local t = chain[math.min(i + 1, m)] - chain[math.max(i - 1, 0)]
		if t:LengthSqr() < 1e-6 then t = Vector(f) end
		t:Normalize()
		-- (the shader's frame: across by the up vector; where it runs straight up, the last one turned on)
		local side = t:Cross(Vector(0, 0, 1))
		if side:LengthSqr() > 1e-3 then nrm = side else nrm = nrm - t * nrm:Dot(t) end
		if nrm:LengthSqr() < 1e-6 then nrm = t:Cross(Vector(1, 0, 0)) end
		nrm:Normalize()
		local l0 = i > 0 and chain[i]:Distance(chain[i - 1]) or 0
		local l1 = i < m and chain[i + 1]:Distance(chain[i]) or l0
		if i == 0 then l0 = l1 end
		out[i] = frameMatrix(p, t, nrm, ws, (l0 + l1) * 0.5 / S, out[i])
		if i == m then
			for j = m + 1, N do out[j] = frameMatrix(p, t, nrm, ws, j == N and ws or 0, out[j]) end
			out[N + 1] = frameMatrix(p + t * (SPIKE * S * ws), t, nrm, ws, ws, out[N + 1])
		end
	end
	x.nrm = nrm
	return out
end

-- the bone matrices of one tendril this frame (nil = nothing to draw)
local function layout(x, now)
	local it = x.it
	local a, b = bonePos(x.m, it[3]), x.b or bonePos(x.pup, it[4])
	if not a or not b then return end
	local cv = x.cv
	if not cv or cv.a:DistToSqr(a) > 0.25 or cv.b:DistToSqr(b) > 0.25 then
		local f = b - a
		local dist = f:Length()
		if dist < 1 then return end
		f:Mul(1 / dist)
		local up = math.abs(f.z) > 0.95 and Vector(1, 0, 0) or Vector(0, 0, 1)
		local r = f:Cross(up)
		r:Normalize()
		local u = r:Cross(f)
		local zr, xr = math.rad(it[8]), math.rad(it[9])
		local d0 = f * math.cos(xr) + (r * math.cos(zr) + u * math.sin(zr)) * math.sin(xr)
		-- out along d0, turning on a circle of circleRadius until it faces the target (xAxisRotation of turn), then on
		-- to it (a Hermite leaving along the turned direction); no circle at all when it leaves straight
		local R = it[7] * M2U
		local side = f - d0 * f:Dot(d0)
		if side:LengthSqr() < 1e-6 then side = r end
		side:Normalize()
		local K1 = (R > 0 and xr ~= 0) and 12 or 0
		local K2 = 14
		local pts = {[0] = a}
		for k = 1, K1 do
			local th = xr * k / K1
			pts[k] = a + d0 * (R * math.sin(th)) + side * (R * (1 - math.cos(th)))
		end
		local c0 = pts[K1]
		local dc = d0 * math.cos(xr) + side * math.sin(xr)
		local rest = b:Distance(c0)
		for k = 1, K2 do pts[K1 + k] = curve(c0, b, dc, rest, rest, k / K2) end
		local K = K1 + K2
		local acc = {0}
		for k = 1, K do acc[k + 1] = acc[k] + pts[k]:Distance(pts[k - 1]) end
		cv = {a = Vector(a), b = Vector(b), f = f, up = up, r = r, pts = pts, acc = acc, K = K}
		x.cv = cv
	end
	local pts, acc, K, f, up = cv.pts, cv.acc, cv.K, cv.f, cv.up
	local L = acc[K + 1]
	-- grown / drawn back
	local len = it[5] * M2U * (now - x.t1)
	if x.tRev and now > x.tRev then
		-- drawn back from the length it had then (not re-grown toward a body still about after the consume)
		x.lenRev = x.lenRev or math.min(it[5] * M2U * math.max(x.tRev - x.t1, 0), L)
		len = x.lenRev - (x.rev or it[6]) * M2U * (now - x.tRev)
	end
	len = math.Clamp(len, 0, L)
	if len < 1 then return end
	local function at(l)
		-- the curve point at arc length l: the first k with acc[k + 1] >= l (binary search)
		if l >= acc[K + 1] then return pts[K] end
		local lo, hi = 1, K
		while lo < hi do
			local mid = math.floor((lo + hi) / 2)
			if acc[mid + 1] >= l then hi = mid else lo = mid + 1 end
		end
		local seg = acc[lo + 1] - acc[lo]
		local w = seg > 0 and (l - acc[lo]) / seg or 0
		return LerpVector(w, pts[lo - 1], pts[lo])
	end
	local segs = math.min(it[10], N)
	local ws = it[2] * (x.sc or 1)
	local wave = it[11]
	local out = x.mats or {}
	x.mats = out
	local n = cv.r
	local seglen = len / segs
	for i = 0, segs do
		local l = i * seglen
		local p = at(l)
		local t = at(math.min(l + 2, len)) - at(math.max(l - 2, 0))
		if t:LengthSqr() < 1e-6 then t = Vector(f) end
		t:Normalize()
		-- parallel transport of the side axis
		n = n - t * n:Dot(t)
		if n:LengthSqr() < 1e-6 then n = t:Cross(up) end
		n:Normalize()
		if wave and i > 0 and i < segs then
			-- waveSpeed / waveLength (in segments) / waveAmplitude (m), ramped in and out along the tendril
			local ramp = math.sin(math.pi * i / segs)
			p = p + t:Cross(n) * (wave[3] * M2U * ramp * math.sin(2 * math.pi * (i / wave[2] - wave[1] * now / 10)))
		end
		out[i] = frameMatrix(p, t, n, ws, seglen / S, out[i])
		if i == segs then
			-- past its segmentCount the chain folds into the tip; the spike there at its own length x the scale
			for j = segs + 1, N do out[j] = frameMatrix(p, t, n, ws, j == N and ws or 0, out[j]) end
			out[N + 1] = frameMatrix(p + t * (SPIKE * S * ws), t, n, ws, ws, out[N + 1])
		end
	end
	return out
end

-- the Tendril Barrage's wetness (menu slider, 0 = leathery .. 100 = glassy): its own materials' gloss, reflection
-- and rim set live from the convar (user 2026-10-22: leathery, not glossy - a new convar at 0, the old one kept 30)
local WET = CreateClientConVar("alex_mercer_tendril_wet2", "0", true, false, "Tendril Barrage wetness 0-100", 0, 100)
local function applyWet()
	local k = math.Clamp(WET:GetFloat(), 0, 100) / 100
	for _, name in ipairs({"models/mercer/tendril_body_wet", "models/mercer/tendril_color_wet"}) do
		local m = Material(name)
		if m and not m:IsError() then
			-- 0 = leather: a dull broad reddish sheen, no reflection, no rim; up = whiter, tighter, glassy
			m:SetFloat("$phongboost", 0.25 + 5.75 * k)
			m:SetFloat("$phongexponent", 6 + 64 * k)
			m:SetVector("$envmaptint", Vector(0.35, 0.12, 0.12) * (k * k))
			m:SetFloat("$rimlightboost", 1.6 * k)
			m:SetVector("$phongtint", LerpVector(k, Vector(1, 0.25, 0.2), Vector(1, 0.45, 0.45)))
			m:SetVector("$phongfresnelranges", LerpVector(k, Vector(0.6, 0.8, 1), Vector(0.5, 0.8, 1)))
			if m.Recompute then m:Recompute() end
		end
	end
end
cvars.AddChangeCallback("alex_mercer_tendril_wet2", applyWet, "AlexMercerWet")
hook.Add("InitPostEntity", "AlexMercerWet", applyWet)
applyWet()

local pool, wpool, gpool = {}, {}, {}
local function modelFor(i, wet, game)
	local P = wet and wpool or game and gpool or pool
	local e = P[i]
	if IsValid(e) then return e end
	e = ClientsideModel(MDL, RENDERGROUP_OPAQUE)
	if not IsValid(e) then return end
	e:SetNoDraw(true)
	if game then
		for k, mat in ipairs(e:GetMaterials()) do
			if mat:find("tendril_body", 1, true) then e:SetSubMaterial(k - 1, "models/mercer/tendril_body_hc") end
		end
	end
	if wet then
		applyWet()
		-- the barrage's own wet materials (tendril_*_wet.vmt); the consume's stay as they are
		for k, mat in ipairs(e:GetMaterials()) do
			if mat:find("tendril_body", 1, true) then e:SetSubMaterial(k - 1, "models/mercer/tendril_body_wet")
			elseif mat:find("tendril_color", 1, true) then e:SetSubMaterial(k - 1, "models/mercer/tendril_color_wet") end
		end
	end
	e.MercerBones = {}
	for k = 0, N do e.MercerBones[k] = e:LookupBone("seg" .. k) end
	e.MercerBones[N + 1] = e:LookupBone("tip")
	e:AddCallback("BuildBonePositions", function(ent)
		local L = ent.MercerLayout
		if not L then return end
		for k = 0, N + 1 do
			local bi, mt = ent.MercerBones[k], L[k]
			if bi and mt then ent:SetBoneMatrix(bi, mt) end
		end
	end)
	P[i] = e
	return e
end

hook.Add("PostDrawOpaqueRenderables", "AlexMercerTendrils", function(depth, sky)
	if depth or sky or #active == 0 then return end
	local now = CurTime()
	local used, wused, gused = 0, 0, 0
	for i = #active, 1, -1 do
		local x = active[i]
		local L, over
		if x.game then
			L = now >= x.t1 and IsValid(x.m) and layoutGame(x, now)
			over = x.done or not IsValid(x.m) or now - x.t1 > 20
		else
			L = (now >= x.t1) and IsValid(x.m) and not (x.tRev and now > x.tRev + 2) and layout(x, now)
			over = now >= x.t1 and not L and (not IsValid(x.m) or (x.tRev and now > x.tRev) or now - x.t1 > 10) or (x.tRev and now > x.tRev + 2)
		end
		if over then
			table.remove(active, i)
		elseif L then
			local e
			if x.wet then
				wused = wused + 1
				e = modelFor(wused, true)
			elseif x.game then
				gused = gused + 1
				e = modelFor(gused, false, true)
			else
				used = used + 1
				e = modelFor(used)
			end
			if e then
				e.MercerLayout = L
				e:SetPos(L[0]:GetTranslation())
				e:SetRenderBounds(Vector(-200, -200, -200), Vector(200, 200, 200))
				e:InvalidateBoneCache()
				e:SetupBones()
				e:DrawModel()
			end
		end
	end
end)
-