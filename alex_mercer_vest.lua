- Mercer's jacket, as the game moves it. alex_tod.p3d AlexBodyExpressionMap (engine::TrackedMotionToExpressionMap on
-- alex_reg_body_expressions) drives the vest mesh's vertex offset expressions; the model carries them as flexes
-- (tools/build_all.py VEST_QC): vest_s0..s2 = Vest_Up's three targets at 0.33 / 0.66 / 1.0, vest_s3 = Vest_Right,
-- vest_s4 = Vest_Left. The code below follows the engine's (prototypeenginef.dll, disassembled with tools/re/:
-- MODLOG "JACKET, the engine's code"); the numbers are the file's:
--  per filter, per extractor: value = (the filter's point - his own point) . axis (his own axes); weight =
--  piecewise-linear curve(value) (below the first point = its y); combined into the expression - the first extractor
--  adds, the rest take the max (combine modes 0 add / 1 min / 2 max).
--  1 proto::LinearVelocityNoiseTrackingFilter (axis up, period 2 s, velocity tracked with at most 10 m/s^2): the
--    point = him + axis * noise(speed, t), noise = sum of bands amp * ramp(speed, min, max) *
--    (base + (1 - base) * 0.5 * (sin(2pi * cycles / period * t - pi/2) + 1)):
--    (1-7 m/s, 0.7, base 0.5, 2), (5-10, 0.2, 0.7, 5), (8-15, 0.1, 0, 9). Vest_Up, add, curve (0,0)-(1,0.7)
--  2 engine::SpringBasedLinearMotionFilter (4, 4, 0.3): a = 4 * (him - p) - 4 * v (no overshoot past him in a step),
--    the point never more than 0.3 m from him (0x107fcef0 [+0xc]: pulled in, its velocity = the step taken).
--    Vest_Up, up axis, max, curve (0,0)-(0.3,0.5)
--  3 engine::DampedLinearMotionTrackingFilter (7, 1): the point follows him at 7 m/s at most, never more than 1 m
--    behind. Vest_Up, axis back, max, curve (0,0)-(1,0.25)
--  4 the noise filter on his forward axis: (1-7, 0.5, base 0, 2), (5-10, 0.3, 0, 7), (8-15, 0.2, 0, 11), period 2.
--    Vest_Left and Vest_Right both, max, curve (0,0)-(1,0.5)
--  5 engine::DampedAngularMotionTrackingFilter on Pelvis (0.4, 0.2): its facing follows the pelvis's at 0.4 rad/s
--    at most, never more than 0.2 rad behind. Vest_Left / Vest_Right by the lag's sign, max, curve (0.01,0)-(0.2,1)
local M2U = 39.3701
local FLEX = {"vest_s0", "vest_s1", "vest_s2", "vest_s3", "vest_s4"}
local UP_NOISE = {period = 2, accel = 10, bands = {{1, 7, 0.7, 0.5, 2}, {5, 10, 0.2, 0.7, 5}, {8, 15, 0.1, 0, 9}}}
local SIDE_NOISE = {period = 2, accel = 10, bands = {{1, 7, 0.5, 0, 2}, {5, 10, 0.3, 0, 7}, {8, 15, 0.2, 0, 11}}}

-- the engine's response curve: piecewise linear through the points, flat beyond them
local function curve(x, x0, y0, x1, y1)
	if x <= x0 then return y0 end
	if x >= x1 then return y1 end
	return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
end

-- one noise band (engine 0x100881a0): amp * ramp * (base + (1 - base) * wave)
local function band(b, speed, t, period)
	local mn, mx, amp, base, cycles = b[1], b[2], b[3], b[4], b[5]
	local s = math.Clamp(speed, mn, mx)
	local r = mx > mn and (s - mn) / (mx - mn) or 0
	local f = period > 0 and cycles / period or 0
	local w = 0.5 * (math.sin(6.2832 * f * t - 1.5708) + 1)
	base = math.Clamp(base, 0, 1)
	return (w * (1 - base) + base) * amp * r
end

local function noise(spec, speed, t)
	local n = 0
	for _, b in ipairs(spec.bands) do n = n + band(b, speed, t, spec.period) end
	return n
end

-- the yaw of his pelvis (the hips' line), radians
local function pelvisYaw(ent)
	local l, r = ent:LookupBone("Hip_L"), ent:LookupBone("Hip_R")
	local ml, mr = l and ent:GetBoneMatrix(l), r and ent:GetBoneMatrix(r)
	if not (ml and mr) then return math.rad(ent:GetAngles().y) end
	local d = ml:GetTranslation() - mr:GetTranslation() -- toward his left
	return math.atan2(d.y, d.x) - 1.5708
end

local function wrap(a)
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- (user 2026-10-29: "on a plain run one side of the jacket drops and the other lifts") the hips' line swings every
-- step of the run, so the tracked yaw lagged it and Vest_Left / Vest_Right alternated with the gait. The game's
-- filter follows the character's facing: his heading here (the hips only when alex_mercer_vest_hips 1)
local VestHips = CreateClientConVar("alex_mercer_vest_hips", "0", true, false, "Alex Mercer jacket: the turn from the hips' line (1) or his heading (0)")
local function facingYaw(ent)
	if VestHips:GetBool() then return pelvisYaw(ent) end
	return math.rad(ent:GetAngles().y)
end
-- (user: "it reacts to everything slowly, like snot") the filters' rates as read from the engine x this: the speed
-- tracking's acceleration, the spring, the trailing point's rate, the turn's rate. 1 = the engine's numbers
local VestSpeed = CreateClientConVar("alex_mercer_vest_speed", "2", true, false, "Alex Mercer jacket: how quick it reacts (1 = the game's filters as read, 2 = twice as quick)")

-- (2026-10-30) every form with the jacket (the base, blade, whip, claws, hammer, muscle) rebuilt with the morphs read
-- right; a model without the vest flexes is left alone below (no flex ids)
local function vestThink(ent, dt)
	local ids = ent.MercerVestIds
	if ids == nil or ent.MercerVestMdl ~= ent:GetModel() then
		ent.MercerVestMdl = ent:GetModel()
		ids = {}
		for i, n in ipairs(FLEX) do
			local id = ent:GetFlexIDByName(n)
			if not id then ids = false break end
			ids[i] = id
		end
		ent.MercerVestIds = ids
	end
	if not ids then return end
	local P = ent:GetPos() / M2U
	local st = ent.MercerVestSt
	if not st or not st.v4 or st.P:DistToSqr(P) > 400 then
		st = {v4 = true, P = P, ts = 0, t = 0, sp = P, sv = Vector(), tr = P, yaw = facingYaw(ent),
			w = {0, 0, 0, 0, 0}}
		ent.MercerVestSt = st
	end
	local up, fwd = Vector(0, 0, 1), ent:GetForward()
	-- the tracked velocity (changes at 10 m/s^2 at most); its speed feeds both noise filters
	local vel = (P - st.P) / dt
	st.P = P
	-- (0x100894b0: only the speed is limited, the direction is his at once)
	local K = math.max(VestSpeed:GetFloat(), 0.25)
	local lim = UP_NOISE.accel * K * dt
	local speed = math.Clamp(vel:Length(), st.ts - lim, st.ts + lim)
	st.ts = speed
	st.t = (st.t + dt) % UP_NOISE.period
	-- 1 Vest_Up: the noise point's lift (add)
	local wUp = curve(noise(UP_NOISE, speed, st.t), 0, 0, 1, 0.7)
	-- 2 the spring (max)
	local a = (P - st.sp) * (4 * K * K) - st.sv * (4 * K)
	local need = (P - st.sp) / dt - st.sv -- (no overshoot: never more velocity change than reaches him this step)
	local dvs = a * dt
	if math.abs(dvs.x) > math.abs(need.x) then dvs.x = need.x end
	if math.abs(dvs.y) > math.abs(need.y) then dvs.y = need.y end
	if math.abs(dvs.z) > math.abs(need.z) then dvs.z = need.z end
	local old = st.sp
	st.sp = st.sp + (st.sv + dvs) * dt
	-- never more than 0.3 m from him (the file's third value; the velocity = the step actually taken)
	local off = st.sp - P
	local ol = off:Length()
	if ol > 0.3 then
		st.sp = P + off * (0.3 / ol)
		st.sv = (st.sp - old) / dt
	else
		st.sv = st.sv + dvs
	end
	wUp = math.max(wUp, curve((st.sp - P):Dot(up), 0, 0, 0.3, 0.5))
	-- 3 the trailing point (max): back along his facing
	local d = P - st.tr
	local len = d:Length()
	local step = 7 * K * dt
	if len > step then
		st.tr = st.tr + d * (math.max(step, len - 1) / len)
	else
		st.tr = P
	end
	wUp = math.max(wUp, curve((st.tr - P):Dot(-fwd), 0, 0, 1, 0.25))
	-- 4 both sides: the forward noise (max)
	local wSide = curve(noise(SIDE_NOISE, speed, st.t), 0, 0, 1, 0.5)
	-- 5 the pelvis's turn: its tracked yaw follows at 0.4 rad/s, at most 0.2 rad behind
	local y = facingYaw(ent)
	local lag = wrap(y - st.yaw)
	local mvy = math.min(math.abs(lag), 0.4 * K * dt)
	if math.abs(lag) - mvy > 0.2 then mvy = math.abs(lag) - 0.2 end
	st.yaw = wrap(st.yaw + (lag > 0 and mvy or -mvy))
	-- (2026-10-29, re-read: the engine's angle is about the game's up (y) in a frame with x = his LEFT, so its positive
	-- lag = he turned LEFT -> the data's Vest_Right: the tails swing out to his right, with the inertia. Source's yaw
	-- is positive turning left, the opposite sign - the old script sent a left turn to Vest_Left: "it moves wrong")
	local turn = wrap(y - st.yaw) -- (his facing - the filter's, Source yaw: > 0 = he turned left)
	local wRight = math.max(wSide, curve(turn, 0.01, 0, 0.2, 1))
	local wLeft = math.max(wSide, curve(-turn, 0.01, 0, 0.2, 1))
	-- Vest_Up through its three targets (0.33 / 0.66 / 1.0)
	local s0, s1, s2 = 0, 0, 0
	if wUp <= 0.33 then
		s0 = wUp / 0.33
	elseif wUp <= 0.66 then
		local k = (wUp - 0.33) / 0.33
		s0, s1 = 1 - k, k
	else
		local k = (wUp - 0.66) / 0.34
		s1, s2 = 1 - k, k
	end
	local w = st.w
	w[1], w[2], w[3], w[4], w[5] = s0, s1, s2, wRight, wLeft
end

-- (the server's networked flex weights (all 0) overwrite the client's on every update - the flicker: set right
-- before he is drawn, from ENT:Draw)
function ALEX_MERCER_VEST_APPLY(ent)
	local ids, st = ent.MercerVestIds, ent.MercerVestSt
	if not ids or not st or not st.w or ent.MercerVestMdl ~= ent:GetModel() then return end
	for i = 1, 5 do ent:SetFlexWeight(ids[i], st.w[i]) end
end

-- (user 2026-10-29: "the jacket moving, as the game's") back on; alex_mercer_vest 0 = still (the flexes at rest)
local VestOn = CreateClientConVar("alex_mercer_vest", "1", true, false, "Alex Mercer: the jacket moves as the game's (1) or stays still (0)")
hook.Add("Think", "AlexMercerVest", function()
	local dt = FrameTime()
	if dt <= 0 then return end
	-- (user 2026-10-30, the game's clip: on the sprint the back hem lifts away up and back, the corners swing out) the
	-- "snot" was ours: the morph records are {vertex index, dx, dy, dz} and were read as {dx, dy, dz, w} - the index as
	-- x, the sideways swing as up / down (one flap down, the other up), z lost. Decoded right (tools/build_all.py
	-- vest_morphs) the five targets are the clip's: Vest_Up the hem up 13 cm / back 17 cm and both flaps out 15-17 cm,
	-- Right / Left one side out. On again (alex_mercer_vest)
	local on = VestOn:GetBool()
	for _, ent in ipairs(ents.FindByClass("drg_alex_mercer")) do
		if not on then
			local st = ent.MercerVestSt
			if st and st.w then st.w[1], st.w[2], st.w[3], st.w[4], st.w[5] = 0, 0, 0, 0, 0 end
		elseif not ent:IsDormant() then
			vestThink(ent, dt)
		end
	end
end)
-