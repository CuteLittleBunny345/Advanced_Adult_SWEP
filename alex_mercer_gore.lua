- Dismemberment as the game's (build/graph_hitreaction.txt, user 2026-10-08 "расчленение и gore как в игре"):
-- reference {dismember} under bank {damaged}: a Slash hit that kills a human (health 0, not held in a grab slot,
-- not a supersoldier / infected2 / TankGunner = our big bosses) with a free combat budget token {Gib} -> bank
-- dismember/<cut>: the blood effect (human/effects/dismemberment), the "dismembered" line, the gib store's two halves
-- (spawnGib inheritPose, copyShader = the ped's own look) and the death. Cuts (pedestrians/shared.p3d peddis_m_generic_*,
-- the seam planes measured on the meshes, ped 1.86 m tall, game x = his left, y up):
--  horiz_01 (the default - claws' ground spike, the plain Slash): y 1.187 (0.638 of his height), normal up; the top
--   half keeps the arms
--  vert_01: x 0, normal his left
--  diag_01: (0.113, 1.496), normal (0.769, -0.634); diag_02: (-0.131, 1.518), normal (0.757, 0.640)
-- Which cut: the game picks it by the hit type of the blow (mostly horiz_01, some slashes vert / diag); ours by the
-- swing that killed: level -> horiz, up / down -> vert, slanted -> diag 01 / 02 by its slant.
-- GMod: the NPC's own model twice as prop_ragdolls in its pose, each drawn clipped at the cut (client:
-- alex_mercer_gore_cl.lua), the side cut off collisionless and weightless; the death ragdoll suppressed
-- (DMG_REMOVENORAGDOLL). Blood: the game's slash-on-flesh systems (goreBloodGush001, goreBloodMistFanOut001), its
-- blood splat decals, sounds claw_dismember / blood_gush / flesh_rip.

local Gore = CreateConVar("alex_mercer_gore", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED},
	"Alex Mercer: his slashes cut the humans they kill in two, as the game", 0, 1)

