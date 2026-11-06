- Whipfist whip, client side (prototype_whipfist + the game's char_alex_whipfist shader).
-- The whip is a chain of segment points. While an attack node runs stuff/animated_whipfist (whipFistAnimated +
-- whipFistSegmentFixToJoint 0..5 -> Whip_Link_01..06) the points sit on the animation's Whip_Link joints;
-- whipFistExtend (the longshot) grows it procedurally (velocity, distance, a travelling wave with a corkscrew) with
-- the arm's whip spike (Whip_Spike_Top and its claw: the longshot's hit joint) riding at the tip; whipFistRetract
-- reels it back into the hand at its velocity (30 m/s after the combo, 100 m/s after the longshot).
-- Drawn the way the game's vertex shader does it: Whipfist_Segment_A bent along the Catmull-Rom spline through the
-- points (followSpline3), framed by the up vector (CalcFrenetFrame), thickness tapering to the tip - here the bones
-- of the rope model (tools/whiprope.py: 32 segments x 3 bones) are put on that spline every frame.
-- Server state (drg_alex_mercer.lua): NW2Int MercerWhip 0 = reel in (MercerWhipReel m/s) / 1 = animated /
-- 2 = extend (MercerWhipT0, MercerWhipSpeed u/s, MercerWhipMax u, NW2Vector MercerWhipDir; once blocked or at its
-- end MercerWhipStop = that time and NW2Vector MercerWhipTip = where the tip stopped).
ALEX_MERCER_WHIP = ALEX_MERCER_WHIP or {}
local W = ALEX_MERCER_WHIP

