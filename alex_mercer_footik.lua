- Feet on uneven ground (stairs, kerbs, slopes) = the game's ikSurfaceFixup: on by default (a few attack holds switch
-- it off in their graphs). Client-side two-bone leg IK in a BuildBonePositions callback: the ground under each ankle
-- is traced, the whole body drops so the lower foot reaches its step, and each leg bends (hip + knee) to put its ankle
-- on its own ground. Only planted feet (the anim's ankle near the floor) and only standing - it fades out as he starts
-- moving, never in the air, on a wall, gliding or diving.
-- (v1 let the body drop 22 u and a foot rise 44 u over it: at a ledge the other leg folded to a kneel, and walking up
-- the stairs the walk's own steps got bent - user screenshots 2026-10-04)
-- The game's own setup (art/alex/alex_tod.p3d, proto::IKBehaviour, supporting limb "Ground"): the balance root (joint 1)
-- moves -0.25..0.25 m at 1 m/s; each leg (the skeleton's limb: hip, knee, ankle) -0.375..0.375 m at 2 m/s, its foot
-- turned to the ground's normal by up to pi/8 at pi/2 rad/s; the arms are off on the ground. The knee bends only about
-- its own hinge: in all 634 Alex anims (~28k bent frames a leg) it bends about the knee bone's local X within 0.1 deg,
-- never the other way.
-- (user 2026-10-30, screenshot: in a stance one knee bent backwards - "as in Prototype, never the leg turned the other
-- way") the old solve aimed the knee at the pelvis's forward, signed by his facing: a stance turned far from his facing
-- flipped it, and the shin's own free turn twisted the knee. Now the knee turns only about that hinge, the whole leg
-- then turns about the hip onto the target.
local LEGS = {{"Hip_L", "Knee_L", "Ankle_L", "Ball_L"}, {"Hip_R", "Knee_R", "Ankle_R", "Ball_R"}}
-- (user 2026-10-28, screenshot: a ledge step ~16 u high left one foot hanging - "it should work from that height";
-- the knees now bend over the toes, not inward) 10 / 10 / 12 -> 18: GMod's step height, a kerb / a stair or two.
-- The game's 0.25 m (~10 u) body limit is not used: the user turned the 10 u cap down (2026-10-28)
local REACH_DOWN = 18 -- u: the most the body drops for a lower foot; deeper = over an edge, it hangs
local REACH_UP = 18 -- u: the highest ground a foot is put on
local RAISE_MAX = 18 -- u: the most a foot rises above the dropped body (keeps the leg from folding)
local ANKLE_REST = 5 -- u: the ankle above the floor when standing
local PLANT = 10 -- u above that the foot counts as lifted: no IK on it
-- (user 2026-11-03: "после ударов лкм левая нога чутка под землю проваливается") the anims' own feet under the floor, which
-- the game's fixup keeps on the surface and this file kept at the anim's height: alex_special_mach_breaker, the punches' end,
-- Ball_L 3.7 -> -7.1 cm in one frame (18-25); the backhand -8.9, the claws' combo -8.3, the blade's dash -6.8, ...
-- (tools/footscan.py). A flat foot stands at Ball 4, Ankle 11.5 cm; the plain run and sprint never go under these: any
-- foot on the ground that does is lifted, at any speed
local BALL_MIN, ANKLE_MIN = 1, 3.5 -- u over the ground
local SPEED_FULL, SPEED_OFF = 30, 90 -- u/s: full IK standing, none once he walks
local SMOOTH = 25 -- 1/s (user 2026-10-28: "the feet should catch it at once" - was 12, ~0.25 s to settle)
local TILT_MAX = math.pi / 8 -- the game's surfaceNormalMaxAngle: the foot on a slope
local TILT_RATE = math.pi / 2 -- rad/s, the game's surfaceNormalAngularVelocity
local UP = Vector(0, 0, 1)
-- (2026-10-04 off by default: on a kerb it read as a lunge) on by default again, as the game has it (user 2026-10-30:
-- "включай" - with the game's knee and the feet to the slope it looks right); "alex_mercer_footik 0" turns it off
local Enabled = CreateClientConVar("alex_mercer_footik", "1", true, false,
	"Alex Mercer: feet placed on uneven ground (stairs, kerbs, slopes) while standing", 0, 1)
-- an archived ConVar keeps its saved value whatever the new default: players who had the old default 0 saved get it
-- switched on once (the cookie remembers it, so turning it off later sticks)
if cookie.GetNumber("alex_mercer_footik_on", 0) < 1 then
	cookie.Set("alex_mercer_footik_on", "1")
	Enabled:SetBool(true)
end

local function rotAxis(k, ang)
	-- Rodrigues: the turn by ang (rad) about the unit axis k
	local c, s = math.cos(ang), math.sin(ang)
	local t = 1 - c
	local x, y, z = k.x, k.y, k.z
	return Matrix({
		{t * x * x + c, t * x * y - s * z, t * x * z + s * y, 0},
		{t * x * y + s * z, t * y * y + c, t * y * z - s * x, 0},
		{t * x * z - s * y, t * y * z + s * x, t * z * z + c, 0},
		{0, 0, 0, 1}})
end

local function rotFromTo(a, b)
	-- the turn taking unit vector a onto unit vector b (nil when they are parallel)
	local axis = a:Cross(b)
	local s = axis:Length()
	if s < 1e-6 then return nil end
	return rotAxis(axis * (1 / s), math.atan2(s, a:Dot(b)))
end

-- the turn R (nil = none) about the point c as one transform: p -> c + R (p - c)
local function about(R, c)
	local M = Matrix()
	if R then M:Set(R) end
	M:SetTranslation(c - M * c)
	return M
end

-- the ground's normal as the game takes it: at most TILT_MAX off up
local function tiltOf(n)
	local c = n:Dot(UP)
	if c >= math.cos(TILT_MAX) then return n end
	local side = n - UP * c
	if side:LengthSqr() < 1e-6 then return UP end
	side:Normalize()
	return UP * math.cos(TILT_MAX) + side * math.sin(TILT_MAX)
end

-- unit vector a turned toward unit vector b by at most step (rad)
local function turnToward(a, b, step)
	local ang = math.acos(math.Clamp(a:Dot(b), -1, 1))
	if ang <= step then return b end
	local v = LerpVector(step / ang, a, b)
	v:Normalize()
	return v
end

local function bones(ent)
	local mdl = ent:GetModel()
	-- (a new key: an autorefresh must not pick up the old solve's bone lists on live Mercers)
	local c = ent.MercerIKLegs2
	if c and c.mdl == mdl then return c end
	c = {mdl = mdl, legs = {}}
	local n = ent:GetBoneCount() or 0
	for i, l in ipairs(LEGS) do
		local hip, knee, ankle = ent:LookupBone(l[1]), ent:LookupBone(l[2]), ent:LookupBone(l[3])
		if hip and knee and ankle then
			-- every bone below goes with its part: the ball with the foot, the armour's plates with the thigh / shin
			local leg = {hip = hip, knee = knee, ankle = ankle, ball = ent:LookupBone(l[4]), thigh = {}, shin = {}, foot = {}}
			for b = 0, n - 1 do
				if b ~= knee and b ~= ankle then
					local p = ent:GetBoneParent(b)
					while p and p >= 0 do
						if p == ankle then leg.foot[#leg.foot + 1] = b break end
						if p == knee then leg.shin[#leg.shin + 1] = b break end
						if p == hip then leg.thigh[#leg.thigh + 1] = b break end
						p = ent:GetBoneParent(p)
					end
				end
			end
			c.legs[i] = leg
		end
	end
	if n > 0 then ent.MercerIKLegs2 = c end
	return c
end

-- the game's two-bone IK: the knee turns only about its own hinge (the bone's local X) to make the hip-ankle distance
-- right, then the whole leg turns about the hip onto the target - the knee can't twist or bend backwards. The foot keeps
-- its world turn (plus the slope's tilt)
local function solveLeg(ent, leg, T, tilt)
	local mH, mK, mA = ent:GetBoneMatrix(leg.hip), ent:GetBoneMatrix(leg.knee), ent:GetBoneMatrix(leg.ankle)
	if not (mH and mK and mA) then return end
	local H, K, A = mH:GetTranslation(), mK:GetTranslation(), mA:GetTranslation()
	local u, s = K - H, A - K
	local l1, l2 = u:Length(), s:Length()
	if l1 < 1 or l2 < 1 then return end
	u, s = u * (1 / l1), s * (1 / l2)
	local h = mK:GetForward()
	h:Normalize()
	-- the anim's own bend about the hinge (a knee past straight reads negative) and the bend the distance needs
	local cur = math.atan2(u:Cross(s):Dot(h), u:Dot(s))
	local d = math.Clamp(H:Distance(T), math.abs(l1 - l2) + 0.5, (l1 + l2) * 0.999)
	local want = math.pi - math.acos(math.Clamp((l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2), -1, 1))
	local Mk = about(rotAxis(h, want - cur), K)
	local Mh = about(rotFromTo((Mk * A - H):GetNormalized(), (T - H):GetNormalized()), H)
	local Ms = Mh * Mk
	local Mf = Matrix()
	if tilt then Mf:Set(tilt) end
	Mf:SetTranslation(Ms * A - Mf * A)
	ent:SetBoneMatrix(leg.hip, Mh * mH)
	ent:SetBoneMatrix(leg.knee, Ms * mK)
	ent:SetBoneMatrix(leg.ankle, Mf * mA)
	for part, M in pairs({thigh = Mh, shin = Ms, foot = Mf}) do
		for _, b in ipairs(leg[part]) do
			local m = ent:GetBoneMatrix(b)
			if m then ent:SetBoneMatrix(b, M * m) end
		end
	end
end

local function build(ent, n)
	local st = ent.MercerIK
	local c = bones(ent)
	-- the anim's own ankles, before anything moves (the think traces the ground under them)
	st.ankle, st.ball = st.ankle or {}, st.ball or {}
	for i, leg in pairs(c.legs) do
		local m = ent:GetBoneMatrix(leg.ankle)
		st.ankle[i] = m and m:GetTranslation() or nil
		local mb = leg.ball and ent:GetBoneMatrix(leg.ball)
		st.ball[i] = mb and mb:GetTranslation() or nil
	end
	local w, lw = st.weight or 0, st.liftW or 0
	if w <= 0.01 and lw <= 0.01 then return end
	local full = w > 0.01
	local drop = full and st.drop or 0
	if drop < -0.05 then
		-- the body down (every bone) so the lower foot reaches its step
		local off = Vector(0, 0, drop)
		for i = 0, n - 1 do
			local m = ent:GetBoneMatrix(i)
			if m then
				m:SetTranslation(m:GetTranslation() + off)
				ent:SetBoneMatrix(i, m)
			end
		end
	end
	for i, leg in pairs(c.legs) do
		-- a planted foot goes onto its own ground and turns to its slope; a lifted one (a step of the walk) just moves
		-- with the body
		local A = st.ankle[i]
		local pl = st.plant and st.plant[i] or 0
		local dz = full and Lerp(pl, drop, math.min(st.ground and st.ground[i] or 0, drop + RAISE_MAX)) or 0
		if A and lw > 0.01 then
			local oz, B = ent:GetPos().z, st.ball[i]
			dz = dz + math.max(ANKLE_MIN - (A.z - oz), B and BALL_MIN - (B.z - oz) or 0, 0) * lw
		end
		local nr, tilt = st.nrm and st.nrm[i], nil
		if nr then
			local axis = UP:Cross(nr)
			local s = axis:Length()
			if s > 1e-4 and w * pl > 0.01 then tilt = rotAxis(axis * (1 / s), math.atan2(s, UP:Dot(nr)) * w * pl) end
		end
		if A and (math.abs(dz - drop) > 0.05 or tilt) then
			solveLeg(ent, leg, Vector(A.x, A.y, A.z + dz), tilt)
		end
	end
end

-- the callback calls through this global, so an autorefresh of this file reaches Mercers that already have one
ALEX_MERCER_FOOTIK = {build = build}
local function attach(ent)
	if ent.MercerIKcb or ent.MercerIKOff then return end
	ent.MercerIK = {}
	ent.MercerIKcb = ent:AddCallback("BuildBonePositions", function(e, n)
		if e.MercerIKOff or not e.MercerIK or not ALEX_MERCER_FOOTIK then return end
		local ok, err = pcall(ALEX_MERCER_FOOTIK.build, e, n)
		if not ok then
			e.MercerIKOff = true
			ErrorNoHalt("[alex_mercer] foot IK off: " .. tostring(err) .. "\n")
		end
	end)
end

-- per frame: the ground under each ankle, its slope and the weights (smoothed)
local function think(ent)
	local st = ent.MercerIK
	if not st then return end
	local pos = ent:GetPos()
	local vel = ent:GetVelocity()
	local ground = util.TraceLine({start = pos + Vector(0, 0, 4), endpos = pos - Vector(0, 0, 8), filter = ent,
		mask = MASK_PLAYERSOLID})
	-- (2026-11-04: in the Super Soldier's hands the anim has his feet: the trace knows nothing of who holds him, and the body could drop up to 18 u off its hand)
	local on = ground.Hit and math.abs(vel.z) < 60 and not ent:GetNW2Bool("MercerWall")
		and not ent:GetNW2Bool("MercerGlide") and ent:GetNW2Float("MercerDive", 0) <= 0 and not ent:GetNW2Bool("MercerSeized")
	local speed = vel:Length2D()
	local want = (on and Enabled:GetBool()) and math.Clamp((SPEED_OFF - speed) / (SPEED_OFF - SPEED_FULL), 0, 1) or 0
	local k = math.Clamp(FrameTime() * SMOOTH, 0, 1)
	st.weight = Lerp(k, st.weight or 0, want)
	-- (not a fade out: off the ground the anims' feet go where they like, on a wall the whole body is tilted)
	st.liftW = (on and Enabled:GetBool()) and Lerp(k, st.liftW or 0, 1) or 0
	st.ground, st.plant, st.nrm = st.ground or {0, 0}, st.plant or {0, 0}, st.nrm or {UP, UP}
	local low = 0
	for i = 1, 2 do
		local A = st.ankle and st.ankle[i]
		local g, pl, nr = 0, 0, UP
		if A and want > 0 then
			-- planted = the anim's ankle near the floor
			pl = math.Clamp(1 - ((A.z - pos.z) - ANKLE_REST) / PLANT, 0, 1)
			local tr = util.TraceLine({start = Vector(A.x, A.y, pos.z + REACH_UP + 2), endpos = Vector(A.x, A.y, pos.z - REACH_DOWN - 1),
				filter = ent, mask = MASK_PLAYERSOLID})
			if tr.Hit and not tr.StartSolid then
				g = math.Clamp(tr.HitPos.z - pos.z, -REACH_DOWN, REACH_UP)
				nr = tiltOf(tr.HitNormal)
			else
				pl = 0 -- over an edge (or inside something): that foot hangs as the anim has it
			end
		end
		st.ground[i] = Lerp(k, st.ground[i], g * st.weight)
		st.plant[i] = Lerp(k, st.plant[i], pl)
		st.nrm[i] = turnToward(st.nrm[i], nr, TILT_RATE * FrameTime())
		-- the body drops for the lower planted foot
		low = math.min(low, st.ground[i] * st.plant[i])
	end
	st.drop = math.max(low, -REACH_DOWN)
end

hook.Add("Think", "AlexMercerFootIK", function()
	for _, ent in ipairs(ents.FindByClass("drg_alex_mercer")) do
		if not ent:IsDormant() then
			attach(ent)
			if not ent.MercerIKOff then
				local ok, err = pcall(think, ent)
				if not ok then
					ent.MercerIKOff = true
					ErrorNoHalt("[alex_mercer] foot IK off: " .. tostring(err) .. "\n")
				end
			end
		end
	end
end)
-