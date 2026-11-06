- The game's joint scale (its animations' SCL channels, lua/alex_mercer/animscale.lua from tools/build_animscale.py):
-- the blade lengthening as it strikes, the hammerfist and the claws growing, the fingers tucked away under them.
-- Source animations carry no scale: every frame Mercer's joints of his current sequence get the scale of its frame
-- (linear between the keys), eased in / out over a few frames (the game blends its tracks too). A scaled joint's
-- children keep their own size but sit where the scaled parent puts them.

include("alex_mercer/animscale.lua")
local SCALE = ALEX_MERCER_ANIMSCALE or {}
local EASE = 0.06 -- s
-- freezeScale (prototype_claws / prototype_hammerfist transition_to_idle: the striking arm's partition keeps its
-- scale while the stance comes back): claws 0.25 s, hammerfist 1.167 s then blendOut 0.2667 s. The blades have none:
-- alex_blades_retract shrinks the blade itself.
local FREEZE = {["Когти"] = {0.25, 0.06}, ["Молот"] = {1.167, 0.2667}}
local CLAW_GROW = 1.5 -- (user) the claws' strike growth: even over a hand and at most this (the game: x1.8 - x7)

local function at(keys, f)
	local k1 = keys[1]
	if f <= k1[1] then return k1[2], k1[3], k1[4] end
	for i = 2, #keys do
		local k2 = keys[i]
		if f <= k2[1] then
			local w = (f - k1[1]) / math.max(k2[1] - k1[1], 1e-6)
			return k1[2] + (k2[2] - k1[2]) * w, k1[3] + (k2[3] - k1[3]) * w, k1[4] + (k2[4] - k1[4]) * w
		end
		k1 = k2
	end
	return k1[2], k1[3], k1[4]
end

-- (the armour's long transformation is two anims in the game: the body's alex_act_armor_transformation shrinks it
-- away part by part while the armour model's own *_armor one grows the armour out of it - a model with the armour
-- takes the *_armor channels)
local function tableFor(ent)
	local name = ent:GetSequenceName(ent:GetSequence())
	-- (user 2026-10-22: no shrinking legs - the armour comes out of nothing like a mutation, he fades under the
	-- biomass) the transformation's scale channels are not played
	if name == "alex_act_armor_transformation" then return nil end
	if SCALE[name .. "_armor"] and string.find(ent:GetModel() or "", "_armor", 1, true) then return SCALE[name .. "_armor"] end
	return SCALE[name]
end

