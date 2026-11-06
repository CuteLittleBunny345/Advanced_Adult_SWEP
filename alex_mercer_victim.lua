- The grabbed human moves like the game's receiver (prototype holding/grabbing/human receiver: grappleLocoSteer with
-- the _rcv anims alongside his _gv ones; the consume finishers' receiver tracks). The _rcv anims are on the game's
-- skeleton: models/mercer/alex_mercer_rcv.mdl (tools/build_rcv.py) stores each frame relative to the giver's
-- Character_Root with the game's grab-slot attachment (R_Wrist_Grapple -> the victim's Motion_Root) baked in. Every
-- frame a hidden puppet of it is put at Mercer's rendered Character_Root, plays the _rcv of his current _gv at the same
-- frame, and the NPC's ValveBiped bones follow it: the torso / neck / head by their turn from the rest pose, the limbs
-- aimed along the puppet's (the two rest poses differ: the game's arms hang ~60 deg lower), the NPC's own bone lengths
-- kept, its neck put on the puppet's (in his hand). Server: NW2 entity MercerVictim on the Mercer.

-- (user 2026-10-30: the stealth consume's victim stood crooked) _v2: the stealth consumes' receivers on his joint every
-- frame as their graph attaches them (tools/build_rcv.py ATTACH); the rest as before - a new name, no restart
local RCV_MDL = "models/mercer/alex_mercer_rcv_v2.mdl"
local BLEND = 0.1 -- the receiver tracks' blend in (s)

local TORSO = {
	{"ValveBiped.Bip01_Pelvis", "Pelvis"},
	{"ValveBiped.Bip01_Spine", "Spine_1"},
	{"ValveBiped.Bip01_Spine1", "Spine_2"},
	{"ValveBiped.Bip01_Spine2", "Spine_3"},
	{"ValveBiped.Bip01_Spine4", "Spine_3"},
	{"ValveBiped.Bip01_Neck1", "Neck"},
	{"ValveBiped.Bip01_Head1", "Head"},
}
-- {NPC bone, NPC child (its direction), puppet joint, puppet child}
local LIMBS = {}
for _, s in ipairs({"L", "R"}) do
	local function v(n) return "ValveBiped.Bip01_" .. s .. "_" .. n end
	for _, l in ipairs({
		{v("Clavicle"), v("UpperArm"), "Clavicle_" .. s, "Shoulder_" .. s},
		{v("UpperArm"), v("Forearm"), "Shoulder_" .. s, "Elbow_" .. s},
		{v("Forearm"), v("Hand"), "Elbow_" .. s, "Wrist_" .. s},
		{v("Hand"), v("Finger2"), "Wrist_" .. s, "Middle_Base_" .. s},
		{v("Thigh"), v("Calf"), "Hip_" .. s, "Knee_" .. s},
		{v("Calf"), v("Foot"), "Knee_" .. s, "Ankle_" .. s},
		{v("Foot"), v("Toe0"), "Ankle_" .. s, "Ball_" .. s},
	}) do LIMBS[#LIMBS + 1] = l end
end

local function rotOnly(m)
	local r = Matrix(m)
	r:SetTranslation(vector_origin)
	return r
end

-- the rotation taking unit vector a onto b (Rodrigues)
local function rotBetween(a, b)
	local k = a:Cross(b)
	local s, c = k:Length(), a:Dot(b)
	if s < 1e-5 then return Matrix() end
	k:Mul(1 / s)
	local x, y, z, t = k.x, k.y, k.z, 1 - c
	return Matrix({
		{c + x * x * t, x * y * t - z * s, x * z * t + y * s, 0},
		{y * x * t + z * s, c + y * y * t, y * z * t - x * s, 0},
		{z * x * t - y * s, z * y * t + x * s, c + z * z * t, 0},
		{0, 0, 0, 1}})
end

-- rest poses (model space, at the origin facing +X): the puppet's "reference" and the NPC model's ragdoll /
-- reference pose
local restCache = {}
local function restOf(mdl, seqNames)
	if restCache[mdl] ~= nil then return restCache[mdl] end
	local e = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
	if not IsValid(e) then restCache[mdl] = false return false end
	e:SetNoDraw(true)
	e:SetPos(vector_origin)
	e:SetAngles(angle_zero)
	local sq = -1
	for _, n in ipairs(seqNames) do
		sq = e:LookupSequence(n)
		if sq and sq >= 0 then break end
	end
	e:ResetSequence(math.max(sq or 0, 0))
	e:SetCycle(0)
	e:InvalidateBoneCache()
	e:SetupBones()
	local r = {byName = {}}
	for i = 0, e:GetBoneCount() - 1 do
		local m = e:GetBoneMatrix(i)
		if m then r.byName[e:GetBoneName(i)] = Matrix(m) end
	end
	e:Remove()
	restCache[mdl] = r
	return r
end

-- the _rcv for his current _gv (the claws' stance holds with the plain one)
local RCV_OF = {alex_claw_grap_hmn_amb_gv = "alex_grap_hmn_amb_rcv"}
-- the stealth consumes' receivers by their finisher name: {sequence, its first cycle} (the shiv plays from frame 17)
local STEALTH_RCV = {break_neck = {"alex_stealth_consumes_break_neck_rcv", 0},
	rip_jugular = {"alex_stealth_consumes_rip_jugular_002_rcv", 0},
	guillotine = {"alex_stealth_consumes_guillotine_002_rcv", 0},
	full_nelson = {"alex_stealth_consumes_full_nelson_002_rcv", 0},
	shiv = {"alex_grap_stealth_shiv_rcv", 17 / 138}, bearhug = {"alex_stealth_consumes_bearhug_002_rcv", 0}}
local function rcvFor(pup, name)
	name = string.lower(name or "")
	-- (the wall run with a human: his *_split, its *_rcv - graph_wall wall_run/loco/pose/human)
	local r = RCV_OF[name] or (string.find(name, "_gv$") and string.sub(name, 1, -4) .. "_rcv")
		or (string.find(name, "_split$") and string.sub(name, 1, -7) .. "_rcv") or name .. "_rcv"
	local sq = pup:LookupSequence(r)
	if sq and sq >= 0 then return sq end
end

local function puppetFor(m)
	local p = m.MercerRcvPuppet
	-- (user 2026-10-30: "the fixes didn't help") a puppet made before RCV_MDL changed kept the old model through the
	-- script's refresh: made anew on the current one
	if IsValid(p) and p:GetModel() == RCV_MDL then return p end
	if IsValid(p) then p:Remove() end
	p = ClientsideModel(RCV_MDL, RENDERGROUP_OPAQUE)
	if not IsValid(p) then return end
	p:SetNoDraw(true)
	m.MercerRcvPuppet = p
	m:CallOnRemove("MercerRcvPuppet", function() if IsValid(p) then p:Remove() end end)
	return p
end

-- the puppet's pose this frame: {joint name -> world matrix}; false when there is nothing to follow
local function puppetPose(m, st)
	local p = puppetFor(m)
	if not p then return false end
	-- his bones with his render matrix off (whether the engine puts it on the bones or not), then the matrix once by
	-- hand: on the wall he is drawn through it (user: the body was thrown off behind him)
	local on = m.MercerMatrixOn
	if on then m:DisableMatrix("RenderMultiply") m:InvalidateBoneCache() end
	m:SetupBones()
	local cr = m:LookupBone("Character_Root")
	local crm = cr and m:GetBoneMatrix(cr)
	local rm = m.MercerRenderMatrix and m:MercerRenderMatrix()
	if on then
		m:EnableMatrix("RenderMultiply", rm or Matrix())
		m:InvalidateBoneCache()
	end
	if not crm then return false end
	crm = Matrix(crm)
	if rm then
		local W = m:GetWorldTransformMatrix()
		crm = W * rm * W:GetInverseTR() * crm
	end
	local seq = m:GetSequence()
	local sq = rcvFor(p, m:GetSequenceName(seq))
	local cyc
	if sq then
		-- frame for frame with his anim (a few pairs differ in length: the receiver holds its last frame)
		local gf = m:GetCycle() * m:SequenceDuration(seq)
		local rd = p:SequenceDuration(sq)
		cyc = rd > 0 and math.Clamp(gf / rd, 0, 1) or 0
		if p:GetSequenceInfo(sq) and bit.band(p:GetSequenceInfo(sq).flags or 0, 1) ~= 0 then
			cyc = m:GetCycle() % 1 -- the looped loco pairs: one cycle each
		end
		st.sq, st.cyc = sq, cyc
		-- the finisher's clock and place, for when he leaves it (its opening) before the body is in him
		local now = CurTime()
		if st.gfT and st.gf and now - st.gfT > 0 and now - st.gfT < 0.2 then
			st.gfRate = math.Clamp(Lerp(0.3, st.gfRate or 1, (gf - st.gf) / (now - st.gfT)), 0, 3)
		end
		st.gf, st.gfT, st.rd = gf, now, rd
		st.crm = Matrix(crm)
		st.crmZ = m:GetPos().z
	elseif st.consuming and st.sq then
		-- (user 2026-10-08: he runs off at the finisher's opening, the body flowing into him on the way) the body stays
		-- where it was and its receiver anim plays on at its own pace; with none left, its last frame
		sq = st.sq
		if st.gf and st.gfT and st.rd and st.rd > 0 then
			cyc = math.Clamp((st.gf + (CurTime() - st.gfT) * (st.gfRate or 1)) / st.rd, 0, 1)
		else
			cyc = st.cyc
		end
		if st.crm then crm = st.crm end
	elseif STEALTH_RCV[m:GetNW2String("MercerConsumeName", "")] and not st.sq
		and m:GetNW2Float("MercerConsumeT", 0) >= (st.since or 0) - 0.5 then
		-- (user 2026-10-30: the stealth victim turned to face him) the stealth consume starts with the hold: his finisher
		-- anim comes a tick after the body - meanwhile its own first frame, not the held stand's (hung facing him)
		local r = STEALTH_RCV[m:GetNW2String("MercerConsumeName", "")]
		sq, cyc = p:LookupSequence(r[1]), r[2]
	else
		-- no receiver anim for this one (an air pose ...): the held stand's (a frozen run pose looked like the body
		-- flying on by inertia - user)
		sq, cyc = p:LookupSequence("alex_grap_hmn_amb_rcv"), (CurTime() / 1.5) % 1
	end
	if not sq or sq < 0 then return false end
	if st.lastSq ~= sq then
		st.lastSq = sq
		st.blend0 = CurTime()
	end
	p:SetPos(crm:GetTranslation())
	p:SetAngles(crm:GetAngles())
	if p:GetSequence() ~= sq then p:ResetSequence(sq) end
	p:SetPlaybackRate(0)
	p:SetCycle(cyc)
	p:InvalidateBoneCache()
	p:SetupBones()
	local pose = {}
	for i = 0, p:GetBoneCount() - 1 do
		local bm = p:GetBoneMatrix(i)
		if bm then pose[p:GetBoneName(i)] = bm end
	end
	return pose
end

-- the NPC's mapped bones from the puppet: {bone index -> world matrix}
-- ground: nil = the victim (its neck put on the puppet's, in his hand); a Vector = the disguise (the pelvis at the
-- source's height above that ground scaled to the model's own legs, the feet on the floor)
-- (user 2026-10-29, the Prototype NPC pack) a victim on the game's own rig (its joints named as the puppet's): each
-- joint takes the puppet's turn as it is, down its own hierarchy with its own bone lengths - no ValveBiped mapping
local function nativeRig(npc)
	return npc:LookupBone("Pelvis") ~= nil and npc:LookupBone("R_Wrist_Grapple") ~= nil
end
-- (user 2026-10-29: "he lies crooked in the hands") the root chain's offsets are animated (a held body hangs off its
-- root): those joints stand where the anim puts them, the rest hang on their parents with the NPC's own lengths; in his
-- hand the whole body is then moved so its neck is the puppet's (in his hand), as the ValveBiped path does
local ANIMATED = {Motion_Root = true, Balance_Root = true, Character_Root = true, Pelvis = true}
local function retargetNative(npc, pose, nr, ground)
	local out = {}
	for i = 0, npc:GetBoneCount() - 1 do
		local n = npc:GetBoneName(i)
		local pm = pose[n]
		if pm then
			local m = Matrix(pm)
			local pb = npc:GetBoneParent(i)
			local pn = pb and pb >= 0 and npc:GetBoneName(pb)
			if not ANIMATED[n] and pn and out[pb] and nr.byName[pn] and nr.byName[n] then
				local loc = nr.byName[pn]:GetInverseTR() * nr.byName[n]
				m:SetTranslation(out[pb] * loc:GetTranslation())
			end
			out[i] = m
		end
	end
	local nk, pn = npc:LookupBone("Neck"), pose.Neck
	if not ground and nk and out[nk] and pn then
		local off = pn:GetTranslation() - out[nk]:GetTranslation()
		for _, m in pairs(out) do m:SetTranslation(m:GetTranslation() + off) end
	end
	return out
end

local function retarget(npc, pose, pr, nr, ground, up)
	if nativeRig(npc) then return retargetNative(npc, pose, nr, ground) end
	local out, byName = {}, {}
	local function idx(n) return npc:LookupBone(n) end
	-- the torso: the puppet joint's turn from its rest, applied to the NPC bone's rest
	local rot = {}
	for _, t in ipairs(TORSO) do
		local pm, prest, nrest = pose[t[2]], pr.byName[t[2]], nr.byName[t[1]]
		if pm and prest and nrest then
			rot[t[1]] = rotOnly(pm) * rotOnly(prest):GetInverseTR() * rotOnly(nrest)
		end
	end
	-- the limbs: the parent's turn, then aimed along the puppet's segment
	local function parentName(n)
		local b = idx(n)
		local pb = b and npc:GetBoneParent(b)
		return pb and pb >= 0 and npc:GetBoneName(pb) or nil
	end
	for _, l in ipairs(LIMBS) do
		local nrest, crest = nr.byName[l[1]], nr.byName[l[2]]
		local a, b = pose[l[3]], pose[l[4]]
		local par = parentName(l[1])
		local prot, prest = par and rot[par], par and nr.byName[par]
		if nrest and crest and a and b and prot and prest then
			local dp = prot * rotOnly(prest):GetInverseTR()
			local r1 = dp * rotOnly(nrest)
			local d0 = dp * (crest:GetTranslation() - nrest:GetTranslation())
			local d = b:GetTranslation() - a:GetTranslation()
			if d0:LengthSqr() > 1e-6 and d:LengthSqr() > 1e-6 then
				d0:Normalize()
				d:Normalize()
				rot[l[1]] = rotBetween(d0, d) * r1
			else
				rot[l[1]] = r1
			end
		end
	end
	-- positions down the NPC's own hierarchy (its bone lengths), the pelvis at the puppet's
	local pel = pose.Pelvis
	if not pel then return nil end
	local pelPos = pel:GetTranslation()
	if ground then
		local pp, np = pr.byName.Pelvis, nr.byName["ValveBiped.Bip01_Pelvis"]
		local k = (pp and np and pp:GetTranslation().z > 1) and np:GetTranslation().z / pp:GetTranslation().z or 1
		-- (its height over his feet scaled to its own legs - along his up, which the wall run turns onto the wall:
		-- world z there threw the disguise off behind him, user)
		up = up or Vector(0, 0, 1)
		local h = (pelPos - ground):Dot(up)
		pelPos = pelPos + up * (h * (k - 1))
	end
	for i = 0, npc:GetBoneCount() - 1 do
		local n = npc:GetBoneName(i)
		local r = rot[n]
		if r then
			local m = Matrix(r)
			local pb = npc:GetBoneParent(i)
			local pn = pb and pb >= 0 and npc:GetBoneName(pb)
			if pn and byName[pn] and nr.byName[pn] and nr.byName[n] then
				local loc = nr.byName[pn]:GetInverseTR() * nr.byName[n]
				m:SetTranslation(byName[pn] * loc:GetTranslation())
			else
				m:SetTranslation(pelPos)
			end
			byName[n] = m
			out[i] = m
		end
	end
	-- the neck in his hand: the whole body moved onto the puppet's neck
	local nk, pn = byName["ValveBiped.Bip01_Neck1"], pose.Neck
	if nk and pn and not ground then
		local off = pn:GetTranslation() - nk:GetTranslation()
		for _, m in pairs(out) do m:SetTranslation(m:GetTranslation() + off) end
	end
	return out
end

-- the NPC's bones: the mapped ones from the puppet (blended in on a change of anim), the rest kept on their parents
local LETGO_BLEND = 0.25
local function buildBones(npc, nb)
	-- (let go) from his hand's pose to its own: the bones the engine just built for it, lerped from the held ones
	local lg = npc.MercerLetGo
	if lg then
		local k = (CurTime() - lg.t) / LETGO_BLEND
		if k >= 1 then
			npc.MercerLetGo = nil
		else
			for i, fm in pairs(lg.T) do
				local m = npc:GetBoneMatrix(i)
				if m then
					local b = Matrix()
					b:SetAngles(LerpAngle(k, fm:GetAngles(), m:GetAngles()))
					b:SetTranslation(LerpVector(k, fm:GetTranslation(), m:GetTranslation()))
					pcall(npc.SetBoneMatrix, npc, i, b)
				end
			end
			return
		end
	end
	local T = npc.MercerVictimT
	if not T or CurTime() - (npc.MercerVictimTT or 0) > 0.25 then return end
	local old, new = {}, {}
	for i = 0, (nb or npc:GetBoneCount()) - 1 do
		local m = npc:GetBoneMatrix(i)
		if m then
			old[i] = Matrix(m)
			local t = T[i]
			if not t then
				local pb = npc:GetBoneParent(i)
				if pb and pb >= 0 and new[pb] and old[pb] then t = new[pb] * old[pb]:GetInverseTR() * old[i] end
			end
			if t then
				new[i] = t
				pcall(npc.SetBoneMatrix, npc, i, t)
			end
		end
	end
end

-- The consume as the game's receiver nodes (prototype_consume grapple/<power>/<finisher>/receiver), seconds from the
-- node's start: ec = effectConsume (the consume biomass growing over the body), dir = its directional wave (spawn
-- 116-118 on the receiver), cyc = receiver/cyclic (spawn 112: its spawner fires two directional waves at random, over
-- and over, until it is gone), giver = giver/cyclic on his Spine_3 (the receiver's grabbedExecuteUsingParent 109),
-- cbp = consumeByParent {time, consumeUpwards, boneSweepConstant (signed, as the graph has it), consumableProperties}:
-- the body flows into his Spine_3 (see consumeBody)
local CONS = {
	chest_punch = {ec = 0.6667, dir = {"transform_chest_out", 0.7333}, cyc = 1, giver = 1.833, cbp = {1.833, true, 4}},
	head_stomp = {ec = 0.6667, dir = {"transform_head_to_toe", 1}, cyc = 1.267, giver = 1.167, cbp = {1.833, false, -5}},
	knee_head = {ec = 0.6667, dir = {"transform_head_to_toe", 0.4667}, cyc = 0.8333, giver = 1.5, cbp = {1.333, true, -4}},
	smash_throw = {ec = 0.9, dir = {"transform_head_to_toe", 0.8}, cyc = 1, giver = 1.167, cbp = {1.333, false, -1}},
	beatdown = {ec = 2.933, dir = {"transform_head_to_toe", 3}, cyc = 3.067, giver = 2.933, cbp = {3.833, true, -4, "fast"}},
	-- (user 2026-10-08: the consume must go into him gradually everywhere) the finishers without consumeByParent end
	-- in consumeMe (with their gibs): the same consume from its time, lowest first (the graph's usual -4)
	foot_sweep = {ec = 0.4, giver = 1.333, cbp = {1.5, true, -4}},
	crush_head = {ec = 2, dir = {"transform_head_to_toe", 2.167}, cyc = 1.833, giver = 4.333, cbp = {2.5, true, -4}},
	headsmush = {ec = 2, dir = {"transform_head_to_toe", 1.867}, cyc = 2.033, giver = 2.567, cbp = {2.133, false, -4}},
	headdrop = {ec = 2.4, dir = {"transform_head_to_toe", 2.667}, cyc = 1.567, giver = 2.867, cbp = {1.933, false, 2}},
	heart_to_head = {ec = 1.333, dir = {"transform_chest_out", 0.7333}, cyc = 1, giver = 1.333, cbp = {1.5, true, -4}},
	arm_rip = {ec = 0.8, giver = 1.2, cbp = {0.8333, true, -4}},
	lash = {ec = 1.4, dir = {"transform_chest_out", 1.4}, cyc = 1.7, giver = 2, cbp = {1.4, false, 2}},
	come_here = {ec = 1.4, giver = 1.667, cbp = {1.267, true, -4}},
	readjust = {ec = 1, dir = {"transform_head_to_toe", 1.533}, cyc = 2, giver = 1.4, cbp = {1.167, false, -4}},
	readjust_b = {ec = 0.8, giver = 2.5, cbp = {0.8, true, -4}},
	spin_and_slice = {ec = 0.6667, giver = 0.8333, cbp = {1.333, true, -4}},
	-- (user: the air slam with a body - no finisher, the body consumed as he lands) straight into the pull
	air_slam = {ec = 0, giver = 0, cbp = {0, true, -4}},
	-- (user 2026-10-30: the stealth consumes - prototype special_actions/stealthConsume, their receiver nodes) ec =
	-- effectConsume, dir = the receiver's head_to_toe execute, giver from the effectConsume; at its death the body into him.
	-- (user 2026-10-30: "the stealth consumes must be instant - in the game they go into Mercer at once, sucked straight
	-- in") the graph has no consumeByParent for them (the shared node's consume {Temporary} stealthy at 0 s, the
	-- disguise's transform complete at 2.333 s, the receiver's death): instant = no powered body, every joint swept into
	-- his chest in that many seconds, 40 m/s up the body - all of it in him ~0.25 s after the death (was the -4 m/s
	-- consumeMe swirl, 1 s a joint)
	break_neck = {ec = 1.5, dir = {"transform_head_to_toe", 1.667}, giver = 1.5, cbp = {2.367, true, -40}, instant = 0.2},
	rip_jugular = {ec = 1, dir = {"transform_head_to_toe", 1.167}, giver = 1, cbp = {2.367, true, -40}, instant = 0.2},
	guillotine = {ec = 1.533, dir = {"transform_head_to_toe", 1.667}, giver = 1.533, cbp = {2.5, true, -40}, instant = 0.2},
	full_nelson = {ec = 1.667, dir = {"transform_head_to_toe", 1.833}, giver = 1.667, cbp = {2.5, true, -40}, instant = 0.2},
	shiv = {ec = 2.1, dir = {"transform_head_to_toe", 2.267}, giver = 2.1, cbp = {3.633, true, -40}, instant = 0.2},
	bearhug = {ec = 1.333, dir = {"transform_head_to_toe", 1.333}, giver = 1.333, cbp = {3, true, -40}, instant = 0.2},
}
local RCV_WAVES = {"rcv_chest_down", "rcv_chest_up", "rcv_l_arm_down", "rcv_r_arm_down", "rcv_l_arm_up", "rcv_r_arm_up",
	"rcv_l_leg_up", "rcv_r_leg_up", "rcv_l_leg_down", "rcv_r_leg_down"}
local WAVE_T = 0.6667 -- a directional wave's length (its last item ends then)
local EC_GROW = 0.6 -- effectConsume growthThreshold (s)
-- a joint's way into him: (user 2026-10-08: in the game the arms and legs wind round his torso and vanish into it in
-- about a second - ours flew straight in in 0.25 s) in to his torso's girth, one and a half turns round it while
-- shrinking, then in
local SWEEP_T = 1
local SWIRL_TURNS, TORSO_R = 1.5, 12
local M2U = 39.37

-- the consume biomass over the victim: the game's consume map, alpha-tested at a falling threshold
local function veinsMat(name, ref)
	return CreateMaterial(name, "VertexLitGeneric", {
		["$basetexture"] = "alex_mercer/fx/consume_veins", ["$bumpmap"] = "alex_mercer/fx/consume_veins_n",
		["$basetexturetransform"] = "center 0 0 scale 2.5 2.5 rotate 0 translate 0 0",
		["$bumptransform"] = "center 0 0 scale 2.5 2.5 rotate 0 translate 0 0", ["$alphatest"] = "1",
		["$alphatestreference"] = ref, ["$allowalphatocoverage"] = "1", ["$phong"] = "1", ["$phongexponent"] = "18",
		["$phongboost"] = "3", ["$phongfresnelranges"] = "[0.3 0.7 1]", ["$color2"] = "[0.85 0.62 0.58]"})
end
local VMAT = veinsMat("alex_mercer_victim_veins", "0.8")
local function veinsPass(ent, flags, k)
	VMAT:SetFloat("$alphatestreference", Lerp(k, 0.8, 0.005))
	render.MaterialOverride(VMAT)
	render.DepthRange(0, 0.99995)
	ent:DrawModel(flags)
	render.DepthRange(0, 1)
	render.MaterialOverride()
end

-- consumeByParent as the engine does it (prototypeenginef.dll ConsumableBehaviour: BeginConsumeByParent 0x1007d770,
-- start 0x1007dc10, update 0x1007c8b0, next batch 0x1007bc10, take 0x10019439): the body goes ragdoll
-- (switchToRagdollMode); every physics bone is tied to his destination joint (Spine_3 + parentPositionOffset) by a
-- distance limit of maxConstraintDistance; the bones are sorted by key = (up ? 1 : -1) * height - boneSweepConstant *
-- (horizontal distance from the body's axis)^2 (metres, ascending) and taken in batches (keys within 0.05 of the
-- batch's first): a taken bone's limit starts at its distance and shrinks at the absorb speed (initialAbsorbSpeed,
-- after delayBeforeAcceleration + absorbAcceleration a second up to maxAbsorbSpeed) down to 1 cm (+1 mm per arrival),
-- the bone then shrinks at jointScaleRate a second (its non-physics children with it) to 0.01; the next batch starts
-- when the whole batch has arrived (the first after constraintDelay). Taking a bone removes its ragdoll joints to the
-- bones already taken: the body comes apart, each piece pulled in with the parts not yet taken hanging on it.
-- (user: "как в игре") GMod cannot break a ragdoll's own joints - every try with its ragdoll fought itself (the spin,
-- the shrinking in place) - so the body is simulated here, position-based: each physics bone a rigid tetrahedron of
-- particles (its origin + AX along its three axes), a ragdoll joint = the child's origin held on a point of the
-- parent's (a ball joint), gravity, the world as collision; drawn on a clientside model of the NPC.
-- startup_tod.p3d proto::ConsumableProperties: Default (every finisher but the beatdown, whose item names Fast)
local PROPS = {
	default = {speed0 = 0, accel = 0.7, maxSpeed = 4, accelDelay = 0.25, scaleRate = 1.5, maxDist = 2.5, delay = 0},
	fast = {speed0 = 3.2, accel = 4, maxSpeed = 8, accelDelay = 0, scaleRate = 2.5, maxDist = 2.5, delay = 0},
}
-- (user: the body went in too late - the consume sounds were long over) the graphs play their "consume" cue 0.03 -
-- 1.4 s after the pull starts, the Default set took 2 - 3 s: the whole pull at 3x the time (speeds x3, acceleration
-- x9, its delay / 3, the bones' shrink x3)
local PULL_K = 3
-- (user 2026-10-29: "the NPC stretches like chewing gum") the engine breaks a taken bone's joints to the bones already
-- taken, so the body comes apart and each piece flies in on its own - on a Source mesh (vertices weighted between two
-- bones) the skin between a piece at his chest and the next one on its way draws out into a long band. Off by
-- default: the joints stay whole, the body is pulled in as one, bone by bone in the engine's order; the bones still
-- shrink into him as they arrive. alex_mercer_consume_tear 1 = the engine's tearing
local TearCvar = CreateClientConVar("alex_mercer_consume_tear", "0", true, false,
	"Alex Mercer consume: 1 = the body comes apart as it is pulled in (the engine's way), 0 = pulled in whole")
-- (a player 2026-10-30: "the consumed NPCs go limp and stretch - in the game they flail as if falling") in the game the
-- body goes into him as a POWERED ragdoll: the held human's ragdoll is powered by its puppet from the grab on
-- (prototype holding/grabbing/human receiver and the human's reaction/grab on_grab: powerRagdollByPuppet), the
-- consume's start only switches the ragdoll off (consume/consume: stop_ragdoll = disableRagdoll), consumeByParent
-- switches it on again (prototypeenginef.dll 0x1007d770: RagdollSetEnabledMessage) and nothing on the way unpowers it
-- (unpowerRagdoll is a track of its own - the air grind's receiver calls it after its ragdoll/enable): the joints'
-- motors keep driving the body to the puppet's pose - the receiver's _rcv played on, its last frame held - while the
-- bones are pulled in. The motors: startup_tod.p3d ravenphysics::PoweredConstraintSharedProperties
-- DefaultPoweredRagdollProperties {angularVelocity 20, maxForce 50}; ConsumableProperties (Default and Fast)
-- angularDampingY 0.3, angularDampingXZ 0. alex_mercer_consume_active 0 = the body as it was (limp)
local ActiveCvar = CreateClientConVar("alex_mercer_consume_active", "1", true, false,
	"Alex Mercer consume: 1 = the body flails into him as the game's powered ragdoll, 0 = the old limp body")
local MOTOR_W = 20 -- rad/s, a motor's top speed
local MOTOR_TQ = 50 * M2U * M2U -- its top torque, 50 N m in kg u^2 / s^2 (the bones' masses: the NPC's own ragdoll)
local DAMP_Y = 0.3 -- 1/s, about the up axis
local ITER = 8 -- constraint passes a frame
local AX = 6 -- u, a bone's particles off its origin
local BODIES = {}
-- the game's joints (the effect programs' names) -> the NPC's ValveBiped bones (TORSO / LIMBS above)
local JOINT_MAP = {Pelvis = "ValveBiped.Bip01_Pelvis", Spine_1 = "ValveBiped.Bip01_Spine",
	Spine_2 = "ValveBiped.Bip01_Spine1", Spine_3 = "ValveBiped.Bip01_Spine2", Neck = "ValveBiped.Bip01_Neck1",
	Head = "ValveBiped.Bip01_Head1"}
for _, s in ipairs({"L", "R"}) do
	for g, n in pairs({Clavicle = "Clavicle", Shoulder = "UpperArm", Elbow = "Forearm", Forarm = "Forearm",
		Wrist = "Hand", Middle_Base = "Finger2", Hip = "Thigh", Knee = "Calf", Ankle = "Foot", Ball = "Toe0"}) do
		JOINT_MAP[g .. "_" .. s] = "ValveBiped.Bip01_" .. s .. "_" .. n
	end
end

-- the physics bones of a model (read off a throwaway clientside ragdoll), cached; with each one's mass for the powered
-- body's motors: massCache[mdl][bone] = {m kg, c its centre (bone space), Icm kg u^2} - its hull's box as a uniform
-- block, turned about its long side
local physCache, massCache = {}, {}
local function physBones(mdl)
	if physCache[mdl] ~= nil then return physCache[mdl] end
	local list, mass = false, {}
	if util.IsValidRagdoll(mdl) then
		local r = ClientsideRagdoll(mdl)
		if IsValid(r) then
			-- (user: a T-posed body flashed up after the consume) never drawn
			r:SetNoDraw(true)
			for i = 0, r:GetPhysicsObjectCount() - 1 do
				local b = r:TranslatePhysBoneToBone(i)
				if b and b >= 0 then
					list = list or {}
					list[#list + 1] = b
					local po = r:GetPhysicsObjectNum(i)
					local ok, lo, hi = pcall(function() return po:GetAABB() end)
					if ok and lo and hi and IsValid(po) then
						local m, sz = po:GetMass(), hi - lo
						local L = math.max(sz.x, sz.y, sz.z)
						mass[b] = {m = m, c = (lo + hi) * 0.5, Icm = m * L * L / 12}
					end
				end
			end
			r:Remove()
		end
	end
	physCache[mdl], massCache[mdl] = list, mass
	return list
end

-- a bone's matrix from its particles (origin, the forward one, the right one)
local function frameOf(o, a, s)
	local f = a - o
	f:Normalize()
	local r = s - o
	r = r - f * r:Dot(f)
	r:Normalize()
	local m = Matrix()
	m:SetForward(f)
	m:SetRight(r)
	m:SetUp(r:Cross(f))
	m:SetTranslation(o)
	return m
end

local function centroid(e)
	return (e.p[1].x + e.p[2].x + e.p[3].x + e.p[4].x) * 0.25
end

local function bodyBones(ent, nb)
	local Bd = ent.MercerBody
	if not Bd then return end
	local new = {}
	for b = 0, (nb or ent:GetBoneCount()) - 1 do
		local e, nm = Bd.bone[b], nil
		if e then
			nm = frameOf(e.p[1].x, e.p[2].x, e.p[3].x)
			if e.scale < 1 then nm:Scale(Vector(e.scale, e.scale, e.scale)) end
		else
			local par = ent:GetBoneParent(b)
			if par and par >= 0 and new[par] and Bd.rel[b] then
				nm = new[par] * Bd.rel[b]
			elseif Bd.rootRel[b] then
				local r = Bd.bone[Bd.root]
				nm = frameOf(r.p[1].x, r.p[2].x, r.p[3].x) * Bd.rootRel[b]
			end
		end
		if nm then
			new[b] = nm
			-- (players: "SetBoneMatrix: Bone is unwriteable" x500) a bone a lower LOD leaves out can't be written: skip
			-- it, don't let it break off the rest of the pose
			pcall(ent.SetBoneMatrix, ent, b, nm)
		end
	end
end

local function bodyDraw(self, flags)
	-- (user: a T-posed body flashed up for an instant) drawn only once the simulation has put its bones, never after
	-- the last one is in him
	local Bd = self.MercerBody
	if not Bd or not Bd.ready or Bd.over then return end
	self:DrawModel(flags)
	veinsPass(self, flags, 1)
end

-- the body from the NPC as drawn this frame (T: its mapped bones; lastT / dtv: the frame before, for its speed; st: the
-- receiver puppet's state, its clock for the powered body)
local function consumeBody(m, v, cb, T, lastT, dtv, st)
	local mdl = v:GetModel()
	local pbs = mdl and physBones(mdl)
	if not pbs then return nil end
	local ent = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
	if not IsValid(ent) then return nil end
	ent:DrawShadow(false) -- (players 2026-10-28: the consumed body's shadow stayed under it)
	ent:SetSkin(v:GetSkin() or 0)
	for _, b in ipairs(v:GetBodyGroups() or {}) do ent:SetBodygroup(b.id, v:GetBodygroup(b.id)) end
	ent:SetMaterial(v:GetMaterial())
	ent:SetColor(v:GetColor())
	-- the whole pose as drawn: the mapped bones, the rest on their parents (buildBones)
	v.MercerVictimT, v.MercerVictimTT = T, CurTime()
	v:InvalidateBoneCache()
	v:SetupBones()
	local M0 = {}
	for b = 0, v:GetBoneCount() - 1 do
		local mt = v:GetBoneMatrix(b)
		if mt then M0[b] = Matrix(mt) end
	end
	local isPhys = {}
	for _, b in ipairs(pbs) do isPhys[b] = true end
	local function physParent(b)
		local p = v:GetBoneParent(b)
		while p and p >= 0 do
			if isPhys[p] then return p end
			p = v:GetBoneParent(p)
		end
	end
	local pel = v:LookupBone("ValveBiped.Bip01_Pelvis") or v:LookupBone("Pelvis")
	local ref = pel and M0[pel] and M0[pel]:GetTranslation() or v:WorldSpaceCenter()
	local P0 = PROPS[cb[4] or "default"]
	local P = {}
	for k, x in pairs(P0) do P[k] = x end
	P.speed0, P.maxSpeed, P.scaleRate = P0.speed0 * PULL_K, P0.maxSpeed * PULL_K, P0.scaleRate * PULL_K
	P.accel, P.accelDelay = P0.accel * PULL_K * PULL_K, P0.accelDelay / PULL_K
	local sgn, C = cb[2] and 1 or -1, cb[3]
	local Bd = {ent = ent, m = m, v = v, P = P, E = {}, order = {}, bone = {}, rel = {}, rootRel = {}, pts = {},
		sticks = {}, joints = {}, speed = P.speed0, accT = P.accelDelay, timer = math.max(P.delay, 0), thr = 0.01, cur = 1,
		t0 = CurTime()}
	local function pt(pos, vel, owner)
		local q = {x = Vector(pos), v = Vector(vel), owner = owner}
		Bd.pts[#Bd.pts + 1] = q
		return q
	end
	local function stick(a, b)
		Bd.sticks[#Bd.sticks + 1] = {a, b, a.x:Distance(b.x)}
	end
	for _, b in ipairs(pbs) do
		local mt = M0[b]
		if mt then
			local o = mt:GetTranslation()
			local vel = Vector(0, 0, 0)
			local tm, lm = T[b], lastT and lastT[b]
			if tm and lm and dtv and dtv > 0.001 then
				vel = (tm:GetTranslation() - lm:GetTranslation()) / dtv
				if vel:Length() > 600 then vel = vel:GetNormalized() * 600 end
			end
			local d = (o - ref) / M2U
			-- (m / c / Icm: the powered body's; a bone with no hull to go by as a 5 kg rod 2 AX long)
			local mi = massCache[mdl] and massCache[mdl][b]
			local e = {b = b, state = 0, scale = 1, len = P.maxDist, key = sgn * d.z - C * (d.x * d.x + d.y * d.y),
				m = mi and mi.m or 5, c = mi and mi.c or Vector(AX, 0, 0), Icm = mi and mi.Icm or 5 * AX * AX / 3}
			e.p = {pt(o, vel, e), pt(o + mt:GetForward() * AX, vel, e), pt(o + mt:GetRight() * AX, vel, e),
				pt(o + mt:GetUp() * AX, vel, e)}
			e.all = {e.p[1], e.p[2], e.p[3], e.p[4]}
			for i = 1, 3 do
				for j = i + 1, 4 do stick(e.p[i], e.p[j]) end
			end
			Bd.bone[b] = e
			Bd.E[#Bd.E + 1] = e
			Bd.order[#Bd.order + 1] = e
		end
	end
	if #Bd.E == 0 then ent:Remove() return nil end
	-- the ragdoll's joints: the child's origin on a point of the parent's (rigid in the parent)
	for _, e in ipairs(Bd.E) do
		local pp = physParent(e.b)
		local pe = pp and Bd.bone[pp]
		if pe then
			local j = pt(e.p[1].x, e.p[1].v, pe)
			for i = 1, 4 do stick(j, pe.p[i]) end
			pe.all[#pe.all + 1] = j
			Bd.joints[#Bd.joints + 1] = {j, e.p[1], a = pe, c = e}
			-- (the powered body: each bone's joint to its parent, its children)
			e.pj = Bd.joints[#Bd.joints]
			pe.kids = pe.kids or {}
			pe.kids[#pe.kids + 1] = e
		else
			Bd.root = Bd.root or e.b
		end
	end
	Bd.root = Bd.root or Bd.E[1].b
	-- the non-physics bones ride their parents as posed
	for b = 0, v:GetBoneCount() - 1 do
		if not isPhys[b] and M0[b] then
			local par = v:GetBoneParent(b)
			if par and par >= 0 and M0[par] then
				Bd.rel[b] = M0[par]:GetInverseTR() * M0[b]
			else
				Bd.rootRel[b] = M0[Bd.root]:GetInverseTR() * M0[b]
			end
		end
	end
	table.sort(Bd.order, function(a, b) return a.key < b.key end)
	local sb = m:LookupBone("Spine_3")
	local sm = sb and m:GetBoneMatrix(sb)
	Bd.target = sm and sm:GetTranslation() or v:WorldSpaceCenter()
	Bd.lastTarget = Bd.target
	ent.MercerBody = Bd
	ent:SetPos(ref)
	ent:SetRenderBounds(Vector(-160, -160, -160), Vector(160, 160, 160))
	-- (its shadow is drawn apart from RenderOverride: none, so no T-posed shadow either)
	ent:DrawShadow(false)
	-- (always the full model: the far LODs drop bones the simulation writes)
	ent:SetLOD(0)
	ent:AddCallback("BuildBonePositions", bodyBones)
	ent.RenderOverride = bodyDraw
	-- (user: particles on the body while it is consumed) the receiver's spawner (spawn 112: two directional waves at
	-- random, again as they end) goes on on it until it is gone; the game's joints onto the NPC skeleton
	-- (a body on the game's own rig - the NPC pack - has the joints by name)
	if ent:LookupBone("ValveBiped.Bip01_Pelvis") then ent.MercerJointMap = JOINT_MAP end
	Bd.nextWave = CurTime()
	-- (the powered body) the pose its motors drive it to, on a puppet of its own: the finisher's _rcv on from this frame
	-- at its pace (puppetPose's clock - he may leave the finisher before the body is in), its last frame held; with no
	-- receiver anim, the pose the held puppet has now
	if ActiveCvar:GetBool() then
		Bd.active = true
		local hp, pq = m.MercerRcvPuppet, nil
		if st and st.sq and st.gf and st.gfT and st.rd and st.rd > 0 then
			pq = {sq = st.sq, gf = st.gf, gfT = st.gfT, rate = st.gfRate or 1, rd = st.rd}
		elseif IsValid(hp) then
			pq = {sq = hp:GetSequence(), cyc = hp:GetCycle()}
		end
		local p = pq and ClientsideModel(RCV_MDL, RENDERGROUP_OPAQUE)
		if IsValid(p) then
			p:SetNoDraw(true)
			p:SetPos(ref)
			Bd.pup, Bd.pq = p, pq
		end
	end
	BODIES[#BODIES + 1] = Bd
	return ent
end

-- the next batch: from the cursor, the bones whose keys are within 0.05 of the first; taking one breaks its joints to
-- the ones already taken
local function nextBatch(Bd)
	local k0
	while Bd.cur <= #Bd.order do
		local e = Bd.order[Bd.cur]
		if e.state == 0 then
			if k0 and e.key - k0 > 0.05 then break end
			k0 = k0 or e.key
			local dist = centroid(e):Distance(Bd.target) / M2U
			e.len = math.min(math.max(dist - 0.001, 0.001), Bd.P.maxDist) + 1e-5
			e.state = 1
			if TearCvar:GetBool() then
				for _, J in ipairs(Bd.joints) do
					if not J.broken and ((J.a == e and J.c.state > 0) or (J.c == e and J.a.state > 0)) then J.broken = true end
				end
			end
		end
		Bd.cur = Bd.cur + 1
	end
end

-- the powered body (alex_mercer_consume_active): the puppet's pose this frame on the body's own bones - the motors'
-- targets
local function bodyTarget(Bd)
	local p, pq = Bd.pup, Bd.pq
	if not IsValid(p) or not pq or not pq.sq or pq.sq < 0 then return nil end
	local cyc = pq.cyc or 0
	if pq.rd then cyc = math.Clamp((pq.gf + (CurTime() - pq.gfT) * pq.rate) / pq.rd, 0, 1) end
	if p:GetSequence() ~= pq.sq then p:ResetSequence(pq.sq) end
	p:SetPlaybackRate(0)
	p:SetCycle(cyc)
	p:InvalidateBoneCache()
	p:SetupBones()
	local pose = {}
	for i = 0, p:GetBoneCount() - 1 do
		local bm = p:GetBoneMatrix(i)
		if bm then pose[p:GetBoneName(i)] = bm end
	end
	local pr = restOf(RCV_MDL, {"reference"})
	local nr = restOf(Bd.ent:GetModel(), {"ragdoll", "reference"})
	return pr and nr and retarget(Bd.ent, pose, pr, nr) or nil
end

-- a bone's turn from its particles; its angular velocity from theirs (rigid: v_i - v_o = w x r_i with r_i its three
-- axes AX long, so the sum of r_i x (v_i - v_o) = 2 AX^2 w); a change of angular velocity about a point onto them
local function rotOf(e)
	local m = frameOf(e.p[1].x, e.p[2].x, e.p[3].x)
	m:SetTranslation(vector_origin)
	return m
end
local function angVel(e)
	local o, w = e.p[1], Vector(0, 0, 0)
	for i = 2, 4 do w:Add((e.p[i].x - o.x):Cross(e.p[i].v - o.v)) end
	w:Mul(1 / (2 * AX * AX))
	return w
end
local function spinBy(e, w, piv)
	for _, q in ipairs(e.all) do q.v:Add(w:Cross(q.x - piv)) end
end

-- a bone and the free ones below it (not those he has taken: the pull moves them)
local function limbOf(e, out)
	out = out or {}
	out[#out + 1] = e
	for _, k in ipairs(e.kids or {}) do
		if k.state == 0 then limbOf(k, out) end
	end
	return out
end

-- the motors, a powered constraint on each joint (root first): the child's turn in its parent driven to the puppet's -
-- the relative angular velocity that closes the gap this step, at most MOTOR_W, given to the child with the limb below
-- it (an arm turned at the shoulder carries the hand) with at most MOTOR_TQ of torque on that limb's inertia about the
-- joint; then the angular damping about the up axis. Bones already in him are left out. (The parent's side is not
-- turned back: offline that reaction made the joints of this solver buzz frame to frame)
local function motors(Bd, dt)
	local T = bodyTarget(Bd)
	if not T then return end
	local R = {}
	for _, e in ipairs(Bd.E) do
		if e.state < 2 then R[e] = rotOf(e) end
	end
	for _, J in ipairs(Bd.joints) do
		local P, C = J.a, J.c
		local tp, tc = T[P.b], T[C.b]
		if not J.broken and R[P] and R[C] and tp and tc then
			-- the turn from the child's now to the target's (the target's child-in-parent on the parent as it is now)
			local E = R[P] * (rotOnly(tp):GetInverseTR() * rotOnly(tc)) * R[C]:GetInverseTR()
			local x = (E:GetField(3, 2) - E:GetField(2, 3)) * 0.5
			local y = (E:GetField(1, 3) - E:GetField(3, 1)) * 0.5
			local z = (E:GetField(2, 1) - E:GetField(1, 2)) * 0.5
			local s = math.sqrt(x * x + y * y + z * z)
			local c = (E:GetField(1, 1) + E:GetField(2, 2) + E:GetField(3, 3) - 1) * 0.5
			-- (half a turn off: no axis to go by this step)
			if not (s < 0.02 and c < 0) then
				local th = math.atan2(s, c)
				local want = s > 1e-6 and Vector(x, y, z) * (math.min(th / dt, MOTOR_W) / s) or Vector(0, 0, 0)
				local dw = want - (angVel(C) - angVel(P))
				local piv = C.p[1].x
				local L, I = limbOf(C), 0
				for _, b in ipairs(L) do
					I = I + b.Icm + b.m * (frameOf(b.p[1].x, b.p[2].x, b.p[3].x) * b.c - piv):LengthSqr()
				end
				local cap = MOTOR_TQ * dt / math.max(I, 1)
				local l = dw:Length()
				if l > cap then dw:Mul(cap / l) end
				for _, b in ipairs(L) do spinBy(b, dw, piv) end
			end
		end
	end
	local k = 1 - 1 / (1 + DAMP_Y * dt)
	for e in pairs(R) do
		local wz = angVel(e).z
		if wz ~= 0 then spinBy(e, Vector(0, 0, -wz * k), centroid(e)) end
	end
end

-- (the powered body) who gives way at a joint - (parent, child) shares of the correction: the bone being pulled leads
-- and the rest of the body hangs on it; one in him holds the rest; one in him whose parent is taken rides that
-- parent's joint in (the engine tears that joint instead: on a Source mesh the skin between then drew out "like
-- chewing gum" - user 2026-10-29)
local function jointW(J)
	local P, C = J.a, J.c
	if C.ride then return 0, 1 end
	local pt, ct = P.state >= 1, C.state >= 1
	if pt ~= ct then
		if pt then return 0, 1 end
		return 1, 0
	end
	if pt and (P.state >= 2) ~= (C.state >= 2) then
		if P.state >= 2 then return 0, 1 end
		return 1, 0
	end
	return 0.5, 0.5
end

local function bodyStep(Bd, dt)
	local P = Bd.P
	dt = math.min(dt, 1 / 30)
	if IsValid(Bd.m) then
		local sb = Bd.m:LookupBone("Spine_3")
		local sm = sb and Bd.m:GetBoneMatrix(sb)
		if sm then Bd.target = sm:GetTranslation() end
	end
	if IsValid(Bd.v) then Bd.ent:SetColor(Bd.v:GetColor()) end
	-- the engine's update: the limits, the arrivals, the shrinking, the batches, the absorb speed
	local any, pulling, done = false, 0, 0
	for _, e in ipairs(Bd.E) do
		if e.state == 1 then
			any = true
			local l = e.len - Bd.speed * dt
			if l < Bd.thr then
				l = Bd.thr
				Bd.thr = Bd.thr + 0.001
				e.state = 2
			else
				pulling = pulling + 1
			end
			e.len = l
		elseif e.state == 2 then
			e.scale = e.scale - P.scaleRate * dt
			if e.scale <= 0.01 then
				e.scale = 0.01
				e.state = 3
			end
		end
		if e.state == 3 then done = done + 1 end
	end
	if Bd.timer > -1e-5 then
		Bd.timer = Bd.timer - dt
		if Bd.timer <= 0 then
			Bd.timer = -1
			nextBatch(Bd)
		end
	elseif any and pulling == 0 then
		nextBatch(Bd)
	end
	Bd.accT = Bd.accT - dt
	if Bd.accT <= 0 then
		Bd.speed = math.min(P.maxSpeed, Bd.speed + P.accel * dt)
		Bd.accT = -1
	end
	-- (the powered body) the motors; which bones in him ride their taken parents
	if Bd.active then
		if Bd.pup then motors(Bd, dt) end
		for _, e in ipairs(Bd.E) do
			local J = e.pj
			e.ride = e.state >= 2 and J and not J.broken and J.a.state >= 1 or nil
		end
	end
	-- the body: gravity, then the bones' rigidity, the joints still whole and the limits, then the world
	local g = GetConVarNumber("sv_gravity")
	for _, q in ipairs(Bd.pts) do
		q.v.z = q.v.z - g * dt
		q.x0 = Vector(q.x)
		q.x = q.x + q.v * dt
	end
	for _ = 1, ITER do
		for _, s in ipairs(Bd.sticks) do
			local a, b = s[1], s[2]
			local d = b.x - a.x
			local l = d:Length()
			if l > 1e-4 then
				d:Mul((l - s[3]) / l * 0.5)
				a.x = a.x + d
				b.x = b.x - d
			end
		end
		if Bd.active then
			-- (the powered body: no joint pulled apart between a bone on its way and one in him - player: "stretches")
			for _, J in ipairs(Bd.joints) do
				if not J.broken then
					local wp, wc = jointW(J)
					-- (an arrived parent shrinks into him: its joint points with it)
					local jp, Pa = J[1].x, J.a
					if Pa.scale < 1 then jp = LerpVector(Pa.scale, Pa.p[1].x, jp) end
					local d = J[2].x - jp
					if wp > 0 then J[1].x = J[1].x + d * wp end
					if wc > 0 then J[2].x = J[2].x - d * wc end
				end
			end
		else
			for _, J in ipairs(Bd.joints) do
				if not J.broken then
					local mid = (J[1].x + J[2].x) * 0.5
					J[1].x, J[2].x = mid, Vector(mid)
				end
			end
		end
		for _, e in ipairs(Bd.E) do
			local d = centroid(e) - Bd.target
			local dist, L = d:Length(), e.len * M2U
			-- (a bone riding its parent in has no limit of its own)
			if dist > L and not e.ride then
				d:Mul(L / dist - 1)
				for _, q in ipairs(e.all) do q.x = q.x + d end
			end
		end
	end
	-- (user 2026-10-29: "no collisions on the body while it is sucked in") the world stops it only until the pull has
	-- taken its first bone; from then on it flows into him through anything
	local solid = Bd.cur <= 1
	for _, q in ipairs(Bd.pts) do
		if solid and q.owner.state < 2 then
			local tr = util.TraceLine({start = q.x0, endpos = q.x, mask = MASK_SOLID_BRUSHONLY})
			if tr.Hit and not tr.StartSolid then q.x = tr.HitPos + tr.HitNormal * 0.5 end
		end
		q.v = (q.x - q.x0) / dt
	end
	local ent = Bd.ent
	ent:SetPos(centroid(Bd.bone[Bd.root]))
	ent:InvalidateBoneCache()
	Bd.ready = true
	local V = ALEX_MERCER_VFX
	if V and V.RunProg and CurTime() >= Bd.nextWave then
		Bd.nextWave = CurTime() + WAVE_T
		local a = math.random(#RCV_WAVES)
		local b = (a + math.random(#RCV_WAVES - 1) - 1) % #RCV_WAVES + 1
		V.RunProg(ent, RCV_WAVES[a], CurTime())
		V.RunProg(ent, RCV_WAVES[b], CurTime())
	end
	return done >= #Bd.E
end

hook.Add("Think", "AlexMercerConsumeRags", function()
	local dt = FrameTime()
	if dt <= 0 then return end
	for i = #BODIES, 1, -1 do
		local Bd = BODIES[i]
		if not IsValid(Bd.ent) or bodyStep(Bd, dt) or CurTime() - Bd.t0 > 15 then
			Bd.over = true
			if IsValid(Bd.ent) then
				Bd.ent:SetNoDraw(true)
				Bd.ent:Remove()
			end
			if IsValid(Bd.pup) then Bd.pup:Remove() end
			table.remove(BODIES, i)
		end
	end
end)

local function victimDraw(self, flags)
	if self.MercerConsumeRag then return end
	if self.MercerVictimGone and CurTime() - (self.MercerVictimTT or 0) < 0.25 then return end
	self:DrawModel(flags)
	local k = self.MercerVeinsK
	if k and k > 0 and CurTime() - (self.MercerVictimTT or 0) < 0.25 then veinsPass(self, flags, k) end
end

-- the consume's timeline for this frame: effects started, the biomass level, the bones' way into him
local function consumeStep(m, v, st, T)
	local name, t0 = m:GetNW2String("MercerConsumeName", ""), m:GetNW2Float("MercerConsumeT", 0)
	local c = CONS[name]
	-- (the last consume's name stays set: only one begun while holding this body counts; the stealth consume begins
	-- with the hold itself - the client sees the body a moment after: 0.5 s of slack)
	if not c or t0 <= 0 or t0 < (st.since or 0) - 0.5 then
		v.MercerVeinsK, v.MercerVictimGone, st.consuming = nil, nil, nil
		return
	end
	st.consuming = true
	local now = CurTime()
	local t = now - t0
	local pup = m.MercerRcvPuppet
	if st.consT ~= t0 then
		-- a new consume: the one-off programs at their times
		st.consT, st.nextWave, st.sweep, st.rag = t0, t0 + (c.cyc or 99), nil, nil
		local V = ALEX_MERCER_VFX
		if V and V.RunProg then
			if c.dir and IsValid(pup) then V.RunProg(pup, c.dir[1], t0 + c.dir[2]) end
			local stop = t0 + (c.cbp and c.cbp[1] + 1 or c.giver + 1.2)
			V.RunProg(m, "consume_giver", t0 + c.giver, math.max(stop, t0 + c.giver + 0.5))
		end
		-- his tendrils (tendrils_from_parent): on the puppet, then on the pulled body, TD.Retarget. (The time: only a body with no ragdoll: the sweep's end)
		if ALEX_MERCER_TENDRILS and IsValid(pup) then
			ALEX_MERCER_TENDRILS.Start(m, pup, name, t0, t0 + (c.cbp and c.cbp[1] + SWEEP_T or c.ec + 1.5))
		end
	end
	-- the receiver's spawner: two waves at random, again as they end, until it is consumed / dead
	local stopCyc = c.cbp and c.cbp[1] + 0.3 or c.ec + 1.5
	if c.cyc and not st.rag and t < stopCyc and now >= st.nextWave and IsValid(pup) and ALEX_MERCER_VFX and ALEX_MERCER_VFX.RunProg then
		st.nextWave = now + WAVE_T
		local a = math.random(#RCV_WAVES)
		local b = (a + math.random(#RCV_WAVES - 1) - 1) % #RCV_WAVES + 1
		ALEX_MERCER_VFX.RunProg(pup, RCV_WAVES[a], now)
		ALEX_MERCER_VFX.RunProg(pup, RCV_WAVES[b], now)
	end
	v.MercerVeinsK = math.Clamp((t - c.ec) / EC_GROW, 0, 1)
	-- consumeByParent: the engine's pull on the body (consumeBody); a model without a ragdoll: each joint (lowest first when
	-- consumeUpwards) swirled into his Spine_3 at |boneSweepConstant| m/s
	local cb = c.cbp
	if not cb or t < cb[1] or not T then
		st.lastT, st.lastTT = T, now
		return
	end
	if st.rag == nil then
		-- (c.instant, the stealth consumes: no powered body - the sweep below takes it in at once)
		st.rag = not c.instant and consumeBody(m, v, cb, T, st.lastT, now - (st.lastTT or now), st) or false
		v.MercerConsumeRag = st.rag or nil
		-- (the puppet's waves under way / still to come - the directional one - go on on the ragdoll)
		if st.rag and IsValid(pup) and ALEX_MERCER_VFX and ALEX_MERCER_VFX.MoveRuns then
			ALEX_MERCER_VFX.MoveRuns(pup, st.rag)
		end
		if st.rag and IsValid(pup) and ALEX_MERCER_TENDRILS and ALEX_MERCER_TENDRILS.Retarget then
			ALEX_MERCER_TENDRILS.Retarget(pup, st.rag)
		end
	end
	if st.rag then
		v.MercerVictimGone = true
		return
	end
	local sb = m:LookupBone("Spine_3")
	local sm = sb and m:GetBoneMatrix(sb)
	if not sm then return end
	local chest = sm:GetTranslation()
	if not st.sweep then
		local lo, hi = math.huge, -math.huge
		for _, mt in pairs(T) do
			local z = mt:GetTranslation().z
			lo, hi = math.min(lo, z), math.max(hi, z)
		end
		st.sweep = {lo = lo, hi = hi, speed = math.abs(cb[3]) * M2U, spin = math.random(2) == 1 and 1 or -1, rel0 = {}}
	end
	local sw = st.sweep
	local ts = t - cb[1]
	local all = true
	for i, mt in pairs(T) do
		local z = mt:GetTranslation().z
		local delay = (cb[2] and (z - sw.lo) or (sw.hi - z)) / math.max(sw.speed, 1)
		local p = math.Clamp((ts - delay) / (c.instant or SWEEP_T), 0, 1)
		if p < 1 then all = false end
		if p > 0 then
			-- (the joint's start, kept relative to his chest as he moves)
			local rel = sw.rel0[i]
			if not rel then
				rel = mt:GetTranslation() - chest
				sw.rel0[i] = rel
			end
			local h = Vector(rel.x, rel.y, 0)
			local r0 = h:Length()
			local dir = r0 > 1 and h / r0 or m:GetForward()
			dir:Rotate(Angle(0, sw.spin * SWIRL_TURNS * 360 * p, 0))
			local e = 1 - (1 - p) * (1 - p)
			local r = p < 0.7 and Lerp(math.min(1, e / 0.91), r0, TORSO_R) or Lerp((p - 0.7) / 0.3, TORSO_R, 0)
			local nm = Matrix(mt)
			nm:SetTranslation(chest + dir * r + Vector(0, 0, rel.z * (1 - e)))
			local s = 1 - p * p * p
			nm:Scale(Vector(s, s, s))
			T[i] = nm
		end
	end
	v.MercerVictimGone = all or nil
end

-- (user 2026-11-05: "видишь он там не на земле стоит, там кстати помимо нашего пака все так стоят, выше пола") tools/build_rcv.py bakes a finisher's receiver where the body hung in
-- his hand, and the body is then put by its neck: the feet stay wherever that leaves them, up to 10 u over the floor on the game's own proportions, more on another addon's. In the
-- game the slot lets go and it stands on the ground. So, from the finisher's start: the body's own lowest joints on the floor under it, as high over it as the receiver's feet are over
-- their lowest in this finisher (his lifts stay). FOOT_LOW: that lowest of each finisher up to its consumeByParent, the rest's height off, u (the floor at the entity's feet: the
-- receiver's _rcv on his _gv, tools/victimfeet.py). The puppet goes with it: the tendrils and the waves stay on the body
local FOOT_LOW = {arm_rip = -4.9, bearhug = -1.0, beatdown = -2.1, break_neck = -0.4, chest_punch = 8.9, come_here = 10.1, crush_head = -0.4, foot_sweep = -1.4, full_nelson = -0.7,
	guillotine = -0.9, head_stomp = 5.9, headdrop = -1.6, headsmush = -2.5, heart_to_head = -0.5, knee_head = 0.4, lash = -0.6, readjust = -0.3, readjust_b = 0, rip_jugular = -0.9, shiv = -1.0,
	smash_throw = -2.8, spin_and_slice = -10.4}
-- BY EYE: from his hand to the ground in this long; no floor this near his feet: he is in the air or on something the trace doesn't see, as the anim has it; a foot joint's height over its sole
local FEET_EASE, FEET_NEAR, SOLE_MAX = 0.3, 24, 12
local FEET_NAMES = {"Ball_L", "Ball_R", "ValveBiped.Bip01_L_Toe0", "ValveBiped.Bip01_R_Toe0", "ValveBiped.Bip01_L_Foot", "ValveBiped.Bip01_R_Foot"}
-- the body's feet among the bones it is posed by: {bone, its height over its sole}; by name, or (a rig of other names) the lowest ones of its rest
local feetCache = {}
local function feetOf(v, T, nr)
	local mdl = v:GetModel()
	local f = feetCache[mdl]
	if f then return f end
	f = {}
	local function add(b, r)
		f[#f + 1] = {b, math.Clamp(r:GetTranslation().z, 0, SOLE_MAX)}
	end
	for _, n in ipairs(FEET_NAMES) do
		local b, r = v:LookupBone(n), nr.byName[n]
		if b and r and T[b] then add(b, r) end
	end
	if #f == 0 then
		local lo = math.huge
		for b in pairs(T) do
			local r = nr.byName[v:GetBoneName(b)]
			if r and not ANIMATED[v:GetBoneName(b)] then lo = math.min(lo, r:GetTranslation().z) end
		end
		for b in pairs(T) do
			local r = nr.byName[v:GetBoneName(b)]
			if r and not ANIMATED[v:GetBoneName(b)] and r:GetTranslation().z <= lo + 4 then add(b, r) end
		end
	end
	feetCache[mdl] = f
	return f
end
local function feetOnGround(m, v, st, T, pose, pr, nr)
	local name, t0 = m:GetNW2String("MercerConsumeName", ""), m:GetNW2Float("MercerConsumeT", 0)
	local low = FOOT_LOW[name]
	-- (the last consume's name stays set: only one begun while holding this body, as consumeStep)
	if not low or t0 <= 0 or t0 < (st.since or 0) - 0.5 then return end
	local bl, br, rb, pel = pose.Ball_L, pose.Ball_R, pr.byName.Ball_L, pose.Pelvis
	if not (bl and br and rb and pel) then return end
	local lo = math.huge
	for _, f in ipairs(feetOf(v, T, nr)) do
		local mt = T[f[1]]
		if mt then lo = math.min(lo, mt:GetTranslation().z - f[2]) end
	end
	if lo == math.huge then return end
	local at = pel:GetTranslation()
	local tr = util.TraceLine({start = at, endpos = at - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY})
	local base = st.crmZ or m:GetPos().z
	if not tr.Hit or tr.StartSolid or math.abs(tr.HitPos.z - base) > FEET_NEAR then return end
	local lift = math.min(bl:GetTranslation().z, br:GetTranslation().z) - rb:GetTranslation().z - base - low
	local w = math.Clamp((CurTime() - t0) / FEET_EASE, 0, 1)
	local dz = w * w * (3 - 2 * w) * (tr.HitPos.z + lift - lo)
	if dz == 0 then return end
	local d = Vector(0, 0, dz)
	for _, mt in pairs(T) do mt:SetTranslation(mt:GetTranslation() + d) end
	local p = m.MercerRcvPuppet
	if IsValid(p) then
		p:SetPos(p:GetPos() + d)
		p:InvalidateBoneCache()
		p:SetupBones()
	end
end

local function victimOf(m)
	local v = m:GetNW2Entity("MercerVictim")
	if IsValid(v) and v ~= m then return v end
end

hook.Add("PreRender", "AlexMercerVictims", function()
	for _, m in ipairs(ents.FindByClass("drg_alex_mercer")) do
		if ALEX_MERCER_MPSMOOTH then ALEX_MERCER_MPSMOOTH(m) end -- (multiplayer: his smoothed place first)
		local v = victimOf(m)
		if v and not m:IsDormant() and not v:IsDormant() then
			local st = m.MercerRcvState or {}
			m.MercerRcvState = st
			if st.v ~= v then
				st.v, st.sq, st.lastSq, st.prev, st.consuming, st.consT = v, nil, nil, nil, nil, nil
				st.since = CurTime()
				st.blend0 = CurTime()
			end
			local pr = restOf(RCV_MDL, {"reference"})
			local nr = restOf(v:GetModel(), {"ragdoll", "reference"})
			local pose = pr and nr and puppetPose(m, st)
			local T = pose and retarget(v, pose, pr, nr)
			if T then
				feetOnGround(m, v, st, T, pose, pr, nr)
				-- blend from the last pose over the receiver tracks' blend time
				local k = math.Clamp((CurTime() - (st.blend0 or 0)) / BLEND, 0, 1)
				if k < 1 and st.prev then
					for i, mt in pairs(T) do
						local pm = st.prev[i]
						if pm then
							local b = Matrix()
							b:SetAngles(LerpAngle(k, pm:GetAngles(), mt:GetAngles()))
							b:SetTranslation(LerpVector(k, pm:GetTranslation(), mt:GetTranslation()))
							T[i] = b
						end
					end
				end
				st.prev = T
				-- the consume: its effects, the biomass over the body, the body into him (after the blend: scaled
				-- matrices must not be lerped)
				consumeStep(m, v, st, T)
				v.MercerVictimT, v.MercerVictimTT = T, CurTime()
				-- (user 2026-10-29: the body vanished from his hand while its entity lagged elsewhere - culled there)
				-- its render box takes in his place too: the posed body is drawn wherever the entity stands
				local a, b = v:GetPos(), m:GetPos()
				local lo = Vector(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z)) - Vector(120, 120, 120)
				local hi = Vector(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z)) + Vector(120, 120, 160)
				v:SetRenderBoundsWS(lo, hi)
				if not v.MercerVictimCb then
					v.MercerVictimCb = v:AddCallback("BuildBonePositions", buildBones)
					v:SetRenderBounds(Vector(-120, -120, -120), Vector(120, 120, 160))
					v.RenderOverride = victimDraw
				end
				v:InvalidateBoneCache()
			end
		end
	end
end)

-- The consume of the big ones (user 2026-11-05: "пусть поглощения хантера нормальным сделает, чтоб эффекты были, и нормально щупальца работали, по графам все"). No finisher: his grab's
-- node, the body his from NW2 MercerHConsume (the Hunter, the Leader, then its ragdoll), MercerHConsumeT its start, MercerHConsumeK which one. By the graphs, seconds from its start:
-- effectConsume on the body (graph_brawler_hunter effects/consume/consume, the Leader's bank {consume}) from {Head}, ForwardBackward: ec its start, back its
-- timeReverse. wave: receiver/cyclic. flow: node #92888d22, debrisTransformSoft001 down the joints, its program and when. blood: his worldDamage {Blood} {time, x left, y up, z back of his root}
local HCONS = {
	hunter = {ec = 0.6667, back = 1.5, wave = 1.167, waveEnd = 2.5, flow = {"hunter_consume_flow", 0.6667}, stop = 4.667,
		blood = {{1, -0.176, 0.049, -0.673}, {1.167, -0.176, 0.049, -0.673}, {1.333, -0.294, 0, -1.595}, {1.5, -0.294, 0, -1.595}}},
	leader = {ec = 0.6667, back = 2, wave = 1.167, waveEnd = 4, flow = {"hunter_consume_flow", 0.6667, 2.9}, stop = 6,
		blood = {{3.067, -0.176, 0.049, -0.673}, {3.267, -0.176, 0.049, -0.673}, {3.5, -0.176, 0.049, -0.673}, {4, -0.294, 0, -1.595}}},
}
-- effectConsume's spreadRate: the share of the body a second. As read: 0.7 x timeReverse 1.5 s is the whole body, the reversal at 2.167 s; on the video it covers it by then and it is off the legs at
-- about 2.6 s, off all but the head at about 3.6 s, so the way back at the same rate
local EC_SPREAD = 0.7
-- (the plane's front through the alpha test's curls, thinner toward it, BY EYE; the plane starts this far over the head and ends past the feet)
local HC_BANDS = {{veinsMat("alex_mercer_victim_veins_a", "0.62"), 0}, {veinsMat("alex_mercer_victim_veins_b", "0.35"), 0.07}, {veinsMat("alex_mercer_victim_veins_c", "0.005"), 0.14}}
local HC_TOP, HC_PAST = 20, 40
local function hcVeins(ent, st, flags)
	local c = st.c
	local t = CurTime() - st.t0 - c.ec
	if t <= 0 then return end
	local full = math.min(c.back * EC_SPREAD, 1.05)
	local R = t < c.back and math.min(t * EC_SPREAD, full) or full - (t - c.back) * EC_SPREAD
	if R <= 0 then return end
	local hb, lb, rb = ent:LookupBone("Head"), ent:LookupBone("Ball_L"), ent:LookupBone("Ball_R")
	local hm, lm, rm = hb and ent:GetBoneMatrix(hb), lb and ent:GetBoneMatrix(lb), rb and ent:GetBoneMatrix(rb)
	if not (hm and lm and rm) then return end
	local head = hm:GetTranslation()
	local axis = head - (lm:GetTranslation() + rm:GetTranslation()) * 0.5
	local L = axis:Length()
	if L < 1 then return end
	axis:Mul(1 / L)
	L = L + HC_TOP + HC_PAST
	local top = axis:Dot(head) + HC_TOP
	local was = render.EnableClipping(true)
	render.DepthRange(0, 0.99995)
	for _, b in ipairs(HC_BANDS) do
		local r = R - b[2]
		if r > 0 then
			render.PushCustomClipPlane(axis, top - r * L)
			render.MaterialOverride(b[1])
			ent:DrawModel(flags)
			render.PopCustomClipPlane()
		end
	end
	render.MaterialOverride()
	render.DepthRange(0, 1)
	render.EnableClipping(was)
end
local function hcDraw(self, flags)
	local st = self.MercerHC
	if st and st.old then
		st.old(self, flags)
	elseif isfunction(self.Draw) then
		self:Draw(flags)
	else
		self:DrawModel(flags)
	end
	if st then hcVeins(self, st, flags) end
end
local function hcLeave(st)
	local h = st.h
	if IsValid(h) then
		if h.RenderOverride == hcDraw then h.RenderOverride = st.old end
		h.MercerHC = nil
	end
	st.h, st.old = nil, nil
end
-- his worldDamage {Blood}: the bright splats of her pool (mo_pool*_v2, prototype_mother_scene.lua: without the pack no Hunter), lit by the spot, staying as hers. Size 8 as 6 m a quad, BY EYE: against Mercer's height the pool is
-- 3.5 m across on the video at 3.6 s; at 4 m a quad 2.2 m on the 2026-11-05 clip (the splat fills about half of its quad); each grows in its first second there
local POOL_SIZE, POOL_GROW, POOL_LIFE, POOL_FADE = 6 * M2U, 1, 45, 10
local hcPools, poolMats = {}, nil
local function hcPool(m, it)
	local p = m:GetPos() + (m:GetRight() * -it[2] + m:GetForward() * -it[4] + Vector(0, 0, 1 + it[3])) * M2U
	local tr = util.TraceLine({start = p, endpos = p - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY})
	if not tr.Hit or tr.StartSolid or tr.HitSky then return end
	hcPools[#hcPools + 1] = {pos = tr.HitPos + tr.HitNormal * 0.7, n = tr.HitNormal, rot = math.random(0, 359), t0 = CurTime(), i = #hcPools % 3 + 1}
end
hook.Add("PostDrawOpaqueRenderables", "AlexMercerHConsumePools", function(depth, sky)
	if depth or sky or not hcPools[1] then return end
	poolMats = poolMats or {Material("models/prototype_npcs/mo_pool1_v2"), Material("models/prototype_npcs/mo_pool2_v2"), Material("models/prototype_npcs/mo_pool3_v2")}
	local now = CurTime()
	for k = #hcPools, 1, -1 do
		local p = hcPools[k]
		local t = now - p.t0
		if t > POOL_LIFE + POOL_FADE then
			table.remove(hcPools, k)
		else
			if not p.col then
				local l = render.ComputeLighting(p.pos + p.n * 4, p.n)
				p.col = {math.Clamp(l.x, 0.3, 1) * 255, math.Clamp(l.y, 0.3, 1) * 255, math.Clamp(l.z, 0.3, 1) * 255}
			end
			local g = math.Clamp(t / POOL_GROW, 0, 1)
			local s = POOL_SIZE * (0.5 + 0.5 * g * (2 - g))
			render.SetMaterial(poolMats[p.i])
			render.DrawQuadEasy(p.pos, p.n, s, s, Color(p.col[1], p.col[2], p.col[3], t < POOL_LIFE and 255 or 255 * (1 - (t - POOL_LIFE) / POOL_FADE)), p.rot)
		end
	end
end)
-- The biomass on the big ones' joints: the items of his programs (receiver/cyclic, the flow) by the pack's engine (prototype_mother_pfx.lua), the data's alpha sprite, stuck to the joint. BY EYE against the video: the item's scale
-- (0.45) not on the size, as on their blood (prototype_hunter_fx.lua): at 0.2 m a sprite the mass stays inside the Hunter's outline. On the frames at 1.5 - 2 s the sprite's thick strand, 7 % of it, is about 5 cm against his forearm: 0.7 m, 1.5 x the data's
local HC_SYS = {charge = "debrisTransform002", charge_soft = "debrisTransformSoft001", charge_hot = "debrisTransformSoftHot2Alpha001"}
local function hcProg(h, name, start)
	local its = PROTO_PFX and ALEX_MERCER_FXPROG and ALEX_MERCER_FXPROG[name]
	if not its then return end
	for _, it in ipairs(its) do
		local sys = HC_SYS[it[1]]
		if sys and it[7] > it[6] then
			PROTO_PFX.Start(sys, {ent = h, bone = h:LookupBone(it[2]), x = it[3], y = it[4], z = it[5], attach = true, t0 = start + it[6], dur = it[7] - it[6], scale = 1.5, ro = it[10], b = it[9]})
		end
	end
end
local function hcStep(m, t0)
	local now, st = CurTime(), m.MercerHCSt
	local c = HCONS[m:GetNW2String("MercerHConsumeK", "hunter")]
	if t0 > 0 and c and now - t0 < c.stop and (not st or st.t0 ~= t0) then
		if st then hcLeave(st) end
		st = {t0 = t0, c = c, blood = 1, nextWave = t0 + c.wave}
		m.MercerHCSt = st
		local h = m:GetNW2Entity("MercerHConsume")
		if IsValid(h) then
			if ALEX_MERCER_TENDRILS then ALEX_MERCER_TENDRILS.Start(m, h, "hunter_consume", t0) end
			for i = 2, #c.flow do hcProg(h, c.flow[1], t0 + c.flow[i]) end
		end
	end
	if not st then return end
	if t0 ~= st.t0 or now - st.t0 >= st.c.stop then
		hcLeave(st)
		m.MercerHCSt = nil
		return
	end
	-- the body, then its ragdoll
	local h = m:GetNW2Entity("MercerHConsume")
	if IsValid(h) and h ~= st.h then
		hcLeave(st)
		st.h, st.old = h, h.RenderOverride
		h.MercerHC = st
		h.RenderOverride = hcDraw
	end
	local bl = st.c.blood
	while bl[st.blood] and now >= st.t0 + bl[st.blood][1] do
		hcPool(m, bl[st.blood])
		st.blood = st.blood + 1
	end
	-- the receiver's spawner: two waves at random, again as they end (BY EYE its end on the Hunter: spawn to the node's end, the video's legs bare from 2.6 s)
	if IsValid(st.h) and now >= st.nextWave and now - st.t0 < st.c.waveEnd then
		st.nextWave = now + WAVE_T
		local a = math.random(#RCV_WAVES)
		local b = (a + math.random(#RCV_WAVES - 1) - 1) % #RCV_WAVES + 1
		hcProg(st.h, RCV_WAVES[a], now)
		hcProg(st.h, RCV_WAVES[b], now)
	end
end
hook.Add("PreRender", "AlexMercerHConsume", function()
	for _, m in ipairs(ents.FindByClass("drg_alex_mercer")) do
		local t0 = m:GetNW2Float("MercerHConsumeT", 0)
		if t0 > 0 or m.MercerHCSt then hcStep(m, t0) end
	end
end)

-- for the disguise (the entity's Draw): the same retarget from Mercer's own bones
ALEX_MERCER_RETARGET = {restOf = restOf, retarget = retarget, buildBones = buildBones}

-- (user 2026-10-28: grabbing players) a player in Mercer's hand (NW2 MercerHeld, set by the server's holdVictim) sees
-- himself from outside: the camera behind and above the one holding him, looking at the pair; his own body drawn (the
-- receiver anims above play on it like on an NPC)
local function holderOf(ply)
	for _, m in ipairs(ents.FindByClass("drg_alex_mercer")) do
		if m:GetNW2Entity("MercerVictim") == ply then return m end
	end
end
local heldCam
hook.Add("CalcView", "AlexMercerHeldView", function(ply, origin, angles, fov)
	if not ply:GetNW2Bool("MercerHeld") or not ply:Alive() then heldCam = nil return end
	local m = holderOf(ply)
	local focus, yaw
	if IsValid(m) then
		focus, yaw = (m:WorldSpaceCenter() + ply:WorldSpaceCenter()) / 2 + Vector(0, 0, 20), m:GetAngles().y + 150
	else
		return
	end
	-- (a frozen player can't turn his view) from in front of Mercer and to his side, a little above, 180 u off the
	-- pair, not through walls - him and the body in his hand both in sight
	local dir = Angle(15, yaw, 0):Forward()
	local tr = util.TraceHull({start = focus, endpos = focus - dir * 180, mins = Vector(-6, -6, -6),
		maxs = Vector(6, 6, 6), mask = MASK_SOLID_BRUSHONLY})
	-- (smoothed: his hand and his turns jerk the pair around)
	local k = math.min(1, FrameTime() * 8)
	heldCam = heldCam and LerpVector(k, heldCam, tr.HitPos) or tr.HitPos
	return {origin = heldCam, angles = (focus - heldCam):Angle(), fov = fov, drawviewer = true}
end)
hook.Add("ShouldDrawLocalPlayer", "AlexMercerHeldView", function(ply)
	if ply:GetNW2Bool("MercerHeld") and ply:Alive() and holderOf(ply) then
		return true
	end
end)

-- (user 2026-10-28: put the victim down - "he just lets go and they walk off at once") when he lets one go alive
-- (the put-down, a grab given up) its bones blend from where his hand had them to its own animation over LETGO_BLEND:
-- it drops onto its feet instead of snapping there (buildBones above plays the blend)
hook.Add("PreRender", "AlexMercerLetGo", function()
	for _, m in ipairs(ents.FindByClass("drg_alex_mercer")) do
		local v = victimOf(m)
		if v then
			m.MercerLastVictim = v
		elseif IsValid(m.MercerLastVictim) then
			local lv = m.MercerLastVictim
			m.MercerLastVictim = nil
			if lv.MercerVictimT and CurTime() - (lv.MercerVictimTT or 0) < 0.25 then
				lv.MercerLetGo = {t = CurTime(), T = lv.MercerVictimT}
				lv.MercerVictimT = nil
			end
		end
	end
end)

-- (players 2026-10-28: "online, a consumed player respawns invisible") what the consume left on the player entity - the
-- held pose's bone callback / RenderOverride, the consumed marks, the hidden draw - cleared once he is alive again and
-- in nobody's hand
local nextVictimReset = 0
hook.Add("Think", "AlexMercerVictimPlayerReset", function()
	if RealTime() < nextVictimReset then return end
	nextVictimReset = RealTime() + 0.5
	local held = {}
	for _, m in ipairs(ents.FindByClass("drg_alex_mercer")) do
		local v = m:GetNW2Entity("MercerVictim")
		if IsValid(v) then held[v] = true end
	end
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and not held[ply] and (ply.MercerVictimCb or ply.MercerConsumeRag or ply.MercerVictimGone)
			and CurTime() - (ply.MercerVictimTT or 0) > 1 then
			if ply.MercerVictimCb then ply:RemoveCallback("BuildBonePositions", ply.MercerVictimCb) end
			ply.MercerVictimCb, ply.MercerConsumeRag, ply.MercerVictimGone = nil, nil, nil
			ply.MercerVictimT, ply.MercerLetGo = nil, nil
			if ply.RenderOverride == victimDraw then ply.RenderOverride = nil end
			ply:SetNoDraw(false)
		end
	end
end)
-