local ROPE = "models/mercer/alex_whip_rope.mdl"
local SPANS, PER = 32, 3
local NB = SPANS * PER + 1
local M2U = 39.3701
local LINKS = {"Whip_Link_01", "Whip_Link_02", "Whip_Link_03", "Whip_Link_04", "Whip_Link_05", "Whip_Link_06"}
-- point0.w at the base, point0.w + point1.w at the tip (set by the game's code, not stored in the data)
local THICK_BASE, THICK_TIP = 1, 0.45
-- where the whip leaves the hand: Link_01 sits ~0.5 m out along Wrist_R's +y in the attack anims
local ANCHOR = Vector(0, 20, 0)
-- whipFistExtend (store shared): waveSpeed 20, waveLength 8, waveAmplitude 0.5 (m), ramp up / down 0.2 s,
-- corkscrewAngle 90, corkscrewRotationSpeed 90 (deg/s), corkscrewTravelingSpeed 3
local WAVE_SPEED, WAVE_LEN, WAVE_AMP, RAMP = 20 * M2U, 8 * M2U, 0.5 * M2U, 0.2
local CORK_ANGLE, CORK_ROT, CORK_TRAVEL = math.rad(90), math.rad(90), 3
local UP = Vector(0, 0, 1)

W.SPANS, W.PER, W.NB = SPANS, PER, NB

local function boneMatrix(ent, name)
	local b = ent:LookupBone(name)
	return b and ent:GetBoneMatrix(b)
end

-- the hand end of the whip
function W.Anchor(ent)
	local m = boneMatrix(ent, "Wrist_R")
	if not m then return ent:WorldSpaceCenter() + ent:GetForward() * 20 end
	return m * ANCHOR
end

-- followSpline3 (Catmull-Rom, the shader's own weights)
local function spline(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * 3
	return p0 * (((-t + 2) * t - 1) * t / 2) + p1 * (((t3 - 5) * t2 + 2) / 2) + p2 * (((-t3 + 4) * t + 1) * t / 2)
		+ p3 * (((t - 1) * t2) / 2)
end
W.Spline = spline

local function frame(p, t, up, s)
	-- CalcFrenetFrame: binormal = cross(tangent, up), normal = cross(binormal, tangent). The game's axes are mirrored
	-- (left-handed), the rope's bind has the binormal side on +y: y = cross(up, t), z = cross(t, y)
	local y = up:Cross(t)
	y:Normalize()
	local z = t:Cross(y)
	local m = Matrix()
	m:SetUnpacked(t.x * s, y.x * s, z.x * s, p.x,
		t.y * s, y.y * s, z.y * s, p.y,
		t.z * s, y.z * s, z.z * s, p.z,
		0, 0, 0, 1)
	return m
end

-- bone matrices (index 0 = rope_root, j + 1 = w%03d j) for the whip through pts (world)
function W.Matrices(pts, fallbackUp)
	local n = #pts
	local mats = {}
	mats[0] = Matrix()
	mats[0]:SetTranslation(pts[1])
	local lastT = pts[n] - pts[n - 1]
	if lastT:LengthSqr() < 1e-6 then lastT = fallbackUp or Vector(1, 0, 0) end
	lastT:Normalize()
	local prevT
	for j = 0, NB - 1 do
		local g = j / PER
		if g > n - 1 + 1e-6 then
			-- past the whip's end: collapsed into the tip
			mats[j + 1] = frame(pts[n], lastT, math.abs(lastT.z) > 0.95 and (fallbackUp or Vector(1, 0, 0)) or UP, 0.001)
		else
			local k = math.min(math.floor(g), n - 2)
			local t = g - k
			local p1, p2 = pts[k + 1], pts[k + 2]
			local p0 = pts[k] or (p1 * 2 - p2)
			local p3 = pts[k + 3] or (p2 * 2 - p1)
			local p = spline(p0, p1, p2, p3, t)
			local tan = spline(p0, p1, p2, p3, t + 0.01) - p
			if tan:LengthSqr() < 1e-8 then tan = prevT or (p2 - p1) end
			if tan:LengthSqr() < 1e-8 then tan = lastT end
			tan = tan:GetNormalized()
			prevT = tan
			local up = math.abs(tan.z) > 0.95 and (fallbackUp or Vector(1, 0, 0)) or UP
			local s = Lerp(g / math.max(n - 1, 1), THICK_BASE, THICK_TIP)
			mats[j + 1] = frame(p, tan, up, s)
		end
	end
	return mats
end

-- the extending whip (whipFistExtend): straight from the hand toward the shot's direction, a travelling wave and a
-- corkscrew on it, ramped in from the start and out once it stops; points every metre (the game adds segments as it
-- grows)
function W.ShotPoints(base, dir, L, tau, stopAge, tip)
	if tip then
		dir = tip - base
		L = dir:Length()
		if L < 1 then return {base, base + Vector(0, 0, 1)} end
		dir = dir / L
	end
	local amp = WAVE_AMP * math.Clamp(tau / RAMP, 0, 1)
	if stopAge then amp = amp * (1 - math.Clamp(stopAge / RAMP, 0, 1)) end
	local n = math.Clamp(math.ceil(L / M2U) + 1, 2, SPANS + 1)
	local e1 = dir:Cross(UP)
	if e1:LengthSqr() < 0.01 then e1 = dir:Cross(Vector(1, 0, 0)) end
	e1:Normalize()
	local e2 = dir:Cross(e1)
	local pts = {}
	for i = 1, n do
		local s = L * (i - 1) / (n - 1)
		local u = L > 0 and s / L or 0
		local env = 4 * u * (1 - u)
		local ph = 2 * math.pi * (s - WAVE_SPEED * tau) / WAVE_LEN
		local th = CORK_ANGLE * (s / M2U) / CORK_TRAVEL + CORK_ROT * tau
		pts[i] = base + dir * s + (e1 * math.cos(th) + e2 * math.sin(th)) * (amp * env * math.sin(ph))
	end
	return pts
end

-- whipFistRetract: reel the whip into the hand by d along its own length (it keeps its shape, the base follows the
-- hand); nil once it is all in
function W.Reel(pts, anchor, d)
	if not pts or #pts < 2 then return nil end
	local chain = {anchor}
	for i = 2, #pts do chain[i] = pts[i] end
	local cum = {0}
	for i = 2, #chain do cum[i] = cum[i - 1] + chain[i]:Distance(chain[i - 1]) end
	local function at(s)
		for i = 2, #chain do
			if cum[i] >= s then
				local seg = cum[i] - cum[i - 1]
				return LerpVector(seg > 0 and (s - cum[i - 1]) / seg or 1, chain[i - 1], chain[i])
			end
		end
		return chain[#chain]
	end
	local out = {anchor}
	for i = 2, #chain do
		local s = cum[i] - d
		if s > 1 then out[#out + 1] = at(s) end
	end
	if #out < 2 then return nil end
	return out
end

function W.Rope()
	if IsValid(W.rope) then return W.rope end
	local e = ClientsideModel(ROPE, RENDERGROUP_OPAQUE)
	if not IsValid(e) then return end
	e:SetNoDraw(true)
	e:SetRenderBounds(Vector(-1600, -1600, -1600), Vector(1600, 1600, 1600))
	e.MercerIds = {}
	for j = 0, NB do
		local id = e:LookupBone(j == 0 and "rope_root" or string.format("w%03d", j - 1))
		e.MercerIds[j] = id
	end
	e:AddCallback("BuildBonePositions", function(r, nb)
		local mats = r.MercerMats
		if not mats then return end
		for j, id in pairs(r.MercerIds) do
			if id and mats[j] and id < nb then r:SetBoneMatrix(id, mats[j]) end
		end
	end)
	W.rope = e
	return e
end

-- the whip spike (Whip_Spike_Top + its claw) carried at the tip of the extending whip
local function spikeBones(ent)
	-- bone ids differ between the whip models (with / without the armour): per model
	local mdl = ent:GetModel()
	if ent.MercerSpikeBones and ent.MercerSpikeModel == mdl then return ent.MercerSpikeBones end
	ent.MercerSpikeBones, ent.MercerSpikeModel = nil, mdl
	local root = ent:LookupBone("Whip_Spike_Top")
	if not root then return end
	local list, i = {root}, 1
	while list[i] do
		for _, c in ipairs(ent:GetChildBones(list[i]) or {}) do list[#list + 1] = c end
		i = i + 1
	end
	ent.MercerSpikeBones = list
	return list
end

function W.SpikeBones(ent)
	local st = ent.MercerWhipCl
	if not st or not st.spikeTip then return end
	local list = spikeBones(ent)
	if not list then return end
	local ms = ent:GetBoneMatrix(list[1])
	local wb = ent:LookupBone("Whip_Wrist_R")
	local mw = wb and ent:GetBoneMatrix(wb)
	if not ms or not mw then return end
	local a = mw:GetTranslation() - ms:GetTranslation()
	if a:LengthSqr() < 1e-4 then return end
	local ma, mb = Matrix(), Matrix()
	ma:SetAngles(a:Angle())
	mb:SetAngles(st.spikeDir:Angle())
	local D = Matrix()
	D:SetTranslation(st.spikeTip)
	D = D * mb * ma:GetInverseTR()
	local back = Matrix()
	back:SetTranslation(-ms:GetTranslation())
	D = D * back
	for _, b in ipairs(list) do
		local m = ent:GetBoneMatrix(b)
		if m then ent:SetBoneMatrix(b, D * m) end
	end
end

-- after Mercer's DrawModel (the bones are this frame's): update the whip and draw it
function W.Draw(ent)
	local st = ent.MercerWhipCl
	if not st then
		st = {}
		ent.MercerWhipCl = st
		ent:AddCallback("BuildBonePositions", function(e) W.SpikeBones(e) end)
	end
	local now = CurTime()
	local dt = math.Clamp(now - (st.t or now), 0, 0.1)
	st.t = now
	local form = ent.GetMercerForm and ent:GetMercerForm()
	if not form or form.name ~= "Хлыст" then
		st.pts, st.spikeTip = nil, nil
		return
	end
	local mode = ent:GetNW2Int("MercerWhip", 0)
	local anchor = W.Anchor(ent)
	if mode == 1 then
		local pts = {}
		for i, nm in ipairs(LINKS) do
			local m = boneMatrix(ent, nm)
			if not m then pts = nil break end
			pts[i] = m:GetTranslation()
		end
		-- (WhipFistPower names Whip_Spike_Top as the whip's tip joint: the spike and its claw ride the end of the whip in
		-- every mode, the anims leave it at the wrist)
		st.pts, st.spike = pts, pts and true or nil
	elseif mode == 2 then
		local t0 = ent:GetNW2Float("MercerWhipT0", now)
		local stop = ent:GetNW2Float("MercerWhipStop", 0)
		local tau = math.max(0, now - t0)
		local dir = ent:GetNW2Vector("MercerWhipDir", ent:GetForward())
		local L = math.min(ent:GetNW2Float("MercerWhipMax", 15 * M2U), ent:GetNW2Float("MercerWhipSpeed", 45 * M2U) * tau)
		local stopped = stop > 0 and now >= stop
		st.pts = W.ShotPoints(anchor, dir, L, tau, stopped and now - stop or nil,
			stopped and ent:GetNW2Vector("MercerWhipTip", anchor + dir * L) or nil)
		st.spike = true
	else
		st.pts = W.Reel(st.pts, anchor, ent:GetNW2Float("MercerWhipReel", 30) * M2U * dt)
		if not st.pts then st.spike = nil end
	end
	if st.spike and st.pts then
		local n = #st.pts
		local d = st.pts[n] - st.pts[n - 1]
		if d:LengthSqr() < 1e-4 then d = ent:GetForward() end
		st.spikeTip, st.spikeDir = st.pts[n], d:GetNormalized()
	else
		st.spikeTip = nil
	end
	local pts = st.pts
	if not pts or #pts < 2 then return end
	local rope = W.Rope()
	if not IsValid(rope) then return end
	rope.MercerMats = W.Matrices(pts, ent:GetForward())
	rope:SetPos(pts[1])
	rope:InvalidateBoneCache()
	rope:SetupBones()
	rope:DrawModel()
end
-