-- The powers' own hand bones (user: the claws crooked, not as in the game). The claws / hammerfist / musclemass arms
-- come with their own skeleton whose finger / wrist bones rest turned differently (alex_claws: Middle 21.5 deg, Index
-- 11.9, Wrist 8.3, Thumb 7.6) and longer. His anims live in alex_mercer_anims.mdl, built on the plain body, and Source
-- plays an included anim as the playing model's own bone default PLUS the anim's offset from the anim model's default
-- (RadianEuler added per channel): the lengths come out the power's own (right), but every frame's finger turn gets
-- the rest difference added - the blades fanned out crooked. The game plays the anim's own rotations. Here each such
-- bone gets (plain rest - power rest) added back to its local Euler angles (checked offline on all 124k finger frames
-- of the anims: 0.00 deg off the game's), the children follow.
local BASE_MDL = "models/mercer/alex_mercer.mdl"
-- (Lua patterns have no "|": the old "^(Index|Middle|Ring|Pink|Thumb)_" never matched a finger - the fingers were
-- never put right, only the wrists / eyes / grapple points; user 2026-10-22: the claws still crooked)
local FINGERS = {"Index_", "Middle_", "Ring_", "Pink_", "Thumb_"}
local function isFinger(n)
	for _, p in ipairs(FINGERS) do
		if string.sub(n, 1, #p) == p then return true end
	end
	return false
end
-- the bones put right: the hands, the eyes (7.5 deg), the grapple points (musclemass R_Wrist_Grapple 121 deg); the
-- spine's 2 deg (claws / hammerfist) is left - fixing it would redo the whole upper body every bone setup
local function fixable(n)
	return isFinger(n) or string.find(n, "^Wrist_") or string.find(n, "^Eye") or string.find(n, "_Grapple$")
end
local restCache = {}
-- {bone name -> its local rest angles} of a model's reference pose
local function restAngles(mdl)
	if restCache[mdl] ~= nil then return restCache[mdl] end
	local e = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
	if not IsValid(e) then restCache[mdl] = false return false end
	e:SetNoDraw(true)
	e:SetPos(vector_origin)
	e:SetAngles(angle_zero)
	local sq = e:LookupSequence("reference")
	e:ResetSequence(math.max(sq or 0, 0))
	e:SetCycle(0)
	e:InvalidateBoneCache()
	e:SetupBones()
	local r = {}
	for i = 0, e:GetBoneCount() - 1 do
		local m, p = e:GetBoneMatrix(i), e:GetBoneParent(i)
		local pm = p and p >= 0 and e:GetBoneMatrix(p)
		if m and pm then r[e:GetBoneName(i)] = (pm:GetInverseTR() * m):GetAngles() end
	end
	e:Remove()
	restCache[mdl] = r
	return r
end
local fixCache = {}
-- {bone name -> Angle to add} where the power model's hand rests turned differently from the plain body's
local function handFix(mdl)
	if fixCache[mdl] ~= nil then return fixCache[mdl] end
	local own, base = restAngles(mdl), restAngles(BASE_MDL)
	local out = false
	if own and base and mdl ~= BASE_MDL then
		for n, a in pairs(own) do
			local b = base[n]
			if fixable(n) and b then
				local d = Angle(b.p - a.p, b.y - a.y, b.r - a.r)
				if math.abs(d.p) + math.abs(d.y) + math.abs(d.r) > 0.3 then
					out = out or {}
					out[n] = d
				end
			end
		end
	end
	fixCache[mdl] = out
	return out
end
local function fixHands(ent, nb)
	local mdl = ent:GetModel() or ""
	local fix = handFix(mdl)
	if not fix then return end
	ent.MercerHandIds = ent.MercerHandIds or {}
	local plan = ent.MercerHandIds[mdl]
	if not plan then
		-- the fixed bones and everything under them, parents first (only those are touched each setup)
		plan = {}
		local under = {}
		for i = 0, ent:GetBoneCount() - 1 do
			local p = ent:GetBoneParent(i)
			local d = fix[ent:GetBoneName(i)]
			if d or (p and p >= 0 and under[p]) then
				under[i] = true
				plan[#plan + 1] = {i, p, d}
			end
		end
		ent.MercerHandIds[mdl] = plan
	end
	-- down the hierarchy: local = parent's (as the engine built it)^-1 * bone, the fixed ones turned back, then put
	-- under the parent's new matrix (scratch matrices kept per bone: no garbage a setup - the collector's hitches)
	local scratch = ent.MercerHandScratch
	if not scratch then scratch = {} ent.MercerHandScratch = scratch end
	local orig, moved = scratch.orig or {}, scratch.moved or {}
	scratch.orig, scratch.moved = orig, moved
	for k in pairs(orig) do orig[k] = nil end
	for k in pairs(moved) do moved[k] = nil end
	for _, it in ipairs(plan) do
		local i, p, d = it[1], it[2], it[3]
		if i < (nb or 256) then
			local m = ent:GetBoneMatrix(i)
			local po = p and p >= 0 and (orig[p] or ent:GetBoneMatrix(p))
			if m and po then
				orig[i] = m
				local L, nm = scratch[i * 2], scratch[i * 2 + 1]
				if not L then
					L, nm = Matrix(), Matrix()
					scratch[i * 2], scratch[i * 2 + 1] = L, nm
				end
				L:Set(po)
				L:InvertTR()
				L:Mul(m)
				if d then
					local a = L:GetAngles()
					a.p, a.y, a.r = a.p + d.p, a.y + d.y, a.r + d.r
					L:SetAngles(a)
				end
				nm:Set(moved[p] or po)
				nm:Mul(L)
				ent:SetBoneMatrix(i, nm)
				moved[i] = nm
			end
		end
	end
end

local function scaleBones(ent, nb)
	local cur = ent.MercerScaleCur
	local d = tableFor(ent)
	if not d and not next(cur) then return end
	-- this frame's targets, eased
	local now = RealTime()
	local dt = math.Clamp(now - (ent.MercerScaleT or now), 0, 0.1)
	ent.MercerScaleT = now
	-- leaving a scaled anim: the form's freezeScale holds the joints it left, then lets go over its blendOut
	if d ~= ent.MercerScaleD then
		local f = ent.GetMercerForm and ent:GetMercerForm()
		local fr = f and FREEZE[f.name]
		if ent.MercerScaleD and fr then ent.MercerFreezeUntil, ent.MercerFreezeOut = now + fr[1], fr[2] end
		ent.MercerScaleD = d
	end
	local frozen = now < (ent.MercerFreezeUntil or 0)
	local k = 1 - math.exp(-dt / ((not frozen and ent.MercerFreezeUntil and now < ent.MercerFreezeUntil + 1)
		and math.max(ent.MercerFreezeOut or EASE, 0.01) / 3 or EASE))
	if ent.MercerScaleNoEase then k = 1 end
	local tgt = {}
	if d then
		local f = ent:GetCycle() * (d.n - 1)
		local claws = string.find(ent:GetModel() or "", "_claws", 1, true)
		local grow = claws and {}
		for name, keys in pairs(d.b) do
			local b = ent:LookupBone(name)
			if b then
				tgt[b] = {at(keys, f)}
				-- (user 2026-10-22: a hand shrank as the claws struck) with the claws out nothing is scaled down
				if claws then
					local t0 = tgt[b]
					t0[1], t0[2], t0[3] = math.max(t0[1], 1), math.max(t0[2], 1), math.max(t0[3], 1)
				end
				-- (user: the claws grow unevenly in the strikes - one finger x4, another x7 - and the longest far too
				-- long) with the claws out the growing fingers of a hand all take one scale: that hand's largest,
				-- at most CLAW_GROW (the shrinking ones - the human fingers tucked away - stay as they are)
				local t = tgt[b]
				local side = grow and isFinger(name) and string.match(name, "_([LR])") or nil
				if side and math.max(t[1], t[2], t[3]) > 1 then
					local g = grow[side] or {s = 1, bones = {}}
					grow[side] = g
					g.s = math.max(g.s, t[1], t[2], t[3])
					g.bones[#g.bones + 1] = b
				end
			end
		end
		for _, g in pairs(grow or {}) do
			local s = math.min(g.s, CLAW_GROW)
			for _, b in ipairs(g.bones) do tgt[b] = {s, s, s} end
		end
	end
	for b, c in pairs(cur) do
		if not tgt[b] then tgt[b] = frozen and {c[1], c[2], c[3]} or {1, 1, 1} end
	end
	local any = false
	for b, t in pairs(tgt) do
		local c = cur[b] or {1, 1, 1}
		c[1], c[2], c[3] = c[1] + (t[1] - c[1]) * k, c[2] + (t[2] - c[2]) * k, c[3] + (t[3] - c[3]) * k
		if math.abs(c[1] - 1) + math.abs(c[2] - 1) + math.abs(c[3] - 1) < 0.003 and not d then
			cur[b] = nil
		else
			cur[b] = c
			any = true
		end
	end
	if not any then return end
	-- apply down the hierarchy: own scale on the joint, children moved by their scaled parent
	local old, new = {}, {}
	for i = 0, (nb or ent:GetBoneCount()) - 1 do
		local m = ent:GetBoneMatrix(i)
		if m then
			old[i] = Matrix(m)
			local p = ent:GetBoneParent(i)
			local moved = p and p >= 0 and new[p]
			local c = cur[i]
			if moved or c then
				local nm = Matrix(m)
				if moved then
					local off = old[p]:GetInverseTR() * m:GetTranslation()
					nm:SetTranslation(new[p] * off)
				end
				if c then nm:Scale(Vector(c[1], c[2], c[3])) end
				new[i] = nm
				ent:SetBoneMatrix(i, nm)
			end
		end
	end
end

-- (user 2026-10-22, setting them by hand) the claws' right-hand fingers: all moved toward the back of the hand (the
-- knuckles' side), the middle one further from the index, the thumb's claw longer (where it is). The hand's own
-- frame each setup: along = wrist -> middle base, across = little finger -> index, the back = along x across.
-- Units are Source units (1 = 2.5 cm).
local CLAW_R = {back = 1.2, middleOut = 3.0, thumbLen = 1.4, palmPinky = 1.6,
	-- the fingers fanned a little about the back axis, degrees (+ toward the thumb)
	splay = {Index = 4, Middle = 0, Ring = -4, Pink = -8}}
-- a matrix's turn about a world axis through a pivot (its axes and position)
local function rot(v, ax, a)
	local c, s = math.cos(a), math.sin(a)
	return v * c + ax:Cross(v) * s + ax * (ax:Dot(v) * (1 - c))
end
local function turnAbout(m, pivot, ax, a)
	local f, r, u = rot(m:GetForward(), ax, a), rot(m:GetRight(), ax, a), rot(m:GetUp(), ax, a)
	m:SetForward(f)
	m:SetRight(r)
	m:SetUp(u)
	m:SetTranslation(pivot + rot(m:GetTranslation() - pivot, ax, a))
end
local function scaleAlong(m, d, k)
	local o = m:GetTranslation()
	k = k - 1
	local S = Matrix({{1 + k * d.x * d.x, k * d.x * d.y, k * d.x * d.z, 0}, {k * d.y * d.x, 1 + k * d.y * d.y, k * d.y * d.z, 0},
		{k * d.z * d.x, k * d.z * d.y, 1 + k * d.z * d.z, 0}, {0, 0, 0, 1}})
	local R = Matrix(m)
	R:SetTranslation(Vector(0, 0, 0))
	local n = S * R
	n:SetTranslation(o)
	return n
end
local CLAW_FINGERS = {"Index", "Middle", "Ring", "Pink", "Thumb"}
local function clawRight(ent, nb)
	if not string.find(ent:GetModel() or "", "_claws", 1, true) then return end
	nb = nb or ent:GetBoneCount()
	local function bm(n)
		local b = ent:LookupBone(n)
		if b and b < nb then return b, ent:GetBoneMatrix(b) end
	end
	local _, W = bm("Wrist_R")
	local _, I = bm("Index_Base_R")
	local _, P = bm("Pink_Base_R")
	local _, M = bm("Middle_Base_R")
	if not (W and I and P and M) then return end
	local along = (M:GetTranslation() - W:GetTranslation()):GetNormalized()
	local across = (I:GetTranslation() - P:GetTranslation()):GetNormalized()
	local back = along:Cross(across):GetNormalized()
	-- (user: the little finger in the air; widening it both ways from the wrist's middle poked out there) the palm
	-- stretched across toward the little finger only: the index side (a plane through the index base) stays put
	local wb = ent:LookupBone("Wrist_R")
	if CLAW_R.palmPinky ~= 1 then
		local o = W:GetTranslation()
		local edge = (I:GetTranslation() - o):Dot(across)
		local pm = scaleAlong(W, across, CLAW_R.palmPinky)
		pm:SetTranslation(o + across * (edge * (1 - CLAW_R.palmPinky)))
		ent:SetBoneMatrix(wb, pm)
	end
	for _, f in ipairs(CLAW_FINGERS) do
		local off = back * CLAW_R.back
		if f == "Middle" then off = off - across * CLAW_R.middleOut end
		local a = math.rad((CLAW_R.splay[f] or 0))
		local _, base = bm(f .. "_Base_R")
		local pivot = base and base:GetTranslation()
		for _, n in ipairs({f .. "_Base_R", f .. "_R", f .. "_R_End"}) do
			local b, m = bm(n)
			if m then
				if a ~= 0 and pivot then turnAbout(m, pivot, back, a) end
				m:SetTranslation(m:GetTranslation() + off)
				ent:SetBoneMatrix(b, m)
			end
		end
	end
	-- the thumb's claw: longer along itself, from where it starts
	local tb, T = bm("Thumb_R")
	local eb, E = bm("Thumb_R_End")
	if T and E and CLAW_R.thumbLen ~= 1 then
		local o, e = T:GetTranslation(), E:GetTranslation()
		ent:SetBoneMatrix(tb, scaleAlong(T, (e - o):GetNormalized(), CLAW_R.thumbLen))
		local ne = Matrix(E)
		ne:SetTranslation(o + (e - o) * CLAW_R.thumbLen)
		ent:SetBoneMatrix(eb, ne)
	end
end

-- (user 2026-10-22: "give the claws some life") the stance / walk / run hold the claws' fingers in one baked pose
-- (CLAW_FINGERS_FROM): each claw now flexes slowly about its knuckle, its own phase, with a faint quick tremor - both
-- hands. Not game data: CLAW_LIFE amplitudes / speeds in degrees / rad per s
-- (user 2026-10-27: "the claws have no animation" - 5 deg did not show) amp 5 -> 14, speed 1.6 -> 2.2, tremor 1.2 -> 2.5
local CLAW_LIFE = {amp = 18, speed = 2.2, tremor = 2.5, tremorSpeed = 9}
local CLAW_PHASE = {Index = 0, Middle = 1.3, Ring = 2.4, Pink = 3.7, Thumb = 5.1}
local function clawLife(ent, nb)
	if not string.find(ent:GetModel() or "", "_claws", 1, true) then return end
	nb = nb or ent:GetBoneCount()
	local t = CurTime() + (ent:EntIndex() % 7)
	for _, side in ipairs({"R", "L"}) do
		local bi, bp = ent:LookupBone("Index_Base_" .. side), ent:LookupBone("Pink_Base_" .. side)
		local I = bi and bi < nb and ent:GetBoneMatrix(bi)
		local P = bp and bp < nb and ent:GetBoneMatrix(bp)
		if I and P then
			local hinge = (I:GetTranslation() - P:GetTranslation()):GetNormalized()
			if side == "L" then hinge = -hinge end
			-- (user 2026-10-27: still nothing) the index / middle claws are skinned to their *_Base bones (85 / 151 verts;
			-- Index_R / Middle_R carry 3): the whole finger turns from its base - base, joint and end about the base
			for f, ph in pairs(CLAW_PHASE) do
				local chain = {ent:LookupBone(f .. "_Base_" .. side), ent:LookupBone(f .. "_" .. side),
					ent:LookupBone(f .. "_" .. side .. "_End")}
				local B = chain[1] and chain[1] < nb and ent:GetBoneMatrix(chain[1])
				if B then
					local a = math.rad(CLAW_LIFE.amp * math.sin(t * CLAW_LIFE.speed + ph)
						+ CLAW_LIFE.tremor * math.sin(t * CLAW_LIFE.tremorSpeed + ph * 2.7))
					local pivot = B:GetTranslation()
					for _, b in ipairs(chain) do
						local M = b and b < nb and ent:GetBoneMatrix(b)
						if M then
							turnAbout(M, pivot, hinge, a)
							ent:SetBoneMatrix(b, M)
						end
					end
				end
			end
		end
	end
end

-- (players 2026-10-27: "jumping with a gun, the gun hovers in the air") the gun follows R_Wrist_Grapple, which the
-- non-weapon anims key ~60 u off the wrist (where a held human goes: jump_long_D -59.7 / 31.6 / -1.7): with a gun in
-- hand it is put back where alex_weap_rifle_stand has it under Wrist_R (frame 0, local), whatever plays
local GRIP = Matrix()
GRIP:SetTranslation(Vector(-1.236323, -2.479855, 0.582117))
GRIP:SetAngles(Angle(math.deg(-0.089621), math.deg(-1.793148), math.deg(-3.084410)))
-- (2026-11-04) the game's partitions over whatever plays (tools/armposes.py, ALEX_MERCER_ARMPOSE): the gun's forearm and hand
-- (prototype_firearm firearm_partition, in the sprint, the jumps, the falls, the landings), a caught rocket's arm (its walk and run:
-- pose/missile on arm_right; else the same firearm_partition), the carry's upper body over the air dash with an object. Here on the
-- bones, not as overlay layers (those froze under graph nodes) nor baked (a rebuild of the model for each). Only the rotations: a
-- bone keeps its length as the model has it; what hangs under them follows, as in fixHands, which runs after this and takes a power
-- model's rest difference off what the engine plays (so here it goes on first). The tracks' blend, 0.1 s. Not in a disguise: another rig
local ARM_FADE = 0.1
local function armWanted(ent)
	local missile, carry, reach = ent:GetNW2Bool("MercerMissileHold"), ent:GetNW2Bool("MercerObjHold"), ent:GetNW2Bool("MercerAirReach")
	if not (missile or carry or reach or ent:GetNW2String("MercerGun", "") ~= "") then return end
	local f = ent.GetMercerForm and ent:GetMercerForm()
	if not f or f.kind == "disguise" then return end
	-- (alex_mercer_air_grab, E held over a jump's own node: graph_jump 1194, alex_climb_air on upper_body2; the server sets it with his hands free)
	if reach then return "reach" end
	local seq = string.lower(ent:GetSequenceName(ent:GetSequence()) or "")
	if carry then return seq == "alex_loco_aerial_dash" and "carry" or nil end
	if missile then
		if string.find(seq, "^alex_weap_missile") then return end
		if seq == "alex_loco_grap_walk_n_gv" or seq == "alex_loco_grap_run_n_gv" then return "missile" end
		return "firearm"
	end
	if string.find(seq, "^alex_weap_rifle") or string.find(seq, "^alex_rifle") then return end
	return "firearm"
end
local function armPose(ent, nb)
	local POSES = ALEX_MERCER_ARMPOSE
	if not POSES then return end
	local want = armWanted(ent)
	local now = RealTime()
	local dt = math.Clamp(now - (ent.MercerArmT or now), 0, 0.1)
	ent.MercerArmT = now
	local name, w = ent.MercerArmName, ent.MercerArmW or 0
	if want == name then
		w = math.min(1, w + dt / ARM_FADE)
	else
		w = math.max(0, w - dt / ARM_FADE)
		if w <= 0 then name = want end
	end
	ent.MercerArmName, ent.MercerArmW = name, w
	if not name or w <= 0 then return end
	local mdl = ent:GetModel() or ""
	ent.MercerArmPlans = ent.MercerArmPlans or {}
	local plans = ent.MercerArmPlans[mdl]
	if not plans then plans = {} ent.MercerArmPlans[mdl] = plans end
	local plan = plans[name]
	if not plan then
		-- the pose's bones and everything under them, parents first
		plan = {}
		local pose, under, fix = POSES[name], {}, handFix(mdl)
		for i = 0, ent:GetBoneCount() - 1 do
			local p = ent:GetBoneParent(i)
			local a = pose[ent:GetBoneName(i)]
			local d = a and fix and fix[ent:GetBoneName(i)]
			if d then a = Angle(a.p - d.p, a.y - d.y, a.r - d.r) end
			if a or (p and p >= 0 and under[p]) then
				under[i] = true
				plan[#plan + 1] = {i, p, a}
			end
		end
		plans[name] = plan
	end
	-- (as fixHands: local = parent's as the engine built it ^-1 * bone, then under the parent's new matrix; scratch per bone)
	local scratch = ent.MercerArmScratch
	if not scratch then scratch = {} ent.MercerArmScratch = scratch end
	local orig, moved = scratch.orig or {}, scratch.moved or {}
	scratch.orig, scratch.moved = orig, moved
	for k in pairs(orig) do orig[k] = nil end
	for k in pairs(moved) do moved[k] = nil end
	for _, it in ipairs(plan) do
		local i, p, a = it[1], it[2], it[3]
		if i < (nb or 256) then
			local m = ent:GetBoneMatrix(i)
			local po = p and p >= 0 and (orig[p] or ent:GetBoneMatrix(p))
			if m and po then
				orig[i] = m
				local L, nm = scratch[i * 2], scratch[i * 2 + 1]
				if not L then
					L, nm = Matrix(), Matrix()
					scratch[i * 2], scratch[i * 2 + 1] = L, nm
				end
				L:Set(po)
				L:InvertTR()
				L:Mul(m)
				if a then L:SetAngles(w >= 1 and a or LerpAngle(w, L:GetAngles(), a)) end
				nm:Set(moved[p] or po)
				nm:Mul(L)
				ent:SetBoneMatrix(i, nm)
				moved[i] = nm
			end
		end
	end
end

local function gunGrip(ent, nb)
	if ent:GetNW2String("MercerGun", "") == "" then return end
	local w, g = ent:LookupBone("Wrist_R"), ent:LookupBone("R_Wrist_Grapple")
	if not (w and g) or w >= nb or g >= nb then return end
	local W = ent:GetBoneMatrix(w)
	if W then ent:SetBoneMatrix(g, W * GRIP) end
end

-- for a copy of his model drawn beside him (the armour's other half): the same joint scale on it
function ALEX_MERCER_SCALE_ATTACH(e)
	e.MercerScaleCur, e.MercerScaleNoEase = {}, true
	e.MercerScaleCb = e:AddCallback("BuildBonePositions", function(en, nb)
		fixHands(en, nb)
		scaleBones(en, nb)
		clawRight(en, nb)
		clawLife(en, nb)
	end)
end

hook.Add("Think", "AlexMercerAnimScale", function()
	for _, e in ipairs(ents.FindByClass("drg_alex_mercer")) do
		if not e.MercerScaleCb then
			e.MercerScaleCur = {}
			e.MercerScaleCb = e:AddCallback("BuildBonePositions", function(en, nb)
				armPose(en, nb)
				fixHands(en, nb)
				scaleBones(en, nb)
				clawRight(en, nb)
				clawLife(en, nb)
				gunGrip(en, nb)
			end)
		end
	end
end)
-