local Dbg = CreateConVar("alex_mercer_gore_debug", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Alex Mercer: print the dismemberment's decisions")
local function dbg(...) if Dbg:GetBool() then MsgN("[alex_mercer_gore] ", string.format(...)) end end
local M2U = 39.37
local GAME_H = 1.86
-- {centre x (his left), centre y (up), normal x, normal y} in game metres, the kept piece "a" on the normal's side
local CUTS = {
	horiz_01 = {-0.011, 1.187, 0, 1},
	vert_01 = {0.001, 1.548, 1, 0},
	diag_01 = {0.113, 1.496, 0.769, -0.634},
	diag_02 = {-0.131, 1.518, 0.757, 0.640},
}
local BUDGET, BUDGET_T = 4, 2 -- (the game's {Gib} combat budget token: at most this many in this many s)
local LIFE = 120 -- s the halves stay (then fade)
local recent, pending = {}, {}

local function humanoid(e)
	if not (e:IsNPC() or e:IsNextBot()) or e:GetClass() == "drg_alex_mercer" then return false, "not an NPC" end
	local mdl = e:GetModel()
	if not mdl or not util.IsValidRagdoll(mdl) then return false, "no ragdoll model " .. tostring(mdl) end
	-- (the bosses: the game leaves supersoldiers / tank gunners whole)
	local h = e:OBBMaxs().z - e:OBBMins().z
	if h > 110 * (e:GetModelScale() or 1) then return false, "too big " .. math.floor(h) end
	-- (the pack's mutated infected: the graph's dismember banks leave the class infected2 whole)
	if e.MercerNoGore then return false, "whole by the graph" end
	return true
end

local function cutFor(swing)
	if not swing or swing:LengthSqr() < 1 then return "horiz_01" end
	local d = swing:GetNormalized()
	local z = math.abs(d.z)
	if z < 0.42 then return "horiz_01" end
	if z > 0.87 then return "vert_01" end
	-- (slanted: by its slant across him - x = his right)
	return (d.z * d.x >= 0) and "diag_01" or "diag_02"
end

local ARM = {"UpperArm", "Forearm", "Hand", "Finger", "Ulna", "Wrist", "Elbow", "Bicep", "Trapezius"}
local function isArm(name)
	if not string.find(name, "_[LR]_") then return false end
	for _, k in ipairs(ARM) do if string.find(name, k, 1, true) then return true end end
	return false
end

-- the pose, look and swing of the one about to die (EntityTakeDamage, before the damage)
hook.Add("EntityTakeDamage", "AlexMercerGore", function(e, dmg)
	if not Gore:GetBool() then return end
	local m = dmg:GetAttacker()
	if not IsValid(m) or m:GetClass() ~= "drg_alex_mercer" or not dmg:IsDamageType(DMG_SLASH) then return end
	if e.MercerHeldBy or e.MercerGone or e:Health() <= 0 then return end
	local ok, why = humanoid(e)
	if not ok then
		if (e.MercerGoreWhyT or 0) < CurTime() then e.MercerGoreWhyT = CurTime() + 2 dbg("%s skipped: %s", e:GetClass(), why) end
		return
	end
	local now = CurTime()
	-- (a full budget: a plain death ragdoll, not a vanished body)
	local n = 0
	for _, t in ipairs(recent) do if now - t <= BUDGET_T then n = n + 1 end end
	if n >= BUDGET then return end
	local bones, byName = {}, {}
	for b = 0, e:GetBoneCount() - 1 do
		local pos, ang = e:GetBonePosition(b)
		if pos then
			bones[b] = {pos, ang}
			byName[e:GetBoneName(b) or ""] = bones[b] -- (the pack's half models: their bones by name)
		end
	end
	local sw = (m.MercerSwing and now - (m.MercerSwingT or 0) < 0.1) and m.MercerSwing or nil
	-- the swing seen from the victim: x = its right, z = up (the slant's sign)
	local swl = sw and Vector(sw:Dot(e:GetRight()), sw:Dot(e:GetForward()), sw.z) or nil
	local bg = {}
	for i = 0, e:GetNumBodyGroups() - 1 do bg[i] = e:GetBodygroup(i) end
	local sub = {}
	for i = 0, 31 do local s = e:GetSubMaterial(i) if s and s ~= "" then sub[i] = s end end
	pending[e] = {mdl = e:GetModel(), skin = e:GetSkin(), bg = bg, col = e:GetColor(), mat = e:GetMaterial(), sub = sub,
		scale = e:GetModelScale(), blood = e:GetBloodColor(), pos = e:GetPos(), ang = Angle(0, e:GetAngles().y, 0),
		h = e:OBBMaxs().z - e:OBBMins().z, bones = bones, byName = byName, vel = e:GetVelocity(), force = dmg:GetDamageForce(),
		cut = cutFor(swl), m = m}
	dmg:SetDamageType(bit.bor(dmg:GetDamageType(), DMG_REMOVENORAGDOLL)) -- (no death ragdoll: the halves are it)
end)

local function bleed(pos, n, big)
	local ed = EffectData()
	ed:SetOrigin(pos)
	ed:SetNormal(n)
	ed:SetScale(big and 1.6 or 1.2)
	ed:SetFlags(13) -- blood_gush (alex_mercer_vfx)
	util.Effect("alex_mercer_vfx", ed, true, true)
	ed:SetFlags(14) -- blood_mist
	util.Effect("alex_mercer_vfx", ed, true, true)
	local ed2 = EffectData()
	ed2:SetOrigin(pos)
	ed2:SetNormal(n)
	util.Effect("BloodImpact", ed2, true, true)
end

-- (user 2026-10-29: "they fly off far when cut") the halves' push, kept small: his own velocity capped at 150 u/s, the
-- top half 55 / 45 up, the bottom 25 / 15, the blow's force at 0.004 up to 90 u/s
local function halfKick(d, kn, keepA)
	local v = d.vel
	if v:Length() > 150 then v = v:GetNormalized() * 150 end
	return v + kn * (keepA and 55 or 25) + Vector(0, 0, keepA and 45 or 15)
		+ d.force:GetNormalized() * math.min(d.force:Length() * 0.004, 90)
end

local function spawnHalf(d, P, N, keepA)
	local rag = ents.Create("prop_ragdoll")
	if not IsValid(rag) then return end
	rag:SetModel(d.mdl)
	rag:SetPos(d.pos)
	rag:SetAngles(d.ang)
	rag:SetSkin(d.skin or 0)
	rag:SetColor(d.col)
	rag:SetModelScale(d.scale or 1)
	if d.mat and d.mat ~= "" then rag:SetMaterial(d.mat) end
	for i, v in pairs(d.bg) do rag:SetBodygroup(i, v) end
	for i, v in pairs(d.sub) do rag:SetSubMaterial(i, v) end
	rag:Spawn()
	rag:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	if d.blood then rag:SetBloodColor(d.blood) end
	local side = keepA and 1 or -1
	local horiz = d.cut == "horiz_01"
	local kn = N * side
	-- pose, then which bodies are kept (their centre on our side; horizontal: the arms go with the top)
	local ref, refD
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local ph = rag:GetPhysicsObjectNum(i)
		local b = rag:TranslatePhysBoneToBone(i)
		local bp = d.bones[b]
		if IsValid(ph) and bp then
			ph:SetPos(bp[1])
			ph:SetAngles(bp[2])
			local name = rag:GetBoneName(b) or ""
			local keep = (bp[1] - P):Dot(kn) >= 0
			if horiz and isArm(name) then keep = keepA end
			if keep then
				local dd = math.abs((bp[1] - P):Dot(N)) + (bp[1] - P):Length() * 0.2
				if not refD or dd < refD then ref, refD = b, dd end
				ph:SetVelocity(halfKick(d, kn, keepA))
			else
				-- the piece cut off: nothing of it may hold or push the half
				ph:EnableCollisions(false)
				ph:SetMass(1)
				ph:SetVelocity(d.vel)
			end
		end
	end
	if not ref then rag:Remove() return end
	-- the cut in the reference bone's frame (the client draws the half clipped at it)
	local rp, ra = rag:GetBonePosition(ref)
	if not rp then local bp = d.bones[ref] rp, ra = bp[1], bp[2] end
	local lp = WorldToLocal(P, Angle(), rp, ra)
	local ln = WorldToLocal(kn, Angle(), vector_origin, ra)
	rag:SetNW2Int("MCutBone", ref)
	rag:SetNW2Vector("MCutP", lp)
	rag:SetNW2Vector("MCutN", ln)
	rag:SetNW2Int("MCutArms", horiz and (keepA and 1 or 2) or 0) -- 1: also draw the arms whole, 2: never the arms
	rag:SetNW2Float("MCutT", CurTime())
	rag:SetNW2Bool("MCut", true)
	rag:Fire("FadeAndRemove", "1", LIFE)
	return rag
end

-- (user 2026-10-29: "real halves") the Prototype NPC pack's soldiers have their meshes cut at the game's seam planes
-- into half models with caps (tools/build_npc.py <stem>_gibs: <stem>_gib_<cut>_t / _b in PROTO_NPC_MODELS), each a
-- ragdoll of its own bones: those are spawned instead of two clipped copies. Only the cuts that were built; a cut
-- without halves falls back to horiz_01, and a model without any to the clipped copies.
local function packHalves(mdl, cut)
	if not PROTO_NPC_MODELS then return end
	local stem
	for k, v in pairs(PROTO_NPC_MODELS) do
		if v == mdl and not string.find(k, "_gib_", 1, true) then stem = k break end
	end
	if not stem then return end
	for _, c in ipairs({cut, "horiz_01"}) do
		local t, b = PROTO_NPC_MODELS[stem .. "_gib_" .. c .. "_t"], PROTO_NPC_MODELS[stem .. "_gib_" .. c .. "_b"]
		if t and b and util.IsValidModel(t) and util.IsValidModel(b) then return t, b, c end
	end
end

local function spawnHalfModel(d, mdl, P, N, keepA)
	local rag = ents.Create("prop_ragdoll")
	if not IsValid(rag) then return end
	rag:SetModel(mdl)
	rag:SetPos(d.pos)
	rag:SetAngles(d.ang)
	rag:SetSkin(d.skin or 0)
	rag:SetColor(d.col)
	rag:SetModelScale(d.scale or 1)
	if d.mat and d.mat ~= "" then rag:SetMaterial(d.mat) end
	rag:Spawn()
	rag:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	if d.blood then rag:SetBloodColor(d.blood) end
	local kn = N * (keepA and 1 or -1)
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local ph = rag:GetPhysicsObjectNum(i)
		local b = rag:TranslatePhysBoneToBone(i)
		local bp = b and d.byName[rag:GetBoneName(b) or ""]
		if IsValid(ph) and bp then
			ph:SetPos(bp[1])
			ph:SetAngles(bp[2])
			ph:SetVelocity(halfKick(d, kn, keepA))
			ph:Wake()
		end
	end
	rag:Fire("FadeAndRemove", "1", LIFE)
	return rag
end

hook.Add("PostEntityTakeDamage", "AlexMercerGore", function(e, dmg, took)
	local d = pending[e]
	if not d then return end
	pending[e] = nil
	if e:Health() > 0 and not e:IsFlagSet(FL_KILLME) then return end
	local now = CurTime()
	for i = #recent, 1, -1 do if now - recent[i] > BUDGET_T then table.remove(recent, i) end end
	if #recent >= BUDGET then dbg("%s: gib budget full", e:GetClass()) return end
	recent[#recent + 1] = now
	dbg("%s cut %s (h %d)", e:GetClass(), d.cut, math.floor(d.h))
	local halfT, halfB, hcut = packHalves(d.mdl, d.cut)
	if hcut then d.cut = hcut end
	local c = CUTS[d.cut]
	local s = d.h / (GAME_H * M2U) * M2U -- game metres -> units, by his height
	local left = -d.ang:Right()
	local up = Vector(0, 0, 1)
	local P = d.pos + up * (c[2] * s) + left * (c[1] * s)
	local N = (left * c[3] + up * c[4]):GetNormalized()
	if halfT then
		dbg("%s: the pack's halves %s", e:GetClass(), hcut)
		spawnHalfModel(d, halfT, P, N, true)
		spawnHalfModel(d, halfB, P, N, false)
	else
		spawnHalf(d, P, N, true)
		spawnHalf(d, P, N, false)
	end
	-- the whole body gone at once (a DrGBase NPC dies a little later, in its own coroutine - no ragdoll then)
	if IsValid(e) then
		e:SetNoDraw(true)
		e:SetNotSolid(true)
		for _, c in ipairs(e:GetChildren()) do if IsValid(c) then c:SetNoDraw(true) end end
	end
	-- blood out of both sides of the cut, the splats around, the sounds
	bleed(P + N * 4, N, true)
	bleed(P - N * 4, -N, false)
	for i = 1, 4 do
		local dir = VectorRand()
		dir.z = -math.abs(dir.z) - 0.6
		local tr = util.TraceLine({start = P, endpos = P + dir:GetNormalized() * 160, mask = MASK_SOLID_BRUSHONLY})
		if tr.Hit then util.Decal("AlexMercerBlood", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal) end
	end
	sound.Play("mercer/fx/claw_dismember01.wav", P, 80, math.random(95, 105), 1)
	sound.Play("mercer/fx/blood_gush_large_0" .. math.random(3) .. ".wav", P, 75, 100, 0.9)
	sound.Play("mercer/fx/flesh_rip_0" .. math.random(4, 6) .. ".wav", P, 75, 100, 0.8)
end)

hook.Add("EntityRemoved", "AlexMercerGore", function(e) pending[e] = nil end)
-