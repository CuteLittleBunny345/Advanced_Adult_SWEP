- The game's chase camera for a possessed Alex Mercer (alex_mercer_camera_game: everyone's, no checkbox; 0 from the console = the default camera):
-- proto::ChaseCamera read out of prototypeenginef.dll (build/camera/*.txt), its records = startup_tod.p3d
-- ChaseCamSmoothingData, the hints = the graphs' cameraHint items (tools/camhints.py). The mouse path of the code (input
-- type 3): on any mouse input the engine sets its "last input" time to 1e9, so the stick's auto-elevation, chase drag,
-- occlusion moves, the sprint turn's roll and the jump's own distance never run for a mouse.
--   focus   = his transform (1 m over his feet: Motion_Root, the floor checks' "y - 1"; not a bone, so no bob) + the avatar
--             offset 0.1 m + the stair smoothing + the hold's lift, through a moving average over filterWidth seconds
--   angles  = the mouse's. Only the pitch has limits, per mode; the camera's place stops over the floor, the view tilts on
--   place   = focus - forward x distance, then the collision ray from his head (1.65 m over his feet)
--   view    = the mouse's angles + the look-at leads (toward where he runs; -8 deg in a jump)
--   FOV     = 80 deg at 16:9 (GMod's 64), wider on the sprint and on very high falls
-- By eye / not in the game's data: see the block "NOT the game's" at the end of this comment.
-- Mode 0 ground, 1 jump, 2 climb, 3 wall run, 4 unstable (Slide / Float), 5 grapple, 6 target. State getter 0x103394f0:
-- the record of mode 0 = 0 (1 Running, 2 Parkour), mode 1 by its sub: 0 -> 3, 1 -> 4, 2 -> 5, 3 / 4 -> 4, mode 2 -> 6,
-- 3 -> 7 (8 Parkour), 4 -> 9, 5 -> 10, 6 -> 11.
-- NOT the game's: the pitch limits work on the player's own view angles (CreateMove), the jump's floor limit keeps the view
-- free like the ground's; the threat count takes all NPCs near him while he is in combat (the game: engaged enemies, per
-- class 1 or 10; "big" here by class name); per-enemy camera distances / heights, auto-target without a lock and the
-- Character_Root offset on walls are left out; the near-plane probes are the hull of the old camera (+-8 u, brushes). The devastators'
-- camera animations (dramaticCamera) are not ported.
ALEX_MERCER_CHASECAM = ALEX_MERCER_CHASECAM or {}
local CC = ALEX_MERCER_CHASECAM

local M2U = 39.37
local RAD = math.pi / 180

-- (user 2026-11-04: "что то может подвинуть камеру мерсера вперед, именно вот типа я смотрю вбок, и что то резко внезапно двигает ее в сторону куда смотрит сам мерсер, это очень раздражает, так же и на беге по стенам, тоже очень бесит что он только вперед смотреть может")
-- What turned the view with no mouse here: the look-at leads, the yaw toward where he runs (18 deg at 12 deg/s, looking sideways on the run: that's his "в сторону куда смотрит сам мерсер") and the pitch by the speed; on the wall run the cone,
-- 300 deg/s back to within 75 deg of the wall's normal. All the game's own, the user's word over it: the view turns by the mouse. Still turning it, as scenes: a devastator's cameraReset, a consume's punch-in, the lock's 1.5 s on a new target
local LeadOn = CreateClientConVar("alex_mercer_camera_lead", "0", true, false, "The game camera: 1 = as the game, the view leans toward where he runs (up to 18 deg) and by his speed up and down; 0 = the view is the mouse's", 0, 1)
local WallCone = CreateClientConVar("alex_mercer_camera_wall_cone", "0", true, false, "The game camera: 1 = as the game, on the wall run the view stays within 75 deg of the wall's normal; 0 = free", 0, 1)
-- (user 2026-11-04: "он в верхней части экрана, хотя должен быть примерно по центру", "движения камеры должны быть плавные, но не опаздывающие, и не резкие") WallCenter
local WallCenter = CreateClientConVar("alex_mercer_camera_wall_center", "1", true, false, "The game camera on the wall run: 1 = him in the middle of the frame, no lag; 0 = the record's own moving average, he runs up to the top of the screen", 0, 1)
local Why = CreateClientConVar("alex_mercer_camera_why", "0", false, false, "1 = a line in the chat when the view moves with no mouse, and what moved it", 0, 1)
-- (alex_mercer_lock_game) the lock has the view only in the target mode; then the mouse's, as any
-- (user 2026-11-04, of the rule "the view is the mouse's": "девостаторы не должны были входить в этот список") on a devastator it has it as before: no cameraReset, no pitch limit, alex_mercer_lock.lua steering; MercerDevOn, the server's, from the antic to the fight's end
local function lockHasView(st, lock, ent)
	if not IsValid(lock) then return false end
	local c = GetConVar("alex_mercer_lock_game")
	return st.mode == 6 or (c ~= nil and not c:GetBool()) or ent:GetNW2Bool("MercerDevOn")
end
-- (user 2026-11-04: "кстати помоему при прыжках камера не приближается в игре"; "и еще на рывке в воздухе, и т.д") measured: the one thing that comes in is the moving average's lag: 1.5 m at 20 m/s on the ground, the jump's record has none, so on a takeoff from a run
-- the camera goes 5.5 to 4 m in 0.45 s, and back on landing. That's the game's data; his word beats it, as with the leads. 0 = as the data
local AirKeep = CreateClientConVar("alex_mercer_camera_air_keep", "1", true, false, "The game camera: 1 = the distance a run's lag gave stays through a jump; 0 = as the game's data, it comes in 1.5 m on a takeoff at full speed", 0, 1)
-- (user 2026-11-05: "бег на стене слишком сильно приближает камеру, после чего например если спрыгнуть со стены и полететь, то камера будет близко до тех пор пока ты не приземлишься, ну можно сказать продолжительное время") measured, build/chasecam/camwall.py: 5.50 m and FOV 74 on the sprint; 0.15 s onto the wall 4.05 m, the run's lag gone, the record's 5.5 m comes only through its 2 s filter (4.9 m after 2 s), the sprint's zoom out in 0.7 s: he stands 1.5 x bigger on the screen. Off the wall the jump mode keeps what it had till the landing. The game's data, his word over it. 0 = as the data
local WallKeep = CreateClientConVar("alex_mercer_camera_wall_keep", "1", true, false, "The game camera on the wall run: 1 = as far as on the sprint, its zoom kept, nothing kept close in the flight after it; 0 = as the game's data, it comes in 1.5 m and the zoom goes", 0, 1)
local LagScale = CreateClientConVar("alex_mercer_camera_game_lag", "1", true, false,
	"The game camera: x on the focus's moving average (1 = the game's 0.15 s, 0 = rigid on him)", 0, 1)

-- ChaseCamSmoothingData (metres, degrees, seconds), in the order of the enum: Ground, Ground_Running, Ground_Parkour,
-- Jump_Vertical, Jump_Leap, Jump_Roof, Climb, WallRun, WallRun_Parkour, Unstable, Grapple, Target
local COL = {
	width =    {0.15, 0.15, 0.15, 0, 0, 0, 0.2, 0.15, 0.15, 0, 0.2, 0},
	widthRate = {0.35, 0.35, 0.35, 0.3, 0.3, 0.3, 0.2, 0.35, 0.35, 1, 0.2, 0.35},
	dist =     {4, 4, 4, 6, 6, 4, 4.5, 5.5, 5.5, 4, 4, 6.5},
	distRate = {200, 110, 110, 500, 500, 200, 6, 200, 5, 120, 6, 2},
	distSlow = {0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.5, 0.1, 0.5, 0.25, 0.5, 0.5},
	yaw =      {18, 18, 18, 18, 18, 18, 0, 16, 18, 18, 0, 0},
	yawMax =   {1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0},
	yawRate =  {12, 12, 12, 8, 8, 12, 0, 8, 8, 8, 0, 0},
	yawSlow =  {4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 0, 0},
	pUp =      {0, 0, 0, -8, -8, 0, 0, 15, 15, 0, 0, 0},
	pUpMax =   {0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0},
	pDown =    {0, 0, 0, 8, 8, 0, 0, 0, 0, 0, 0, 0},
	pDownMax = {0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0},
	pRate =    {0, 0, 0, 25, 25, 0, 0, 5, 8, 0, 0, 0},
	pSlow =    {0, 0, 0, 5, 5, 0, 0, 5, 4, 0, 0, 0},
}
local REC = {}
for i = 1, 12 do
	local r = {}
	for k, c in pairs(COL) do r[k] = c[i] end
	REC[i - 1] = r
end
CC.REC = REC

-- the pitch per mode: limits, the rate and the slowing distance toward the target (no rate = at once)
local PITCH = {
	[0] = {-40, 60, 150, 5}, [1] = {-60, 60, 240, 0}, [2] = {-75, 75}, [3] = {-75, 75},
	[4] = {-60, 60}, [5] = {-60, 60}, [6] = {-60, 80, 300, 10},
}

-- the graphs' cameraHint by animation (tools/camhints.py, build/camera/camhints.txt: the anims under a node with the hint)
local function set(s)
	local t = {}
	for w in string.gmatch(s, "%S+") do t[w] = true end
	return t
end
-- Slide and Float: both go to the unstable mode
local UNSTABLE = set[[alex_blades_attack_d alex_breakfall_flip alex_dev_critical_pain_cannonball alex_gethit_air_up
	alex_gethit_body alex_gethit_breakfall_front_backflip alex_gethit_pushback_2 alex_gethit_pushback_s alex_gethit_stagger
	alex_gethit_stagger_2 alex_gethit_stagger_3 alex_grap_hmn_leg_slam2_gv alex_hammer_3hit_combo alex_hammer_air_toss
	alex_hammer_amb_combat alex_hammer_devastator alex_kick_air_straight alex_kick_air_straight_enemy_grind_gv
	alex_kick_air_straight_enemy_impact alex_kick_air_straight_enemy_secondary alex_kick_air_straight_ground_impact
	alex_kick_air_straight_wall_impact alex_kick_dash_attack_contact alex_kick_dash_attack_contact_soft alex_loco_diveroll
	alex_loco_jump_land_stop alex_punch_float_2 alex_weap_1hnd_grab_hmn_gv alex_weap_2hnd_grab_car alex_whip_3hitcombo
	alex_whip_3hitcombo_max alex_whip_sweep alex_whip_sweep_max gethit_lefthand alex_blades_air_attack alex_hammer_air_elbow
	gethit_kd_1 gethit_kd_2]]
local JUMPING = set[[alex_air_punch_axe alex_air_punch_r alex_grap_air_float_gv alex_grap_air_powerbomb_gv alex_grap_air_slam_gv
	alex_loco_grap_jump_b_gv alex_loco_jump_long alex_loco_jump_long_all1 alex_loco_jump_long_all1_end
	alex_loco_jump_long_all1_mid alex_loco_jump_long_all1_start alex_loco_jump_long_all2 alex_loco_jump_long_b
	alex_loco_jump_long_d_back alex_loco_jump_long_flip alex_loco_jump_small_flip]]
local AIRDASH = set[[alex_loco_aerial_dash]]
local GRAPPLE = set[[alex_grap_knee_head_rcv gethit_kd_4 supersol_combat_counter_attack_rcv]]
local PARKOUR = set[[alex_loco_obstacle_jump_a alex_loco_parkour_enter_tuck_jump alex_loco_parkour_hoodslide
	alex_loco_parkour_hoodslide_gv alex_loco_parkour_hurdle alex_loco_parkour_small_basic alex_loco_parkour_small_basic_b
	alex_loco_parkour_step_left alex_loco_parkour_step_right]]

-- punchinCamera, the game's cuts of the consumes and the big blows, by the port's consume name (random among a bank's variants)
-- and by the animation: {timeBegin, timeEnd, inTime, outTime, dolly, zoom, reAim, aim x, y, z}. The aim point is in his frame:
-- x = his left, y = up, z = behind him, from his transform (tools/punchgen.py <- graph_consume). The stealth consumes have
-- dramaticCameras instead: none of them here
local PUNCH_CONSUME = {
	arm_rip = {{{0, 2.1, 0.0667, 0.1667, 1.3, 1.3, 1, 0, 0, 0}, {0.6667, 2.233, 0.1333, 0.3, 1.4, 1.4, 1, 0, 0.3, 0}}},
	chest_punch = {{{0.6667, 1.667, 0.0667, 0.1, 1, 2, 0, 0, 0.6, 0}},
		{{0, 1.667, 0.1, 0.1333, 1.5, 1.5, 1, 0, 0, 0}, {0.3333, 1.667, 0.2, 0.1333, 1.5, 1.5, 1, 0, 0, 0.32}, {0.6667, 1.833, 0.1667, 0.3333, 1.7, 1.7, 1, 0, 0, -0.7}}},
	come_here = {{{0, 2, 0.0667, 0.3333, 1, 1, 1, 0, 0, 0}, {0.2667, 2, 0.3333, 0.3333, 1, 1, 1, 0, 1, -1.5}, {0.9, 2, 0.2, 0.3333, 1, 1, 1, 0, 0.5, -0.8}, {1.167, 2.133, 0.1333, 0.3, 1, 1, 1, 0, 0, 0}}},
	crush_head = {{{0.0667, 2.333, 0.1333, 0.1, 1.8, 1.5, 1, 0, 0.4, -0.4}, {0.5, 2.333, 0.1667, 0.1, 1.8, 1.5, 1, 0, 0.4, -1}, {1.267, 2.5, 0.0667, 0.3333, 2, 2, 1, 0, 0.4, -1}}},
	foot_sweep = {{{0, 1.833, 0.1, 0.1, 1.2, 1.2, 1, 0, -0.3, 0}, {0.3333, 1.833, 0.1667, 0.1, 1.2, 1.2, 1, 0, -0.3, -1}, {0.6, 1.833, 0.3333, 0.1, 1.2, 1.2, 1, 0, 0.7, -0.4}, {1.2, 2, 0.3333, 0.3333, 1.2, 1.2, 1, 0, 0, -0.5}}},
	head_stomp = {{{0, 2.333, 0.1, 0.1667, 1.2, 1.2, 1, 0, 0, -1}, {0.2, 2.333, 0.4, 0.1667, 1.3, 1.3, 1, 0, 0.4, -1}, {0.8333, 2.167, 0.2333, 0.3333, 1.3, 1.3, 1, 0, -0.4, -0.5}},
		{{0, 2.333, 0.3333, 0.1667, 1.3, 1.3, 0, 0, 0.6, 0}, {1, 2.333, 0.0667, 0.2667, 1.4, 1.4, 0, 0, 0.6, 0}}},
	headdrop = {{{0, 2.167, 0.1, 0.1333, 1, 1.7, 1, 0, 0, 0}, {0.3333, 2.167, 0.2, 0.1333, 1, 1.7, 1, 0, 0, 0.3}, {0.5333, 2.167, 0.2, 0.1333, 1, 1.7, 1, 0, 0.4, 0}, {1.067, 2.333, 0.2, 0.3333, 1, 1.7, 1, 0, -0.6, 0}}},
	headsmush = {{{0, 1.667, 0.1, 0.2333, 1.3, 1.3, 1, 0, 0, 0}, {0.5, 1.667, 0.2, 0.2333, 1.35, 1.35, 1, 0, 0, -0.5}}},
	heart_to_head = {{{0, 1.5, 0.0667, 0.2667, 1.3, 1.3, 1, 0, 0, 0}, {0.3333, 1.5, 0.2667, 0.2667, 1.3, 1.3, 1, 0, 0.4, 0}}},
	knee_head = {{{0.4, 1, 0.1333, 0.1, 1.8, 1, 0, 0, 0.6, 0}},
		{{0, 1, 0.1, 0.1, 1.5, 1, 1, 0, 0, 0.3}, {0.2, 1, 0.3333, 0.1, 1.5, 1.3, 1, 0, 0.6, -0.5}, {0.6, 1.167, 0.2333, 0.2667, 1.5, 1.1, 1, 0, 0, -0.5}}},
	lash = {{{0, 1.833, 0.0667, 0.0333, 1, 1, 1, 0, 0, 0}, {0.3333, 1.833, 0.4, 0.0333, 1, 1, 1, 0, 3, 0}, {0.9333, 2, 0.2, 0.3, 1, 1, 1, 0, 0, 0}}},
	readjust = {{{0, 2, 0.1, 0.2, 1.2, 1.2, 1, 0, 0, 0}, {0.3333, 2, 0.0667, 0.2, 1.2, 1.2, 1, 0, 0, -0.3}, {1, 2.067, 0.0667, 0.2667, 1.4, 1.2, 1, 0, 0, -0.3}}},
	readjust_b = {{{0, 1.5, 0.0667, 0.1667, 1, 1.3, 1, 0, 0, 0}, {0.2, 1.5, 0.2667, 0.1667, 1, 1.3, 1, 0, 1, 0}, {0.7333, 1.567, 0.2667, 0.2667, 1, 1.3, 1, 0, -0.7, 0}}},
	smash_throw = {{{0, 1.333, 0.0667, 0.1, 1.2, 1.2, 1, 0, 0, 0}, {0.1, 1.333, 0.5333, 0.1, 1.3, 1.3, 1, 0, 1, 0.5}, {0.6, 1.5, 0.2667, 0.3, 1.3, 1.3, 1, 0.3, -0.7, -0.4}}},
	spin_and_slice = {{{0, 2, 0.1, 0.3333, 1.2, 1.2, 1, 0, 0, 0}, {0.1667, 2, 0.3333, 0.3333, 1.2, 1.2, 1, 0, 0.6, -0.7}, {0.6667, 2, 0.3333, 0.3333, 1.2, 1.2, 1, 0, 0, -0.5}, {0.8333, 2, 0.0667, 0.3333, 1.3, 1.3, 1, 0, 0, -0.5}}},
}
local PUNCH_SEQ = {
	alex_punch_float_charged = {{0, 1, 0, 1, 1.15, 1.15, 0, 0, 0.6, 0}}, -- (uppercut/release)
	alex_special_float_kick = {{0, 1.067, 0.2667, 0.3333, 1.17, 1.17, 0, 0, 0.6, 0}}, -- (special_combo/special)
}
-- the devastators (graph_devastator), from the release that follows the antic alex_dev_charge: the bank {camera}'s variants by their
-- weights, each a punch-in and a cameraReset {timeBegin, "reset", direction x, y, z, blendTime} (the view's direction in his frame,
-- as the aim point's axes). base = the devastator node's start in the release. The variants' dramaticCameras (camera animations) are
-- not ported; here these replace MercerDevCamT's pull, the default camera keeps it
local PUNCH_DEV = {
	alex_dev_groundpound = {base = 0.2667, ground = {
		{10, {{0, 2, 0.5, 0.8333, 0.7, 0.6, 1, 0, 1.5, 0}, {0.2333, "reset", 0.3, -0.1, 0.7, 1}}},
		{7.5, {{0, 2.333, 0.4, 1, 0.8, 0.6, 1, 0, 1.5, 0}, {0.2333, "reset", -0.3, -0.2, -1, 1}}},
		{15, {{0, 2.667, 0.4, 1, 0.6, 0.7, 1, 0, 1.5, 0}, {0.2333, "reset", 0, -0.3, 1, 1}}},
	}},
	alex_dev_whip = {base = 0, ground = {
		{7.5, {{0.1667, 2.667, 0.8333, 1, 0.6, 0.65, 1, 0, 1.5, 0}, {0.2333, "reset", 0, -0.3, -1, 1}}},
		{7.5, {{0, 2.333, 0.4, 1, 0.8, 0.6, 1, 0, 1.5, 0}, {0.2333, "reset", -0.3, -0.2, -1, 1}}},
		{10, {{0.1667, 2.667, 0.4, 1, 0.6, 0.7, 1, 0, 1.5, 0}, {0.4333, "reset", 0, -0.3, 1, 1}}},
		{10, {{0.1667, 3.333, 0.8333, 1.167, 0.6, 0.65, 1, 0, 1.5, 0}, {0.4333, "reset", -0.3, -0.3, -0.6, 1.333}}},
	-- (air: 30 m up and more, absoluteHeight)
	}, air = {{10, {{0.1667, 2.667, 0.8333, 1, 0.6, 0.65, 1, 0, 1.5, 0}}, high = 30}}},
	alex_dev_critical_pain = {base = 0, ground = {{1, {{0.5, 3.667, 0.3333, 0.8333, 1.1, 1.5, 0, 0, 0.6, 0}}}},
		air = {{1, {{0.5, 3.667, 0.3333, 0.5, 0.8, 1.5, 0, 0, 0, 0}}}}},
}
-- (user 2026-11-04: "в воздухе камера не так работает именно со взрывом щупалец, е+пкм") the air's bank {camera} (graph_devastator 1570-1585) references three of the ground's, items 127 - 129, and has the one above from 30 m up: only that one was here, so under 30 m no camera at all, above it never the turn.
-- Its fourth reference, #8d6ba2ea, is item 195: itself, the only such in all the graphs, nothing to play: the ground's first stays out
for i = 2, 4 do PUNCH_DEV.alex_dev_whip.air[i] = PUNCH_DEV.alex_dev_whip.ground[i] end
-- the hammer toss's landing by height (graph_hammerfist exit/land/height: MercerHTossLand's tier over 70, 50, under): high, medium, low
local PUNCH_TOSS = {
	{{0, 1.333, 0.1333, 0.2333, 0.5, 0.9, 1, 0, 0, 0}},
	{{0, 0.9333, 0.1667, 0.2333, 0.65, 0.9, 1, 0, 0, 0}},
	{{0, 0.9333, 0.1, 0.2333, 0.7, 0.9, 1, 0, 0, 0}},
}
local function pickWeighted(list, heightM)
	local total = 0
	for _, v in ipairs(list) do
		if not v.high or heightM >= v.high then total = total + v[1] end
	end
	if total <= 0 then return nil end
	local r = math.random() * total
	for _, v in ipairs(list) do
		if not v.high or heightM >= v.high then
			r = r - v[1]
			if r <= 0 then return v[2] end
		end
	end
	return list[#list][2]
end
-- by the frame of an animation that has more than one node in it: the claws' spike from its release, the hammer toss from its
-- flight
local PUNCH_FRAME = {
	alex_claw_groundspike = {24.5, {{0, 3, 0.2667, 0.9, 0.8, 1.25, 0, 0, 0.6, 0}}},
	alex_hammer_air_toss = {15, {{0, 2.833, 2.167, 0.1667, 1, 0.65, 0, 0, 0.6, 0}}},
}

-- 0x1084cbb0: nearly 1 - exp(-dt / T)
local function kf(dt, T)
	if T == 0 then return 1 end
	local x = dt / T
	return 1 - 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
end
local function filter(cur, target, dt, T)
	return cur + (target - cur) * kf(dt, T)
end
-- 0x103365c0: linear at rate until within slow, then exponential with the time constant slow / rate
local function approach(cur, target, rate, dt, slow)
	local d = target - cur
	if d == 0 or rate == 0 or dt == 0 then return cur end
	local s = d > 0 and 1 or -1
	local over = math.abs(d) - slow
	if over > 0 then
		local tl = over / rate
		if dt <= tl then return cur + s * rate * dt end
		cur = cur + s * over
		dt = dt - tl
	end
	if slow <= 0 then return target end
	return cur + (target - cur) * kf(dt, slow / rate)
end
CC.kf, CC.approach = kf, approach

-- 0x103350b0: the zoom's value: the target's ramp, then the filter (time x 0.167)
local function zoomStep(st, dt, dir)
	if dt <= 0 or dir == 0 then return end
	local time, tgt
	if dir > 0 then time, tgt = st.zUp, st.zHi else time, tgt = st.zDown, 1 end
	local new = tgt
	if time > 0 then
		local step = (st.zHi - 1) / time * dt
		local d = tgt - st.zCur
		if step < math.abs(d) then new = st.zCur + (d > 0 and step or -step) end
	end
	st.zVal = filter(st.zVal, new, dt, time * 0.167)
	st.zCur = new
end

-- the focus's moving average (0x103352d0, kernel 0): newest samples first, the last width seconds, trapezoids
local function boxPush(st, x, y, z, dt)
	local i = st.n % 64 + 1
	st.n = i
	st.bx[i], st.by[i], st.bz[i], st.bt[i] = x, y, z, dt
end
local function boxOut(st, width)
	local i = st.n
	local x1, y1, z1 = st.bx[i], st.by[i], st.bz[i]
	if width <= 0 then return x1, y1, z1 end
	local sx, sy, sz, t = 0, 0, 0, 0
	for _ = 1, 63 do
		local j = (i - 2) % 64 + 1
		local seg, x0 = st.bt[i], st.bx[j]
		if not x0 or seg <= 0 then break end
		local y0, z0 = st.by[j], st.bz[j]
		if t + seg > width then
			local f = (width - t) / seg
			x0, y0, z0 = x1 + (x0 - x1) * f, y1 + (y0 - y1) * f, z1 + (z0 - z1) * f
			seg = width - t
		end
		sx, sy, sz = sx + (x0 + x1) * 0.5 * seg, sy + (y0 + y1) * 0.5 * seg, sz + (z0 + z1) * 0.5 * seg
		t = t + seg
		x1, y1, z1, i = x0, y0, z0, j
		if t >= width then break end
	end
	if t <= 1e-5 then return st.bx[st.n], st.by[st.n], st.bz[st.n] end
	return sx / t, sy / t, sz / t, x1, y1, z1 -- (and where he was, that far back)
end
local function boxReset(st, x, y, z)
	st.n = 0
	st.bx, st.by, st.bz, st.bt = {}, {}, {}, {}
	boxPush(st, x, y, z, 0)
end

-- (user 2026-11-04: "Надо бы камеру чуточку отделить от мерсера, и сделать так чтоб она совсем чуточку могла не успевать за ним, но только при беге, в игре так помогу, при прыжках и
-- делах в воздухе не надо") the DEFAULT camera's pivot, ENT:PossessorView: the same moving average, Ground_Running's numbers (width 0.15 s: he is 0.075 s ahead of the camera, 0.45 m
-- at the run's 6 m/s, 1.5 m at 20 m/s; none in the jump records, its widening and narrowing at widthRate 0.35: 0.43 s). A moving average of the place itself, weighed by the frames'
-- own times: a constant speed gives the same lag at any frame time. BY EYE, not the game's: only on the run and the sprint (the game has it all over the ground, and walking or a
-- strike's lunge stay as they were: the user's "резче" of 2026-11-03), the width eased at both ends so the camera's speed has no corner. Returns the pivot's x, y and how far in
local RunLag = CreateClientConVar("alex_mercer_camera_run_lag", "1", true, false,
	"The default camera on the run and the sprint: x on its lag (1 = the game's 0.075 s, 0 = none, as before 2026-11-04); none in the air", 0, 2)
function CC.RunLag(ent, st, target, dt)
	local strength = RunLag:GetFloat()
	if strength <= 0 then return target.x, target.y, 0 end
	local x, y, z = target.x, target.y, target.z
	if not st.n then
		st.runK = 0
		boxReset(st, x, y, z)
	end
	if math.abs(x - st.bx[st.n]) > 300 or math.abs(y - st.by[st.n]) > 300 then
		boxReset(st, x, y, z) -- a teleport, not a run
	elseif dt > 0 then
		boxPush(st, x, y, z, dt)
	end
	local v = ent:GetVelocity():Length2D() / M2U
	local run = false
	if ent:IsOnGround() and not ent:GetNW2Bool("MercerWall") and v > 2.5 then
		run = ent:GetNW2Float("MercerSprint", 0) > 0
		if not run then
			local name = string.lower(ent:GetSequenceName(ent:GetSequence()) or "")
			run = string.find(name, "run", 1, true) ~= nil or string.find(name, "sprint", 1, true) ~= nil
		end
	end
	local rec = REC[1]
	local step = rec.widthRate / rec.width * dt
	st.runK = math.Clamp(st.runK + (run and step or -step), 0, 1)
	local k = st.runK * st.runK * (3 - 2 * st.runK)
	if k <= 0 then return x, y, 0 end
	local ox, oy = boxOut(st, rec.width * strength * k)
	return ox, oy, k
end

local function newState(ent, ang)
	local o = ent:GetPos()
	local st = {
		mode = 0, sub = 0, count = 0, running = false, parkour = false,
		base = 4, c68 = 4, r = 4, rOut = 4, width = 0.15,
		stepOff = 0, lift = 0, prevZ = o.z + M2U,
		leadY = 0, leadP = 0, extra = 0, camP = math.NormalizeAngle(ang.p),
		zCur = 1, zVal = 1, zUp = 1.67, zDown = 0.67, zHi = 1.2,
		threatT = 0, threatNext = 0, lockT = 0, lockMax = 1.5,
		colHit = false, colDist = 0,
	}
	boxReset(st, o.x, o.y, o.z + 1.1 * M2U)
	return st
end

-- 0x1033a7b0: a change of mode blends the distance (0x103391f0: smoothstep) over the given time
local function setMode(st, mode, blend)
	if st.mode == mode then return end
	st.mode = mode
	st.count = 0
	st.blendT, st.blendLen, st.blendFrom = 0, blend, st.rOut
	if mode == 1 then
		st.r = st.rOut
		st.fallMark = nil -- the high fall's mark (+0xc34)
	end
end

local function seqName(st, ent)
	local i = ent:GetSequence()
	if st.seqI ~= i then
		st.seqI = i
		st.seqN = string.lower(ent:GetSequenceName(i) or "")
	end
	return st.seqN
end

-- the distance's threat (0x103531b0, range 20 m): the sum over the enemies around; 8 and up holds 5.4 m for 2 s after it
local FRIENDLY = {"citizen", "alyx", "barney", "kleiner", "eli", "mossman", "monk", "vortigaunt", "dog", "breen"}
local BIG = {"strider", "gunship", "helicopter", "hunter", "tank", "apc"}
local function nameIn(c, list)
	for _, n in ipairs(list) do
		if string.find(c, n, 1, true) then return true end
	end
	return false
end
local function threatScore(ent, center)
	if CurTime() - ent:GetNW2Float("MercerCombatT", -100) >= 10 then return 0 end
	local s = 0
	for _, e in ipairs(ents.FindInSphere(center, 20 * M2U)) do
		if e ~= ent and (e:IsNPC() or e:IsNextBot()) then
			local c = e:GetClass()
			if not nameIn(c, FRIENDLY) then s = s + (nameIn(c, BIG) and 10 or 1) end
		end
	end
	return s
end

-- one frame of the camera: 0x10343590 -> 0x10342000 -> the mode's function, for a mouse
local TR = {}
-- (user 2026-11-05, youtube AEM-Vuzw8M4: "vfx и камеру пусть чутка подредактируют при буллет дайве") the convar is the entity's, replicated
local function diveVideo()
	local c = GetConVar("alex_mercer_dive_video")
	return c and c:GetBool()
end
local function update(st, ent, ang, dt)
	local pos, vel = ent:GetPos(), ent:GetVelocity()
	-- (multiplayer: the speed of what is drawn, ALEX_MERCER_MPSMOOTH; there the server's steps come ~10 a second. Single player never sets it)
	if ent.MercerSmVel and ent.MercerSmFrame == FrameNumber() then vel = ent.MercerSmVel end
	local ox, oy, oz = pos.x, pos.y, pos.z + M2U -- his transform in the game's sense
	local vz = vel.z / M2U
	local speed = vel:Length() / M2U
	local onGround = ent:IsOnGround()
	local wall, climb = ent:GetNW2Bool("MercerWall"), ent:GetNW2Bool("MercerClimb")
	local name = seqName(st, ent)

	-- the floor: under his feet on the ground, traced in the air (0x10338ce0)
	local floorZ = pos.z
	if not onGround and not wall then
		TR.start, TR.endpos, TR.filter, TR.mask, TR.mins, TR.maxs = Vector(ox, oy, oz), Vector(ox, oy, oz - 16000), ent, MASK_SOLID_BRUSHONLY
		local tr = util.TraceLine(TR)
		floorZ = tr.Hit and tr.HitPos.z or nil
	end
	local noFloor = function(m) return not floorZ or oz - floorZ > m * M2U end

	-- the punch-ins of what he plays: a consume by its name and start time, the blows by the animation's start
	local q
	local cname, ct = ent:GetNW2String("MercerConsumeName", ""), ent:GetNW2Float("MercerConsumeT", 0)
	if ct ~= st.consumeT then
		st.consumeT = ct
		local v = PUNCH_CONSUME[cname]
		if v and CurTime() - ct < 0.5 then q, st.queueT = v[math.random(#v)], ct end
	end
	if name ~= st.punchSeq then
		-- (user 2026-11-04: "если нажать пкм+лкм для девастатора, но не полностью зажать ... слоумо будет и отодвижение камеры тоже, его быть не должно") with critical mass the two buttons go straight into the antic, and let go early the plain
		-- move plays the same alex_dev_groundpound / alex_dev_whip: that took the devastator's punch-in (camera out x 1.4, FOV wide) and cameraReset. Only when the server says the antic ran out (MercerDevGoT; the graph has none of it before
		-- the devastator node). It may come a frame after the sequence
		if st.punchSeq == "alex_dev_charge" and PUNCH_DEV[name] then st.devPend, st.devPendT = PUNCH_DEV[name], CurTime() end
		st.punchSeq, st.punchFrameDone = name, nil
		if PUNCH_SEQ[name] then q, st.queueT = PUNCH_SEQ[name], CurTime() end
	end
	if st.devPend then
		if CurTime() - st.devPendT > 0.3 then
			st.devPend = nil
		elseif CurTime() - ent:GetNW2Float("MercerDevGoT", -10) < 1 then
			local dev = st.devPend
			st.devPend = nil
			local list = onGround and dev.ground or dev.air
			if list then
				local v = pickWeighted(list, floorZ and (pos.z - floorZ) / M2U or 1000)
				if v then q, st.queueT = v, st.devPendT + dev.base end
			end
		end
	end
	local tossT = ent:GetNW2Float("MercerHTossLandT", 0)
	if tossT ~= st.tossT then
		st.tossT = tossT
		local v = PUNCH_TOSS[ent:GetNW2Int("MercerHTossTier", 3)]
		if v and CurTime() - tossT < 0.5 then q, st.queueT = v, tossT end
	end
	local pf = PUNCH_FRAME[name]
	if pf and not st.punchFrameDone and ent:GetCycle() * ent:SequenceDuration(ent:GetSequence()) * 30 >= pf[1] then
		st.punchFrameDone = true
		q, st.queueT = pf[2], CurTime()
	end
	if q then st.queue, st.queueI = q, 1 end
	while st.queue and ALEX_MERCER_PUNCHSET do
		local it = st.queue[st.queueI]
		if not it then
			st.queue = nil
		elseif CurTime() - st.queueT < it[1] then
			break
		else
			if it[2] == "reset" then
				-- cameraReset (0x10359080, 0x1033f810): the view's direction in his frame, turned to at |difference| / blendTime
				local want = (ent:GetForward() * -it[5] - ent:GetRight() * it[3] + Vector(0, 0, it[4])):Angle()
				-- (a lock has the view on a devastator: no turn, and none kept for after it)
				if not (IsValid(ent:GetNW2Entity("MercerLock")) and ent:GetNW2Bool("MercerDevOn")) then
					st.reset = {p = math.Clamp(math.NormalizeAngle(want.p), -60, 60), y = want.y, blend = it[6], input = 0, dev = ent:GetNW2Bool("MercerDevOn")}
				end
			else
				ALEX_MERCER_PUNCHSET(it[2] - it[1], it[3], it[4], it[5], it[6], it[7] == 1, it[8], it[9], it[10])
			end
			st.queueI = st.queueI + 1
		end
	end

	-- the hints as the graphs give them, by what he plays and his state
	st.running = ent:GetNW2Float("MercerSprint", 0) > 0
	st.parkour = PARKOUR[name] or false
	local air = not onGround and not wall
	local glide = ent:GetNW2Bool("MercerGlide")
	local dash = AIRDASH[name]

	-- the target (the lock): the record for 1.5 s from a new target (0.9 s over 11 m/s), then the mouse's camera again
	local lock = ent:GetNW2Entity("MercerLock")
	if IsValid(lock) then
		if st.lockEnt == lock then
			st.lockT = st.lockT + dt
		else
			st.lockEnt, st.lockT, st.lockMax = lock, 0, speed > 11 and 0.9 or 1.5
		end
	else
		st.lockEnt, st.lockT = nil, 0
	end
	local targeted = st.lockEnt ~= nil and st.lockT < st.lockMax

	-- the mode (the hint handler 0x1033eca0, the exits in 0x10343590): nothing moves it out of the target mode
	if targeted then
		if st.mode ~= 6 then setMode(st, 6, 0) end
	elseif st.mode == 6 then
		setMode(st, wall and (climb and 2 or 3) or 0, 0.25)
	else
		if wall then
			setMode(st, climb and 2 or 3, 0.25)
		elseif GRAPPLE[name] then
			setMode(st, 5, 0.25)
		elseif UNSTABLE[name] or ent:GetNW2Bool("MercerSlide") then
			setMode(st, 4, 0.25)
		elseif air then
			if st.mode == 4 or st.mode == 5 then setMode(st, 0, 0.25) end
			if JUMPING[name] or glide or dash or vz > 1 then
				if st.mode ~= 1 then
					local from = st.mode
					setMode(st, 1, 0.25)
					st.sub = from == 3 and not (JUMPING[name] or glide or dash) and 2 or 0
				end
				if glide then st.sub = 4 elseif dash then st.sub = 3 end
			elseif st.mode == 2 or st.mode == 3 then
				setMode(st, 1, 0.25)
				st.sub = 2 -- off a wall: Jump_Roof
			elseif st.mode ~= 1 and noFloor(6) then -- Falling: only with no floor within 5 m under his feet
				setMode(st, 1, 0.25)
				st.sub = 1
			end
		elseif st.mode == 1 then
			st.count = st.count + 1
			if st.count >= 2 then setMode(st, 0, 0.25) end
		elseif st.mode ~= 0 then
			setMode(st, 0, 0.25)
		end
	end
	if st.mode ~= 1 then st.sub = 0 end

	-- the record
	local recI
	if st.mode == 0 then recI = st.parkour and 2 or (st.running and 1 or 0)
	elseif st.mode == 1 then recI = st.sub == 0 and 3 or (st.sub == 2 and 5 or 4)
	elseif st.mode == 2 then recI = 6
	elseif st.mode == 3 then recI = st.parkour and 8 or 7
	elseif st.mode == 4 then recI = 9
	elseif st.mode == 5 then recI = 10
	else recI = 11 end
	local rec = REC[recI]

	-- the stairs: on the ground, walking, a step up or down goes into an offset (up to 0.175 m) that fades in 3 s
	local stepOff = filter(st.stepOff, 0, dt, 3)
	local dz = (oz - st.prevZ) / M2U
	if st.mode == 0 and not st.running and not st.parkour and math.abs(dz) >= dt * 0.5 and dt > 0 then
		stepOff = math.Clamp(stepOff - dz, -0.175, 0.175)
	end
	st.stepOff = stepOff
	st.prevZ = oz

	-- the lift while holding something in both hands: 1 m (filter 1 s)
	local hold2 = ent:GetNW2Bool("MercerObjHold")
	st.lift = filter(st.lift, hold2 and 1 or 0, dt, 1)

	-- the focus: the moving average, its width at the record's rate
	local fx, fy, fz = ox, oy, oz + (0.1 + stepOff + st.lift) * M2U
	local wTarget = rec.width * LagScale:GetFloat()
	local wStep = rec.widthRate * dt
	st.width = st.width + math.Clamp(wTarget - st.width, -wStep, wStep)
	local last = st.n
	if st.bx[last] and (math.abs(fx - st.bx[last]) > 300 or math.abs(fy - st.by[last]) > 300 or math.abs(fz - st.bz[last]) > 300) then
		boxReset(st, fx, fy, fz) -- a teleport, not a run
	elseif dt > 0 then
		boxPush(st, fx, fy, fz, dt)
	end
	local nx, ny, nz = fx, fy, fz
	local ax, ay, az, ox1, oy1, oz1 = boxOut(st, st.width)
	-- (alex_mercer_camera_wall_center) the wall run's record has the average's 0.15 s too: running up at 16 m/s the focus is 1.2 m under him, and the game's own answer, the view's 15 deg lean up the wall, is the mouse's now (alex_mercer_camera_lead):
	-- he's at the top of the screen. So the average's lag is put back: half of what he did over its width, which is the lag exactly at a steady speed and leaves the average's ramp when his speed changes. That term itself through a short
	-- filter, so a jump off the wall steps nothing; in and out of the wall run over 0.4 s, eased: what the camera does then is a smooth catch-up
	local wantK = (st.mode == 3 and WallCenter:GetBool()) and 1 or 0
	st.wallK = approach(st.wallK or 0, wantK, 2.5, dt, 0)
	if st.wallK > 0 or wantK > 0 then
		local kf = dt > 0 and 1 - math.exp(-dt / 0.06) or 0
		local tx, ty, tz = ox1 and (nx - ox1) * 0.5 or 0, oy1 and (ny - oy1) * 0.5 or 0, oz1 and (nz - oz1) * 0.5 or 0
		st.ffx, st.ffy, st.ffz = (st.ffx or 0) + (tx - (st.ffx or 0)) * kf, (st.ffy or 0) + (ty - (st.ffy or 0)) * kf, (st.ffz or 0) + (tz - (st.ffz or 0)) * kf
		local e = st.wallK * st.wallK * (3 - 2 * st.wallK)
		ax, ay, az = ax + st.ffx * e, ay + st.ffy * e, az + st.ffz * e
	else
		st.ffx, st.ffy, st.ffz = nil, nil, nil
	end
	fx, fy, fz = ax, ay, az
	local focus = Vector(fx, fy, fz)

	-- the distance: the record's (in the jump mode by the vertical speed) at its rate, the threat, then a 2 s filter
	local f = 1
	if st.mode == 1 and st.sub ~= 3 then
		local slow = vz > 0 or -vz < 1
		if st.sub == 4 then
			f = slow and 0.75 or (-vz > 12 and 1.18 or 1)
		else
			f = slow and 0.45 or (-vz > 12 and 1.35 or 1)
		end
	end
	st.base = approach(st.base, rec.dist * f, rec.distRate, dt, rec.distSlow)
	if RealTime() >= st.threatNext then
		st.threatNext = RealTime() + 0.25
		st.threat = threatScore(ent, Vector(ox, oy, oz))
	end
	if (st.threat or 0) >= 8 then
		st.threatT = 2
	else
		st.threatT = math.max(0, st.threatT - dt)
	end
	local T = st.base
	if st.threatT > 0 then T = 5.4 elseif hold2 then T = 5 end
	st.c68 = filter(st.c68, T, dt, 2)
	local c6c = st.c68

	-- the mode's own distance: a mouse in the air keeps what it had; grapple and target stay in a band
	if st.mode == 5 then
		local lo, hi = c6c * 0.8, c6c * 1.2
		if st.r < lo then
			st.r = approach(st.r, lo, 120, dt, 1)
		elseif st.r > hi then
			st.r = approach(st.r, hi, 120, dt, 1)
		else
			st.r = approach(st.r, c6c, 5, dt, 1)
		end
	elseif st.mode == 6 then
		st.r = math.Clamp(approach(st.r, c6c, 10, dt, 0.5), c6c * 0.9, c6c * 1.1)
	elseif st.mode ~= 1 then
		st.r = c6c
	end
	local r = st.r
	if st.blendT then
		st.blendT = st.blendT + dt
		if st.blendLen <= 0 or st.blendT >= st.blendLen then
			st.blendT = nil
		else
			local k = st.blendT / st.blendLen
			r = st.blendFrom + (r - st.blendFrom) * k * k * (3 - 2 * k)
		end
	end
	st.rOut = r
	if AirKeep:GetBool() then
		-- (the lag along the view; what's been lost of it since he left the ground stays in the distance. Back on the ground the lag grows again as the hold goes out, 1 m/s: no dip, and no step if he stops)
		-- (user 2026-11-05: "спринт ... стали резкими ... и прыжок снова") on the ground, over a second after a landing, this touches nothing now: as first written it followed the lag all the time, and a turn of the view pumped the distance up to 0.7 m on the run. And what's added is filtered: the lag has every frame's noise in it
		local a = Angle(st.camP, ang.y, 0):Forward()
		local lag = math.max(0, ((nx - fx) * a.x + (ny - fy) * a.y + (nz - fz) * a.z) / M2U)
		-- (alex_mercer_camera_wall_keep) on the wall as in a flight: what the run's lag gave stays, less what the wall's own record has added since, its 5.5 m is the sprint's 4 + 1.5. Off it, in the air, that sum goes on as it is, and on a landing out at 1 m/s
		local onWall = st.mode == 3 and WallKeep:GetBool()
		if st.mode == 1 or onWall then
			st.lagHold = st.lagHold or st.lagRun or lag
			st.holdR = st.holdR or r
			if onWall then st.holdWall = true end
		else
			st.lagRun = lag
			if st.lagHold then
				st.lagHold = approach(st.lagHold, 0, 1, dt, 0)
				if lag >= st.lagHold then st.lagHold, st.holdR, st.holdWall = nil, nil, nil end
			end
		end
		local over = st.holdWall and st.holdR and math.max(0, r - st.holdR) or 0
		st.lagExtra = filter(st.lagExtra or 0, st.lagHold and math.max(0, st.lagHold - lag - over) or 0, dt, 0.05)
		r = r + st.lagExtra
	else
		st.lagHold, st.lagRun, st.lagExtra, st.holdR, st.holdWall = nil, nil, nil, nil, nil
	end

	local rU = r * M2U

	-- the pitch: the mouse's within the mode's limits; under the floor limit the place stops and the view tilts on
	local yaw = ang.y
	local p = math.NormalizeAngle(ang.p)
	local P = PITCH[st.mode]
	local pTarget = math.Clamp(p, P[1], P[2])
	if lockHasView(st, lock, ent) then pTarget = p end -- (alex_mercer_lock.lua steers the view itself)
	local placeP, extraT = pTarget, 0
	if (st.mode == 0 or st.mode == 1 or st.mode == 6) and floorZ then
		local limit = math.deg(math.asin(math.Clamp((floorZ + 0.3 * M2U - fz) / rU, -1, 1)))
		if placeP < limit then placeP, extraT = limit, pTarget - limit end
	end
	if P[3] then st.camP = approach(st.camP, placeP, P[3], dt, P[4]) else st.camP = placeP end
	st.extra = approach(st.extra, extraT, 150, dt, 5)

	-- the look-at leads (0x10342000): the yaw toward where he runs ...
	local camRight = Angle(0, yaw, 0):Right()
	local fwd = ent:GetForward()
	-- (user 2026-11-04: the same) a devastator keeps the leads it had: they start at it, from 0, and go out after it at their own rate
	local lead = LeadOn:GetBool() or ent:GetNW2Bool("MercerDevOn")
	if not lead then
		-- (it goes out in CreateMove, into the player's own angles: what's drawn doesn't move after the devastator. Under a lock it's the lock's view, nothing to hand over)
		if lockHasView(st, lock, ent) then st.leadY = approach(st.leadY, 0, 30, dt, 2) end
	elseif rec.yaw == 0 then
		st.leadY = approach(st.leadY, 0, 30, dt, 2)
	elseif speed > 1 then
		if fwd:Dot(vel) > 0 then
			local a = fwd:Dot(camRight)
			if a ~= 0 then
				local k = math.min(math.abs(a) / rec.yawMax, 1)
				st.leadY = approach(st.leadY, rec.yaw * k * (a > 0 and 1 or -1), rec.yawRate, dt, rec.yawSlow)
			end
		end
	elseif st.yawMoved then
		st.leadY = approach(st.leadY, 0, 30, dt, 2)
	end
	-- ... the pitch by his speed along the camera's up
	if not lead then
		if lockHasView(st, lock, ent) then st.leadP = approach(st.leadP, 0, 30, dt, 2) end
	elseif rec.pUp == 0 and rec.pDown == 0 then
		st.leadP = approach(st.leadP, 0, 30, dt, 2)
	elseif speed > 0 then
		local v = Angle(st.camP, yaw, 0):Up():Dot(vel) / M2U
		local t = 0
		if v > 0 then
			t = v >= rec.pUpMax and rec.pUp or v / rec.pUpMax * rec.pUp
		elseif v < 0 then
			t = -v >= rec.pDownMax and -rec.pDown or v / rec.pDownMax * rec.pDown
		end
		st.leadP = approach(st.leadP, t, rec.pRate, dt, rec.pSlow)
	end

	-- the zoom: the sprint widens to 1.2 in 1.67 s (back in 0.67 s); a very high fall to 1.5 until half way down
	local dir = -1
	if (st.running or st.parkour or (st.mode == 3 and WallKeep:GetBool())) and st.mode ~= 6 then
		st.zUp, st.zDown, st.zHi = 1.67, 0.67, 1.2
		dir = 1
	end
	-- (diveVideo) the video's glide and windup have his body at 43 and 22 % of the frame: FOV 64 at his 4.5 m (28 and 13.5 % at the 1.5 here); the wide view comes with the dive, the fall then within 5 % of the video. Off the frames: 0x1033bb11 has no such gate, the video's flight may simply have passed its half way. Only a glide over 50 m sees the difference
	local wideOff = diveVideo() and (glide or (name == "alex_bullet_smash" and not ent:GetNW2Bool("MercerBulletFall")))
	if st.mode == 1 and st.sub <= 4 and not wideOff then
		if not st.fallMark then
			dir = 0
			if floorZ and noFloor(50) then
				st.zUp, st.zDown, st.zHi = 1.67, 1.67, 1.5
				st.fallMark = (oz + floorZ) * 0.5
				dir = 1
			end
		elseif oz > st.fallMark and noFloor(10) then
			dir = 1
		end
	end
	zoomStep(st, dt, dir)

	-- the place, then the collision ray from his head: a hit comes in at once, the way back is at 5 m/s (2.5 falling)
	local want = focus - Angle(st.camP, yaw, 0):Forward() * rU
	local view = Angle(st.camP + st.extra - st.leadP, yaw - st.leadY, 0)
	-- punchinCamera (0x10343590): the view turns to the aim point by its blend, the place goes to the distance c6c / dolly
	-- from it, before the collision
	if ALEX_MERCER_PUNCHNOW then
		local dolly, _, ra, ax, ay, az = ALEX_MERCER_PUNCHNOW()
		if dolly ~= 1 or ra ~= 0 then
			local aim = Vector(ox, oy, oz) + (ent:GetRight() * -(ax or 0) + Vector(0, 0, ay or 0.6) + fwd * -(az or 0)) * M2U
			if ra ~= 0 then
				local look = want + view:Forward() * rU
				view = (look + (aim - look) * ra - want):Angle()
			end
			if dolly ~= 1 then
				want = aim + (want - aim):GetNormalized() * (c6c * M2U / dolly)
			end
		end
	end
	-- (diveVideo) his body in the video's fall stays 38 - 40 % from the top of the frame: the game's pitch lead, the view about 10 deg further down by the speed. "Only the mouse turns the view": the place goes along the view's up instead, the angles stay the mouse's. 0.22 x half the frame's height at his distance = 11 % of the frame; 25 u: the fall's pose has its middle that much under the entity, on the frame (rendered, build/chasecam/divecam.py's numbers on the real mesh)
	st.diveK = approach(st.diveK or 0, ent:GetNW2Bool("MercerBulletFall") and diveVideo() and 1 or 0, 3, dt, 0)
	if st.diveK > 0 then
		local _, pz = 1, 1
		if ALEX_MERCER_PUNCHNOW then _, pz = ALEX_MERCER_PUNCHNOW() end
		local halfH = want:Distance(Vector(ox, oy, oz)) * math.tan(32 * RAD) * 0.75 * st.zVal / (pz or 1)
		want = want - view:Up() * ((0.22 * halfH + 25) * st.diveK)
	end
	local start = Vector(ox, oy, oz + 0.65 * M2U)
	local center = ent:WorldSpaceCenter()
	TR.start, TR.endpos, TR.filter, TR.mask, TR.mins, TR.maxs = center, start, ent, MASK_SOLID_BRUSHONLY
	local up = util.TraceLine(TR)
	if up.Hit then start = up.HitPos + (center - start):GetNormalized() * 9 end
	TR.start, TR.endpos, TR.mins, TR.maxs = start, want, Vector(-8, -8, -8), Vector(8, 8, 8)
	local tr = util.TraceHull(TR)
	if tr.StartSolid then
		TR.mins, TR.maxs = nil, nil
		tr = util.TraceLine(TR)
	end
	local total = start:Distance(want)
	local free = total * tr.Fraction
	if st.colHit and free > st.colDist then
		free = approach(st.colDist / M2U, free / M2U, (air and vz <= 0) and 2.5 or 5, dt, 0.5) * M2U
	end
	st.colHit = free < total - 0.5
	st.colDist = free
	local place = total > 0 and start + (want - start) * (free / total) or want

	st.focus = focus
	return place, view
end

-- ENT:PossessorView with the convar on. Once a frame: DrGBase may ask more than once
function CC.View(ent, ang)
	local st = ent.MercerChase
	local frame = FrameNumber()
	if st and st.frame == frame then return st.outPos, st.outAng end
	if not st or RealTime() - st.real > 0.5 then
		st = newState(ent, ang)
		ent.MercerChase = st
	end
	st.real, st.frame = RealTime(), frame
	st.yawMoved = st.lastYaw ~= nil and st.lastYaw ~= ang.y
	-- (alex_mercer_camera_why) the view moved and no mouse in the last frames: what did it
	if Why:GetBool() and st.lastYaw and st.lastP then
		local dy, dp = math.AngleDifference(ang.y, st.lastYaw), math.AngleDifference(ang.p, st.lastP)
		if (math.abs(dy) > 0.5 or math.abs(dp) > 0.5) and RealTime() - (st.mouseT or 0) > 0.05 and RealTime() >= (st.whyT or 0) then
			st.whyT = RealTime() + 0.5
			local c = st.mode == 6 and "the lock, 1.5 s on a new target" or st.reset and "a devastator's cameraReset" or st.leadOutT and "the lean a devastator left, handed over: the drawn view stays" or st.whyWall and "the wall run's cone (alex_mercer_camera_wall_cone)"
				or st.whyPitch and "the pitch limit of camera mode " .. st.mode or "not this camera: another addon, or DrGBase's own lock-on (L)"
			chat.AddText(string.format("[alex_mercer] view %+.1f %+.1f deg with no mouse: %s", dy, dp, c))
		end
	end
	st.whyWall, st.whyPitch = nil, nil
	st.lastYaw, st.lastP = ang.y, ang.p
	st.outPos, st.outAng = update(st, ent, ang, FrameTime())
	-- (the server's aim: ENT:MercerAimVector, its PossessorView. A lost message costs nothing, the next one comes)
	if RealTime() >= (st.sendT or 0) and util.NetworkStringToID("alex_mercer_view") ~= 0 then
		st.sendT = RealTime() + 0.1
		net.Start("alex_mercer_view", true)
		net.WriteVector(st.outPos - ent:GetPos())
		net.WriteFloat(math.AngleDifference(st.outAng.p, ang.p))
		net.WriteFloat(math.AngleDifference(st.outAng.y, ang.y))
		net.SendToServer()
	end
	return st.outPos, st.outAng
end

-- the FOV: 80 deg at 16:9 = GMod's 64; 0x10338ff0: fov' = 2 atan(tan(fov / 2) x the zoom), the zoom = its value / the punch's
function CC.Fov(ent, punchZoom)
	local st = ent.MercerChase
	local z = (st and st.zVal or 1) / (punchZoom or 1)
	return 2 * math.deg(math.atan(math.tan(32 * RAD) * z))
end

-- the limits on the player's own view: inside them the mouse is free; past them (2 deg) the pitch comes back at 150 deg/s.
-- On a wall run the camera stays within 75 deg of the wall's normal (the game moves it at once; here at 300 deg/s)
local function possessedMercer()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply.DrG_GetPossessing then return end
	local ent = ply:DrG_GetPossessing()
	if IsValid(ent) and ent:GetClass() == "drg_alex_mercer" then return ent end
end
hook.Add("CreateMove", "alex_mercer_chasecam", function(cmd)
	local ent = possessedMercer()
	if not ent then return end
	local gc = GetConVar("alex_mercer_camera_game")
	local st = ent.MercerChase
	if not gc or not gc:GetBool() or not st or lockHasView(st, ent:GetNW2Entity("MercerLock"), ent) then return end
	local ang = cmd:GetViewAngles()
	local dt = FrameTime()
	local changed = false
	if cmd:GetMouseX() ~= 0 or cmd:GetMouseY() ~= 0 then st.mouseT = RealTime() end
	-- (user 2026-11-04: "после окончания девостатора") the lean a devastator leaves, by the fall (8 deg in the air's Tendril Barrage): the leads are off outside it, so it goes out; at its own rate, into the player's own angles: what's drawn stays where it is, the place alone glides
	if (st.leadY ~= 0 or st.leadP ~= 0) and not LeadOn:GetBool() and not ent:GetNW2Bool("MercerDevOn") then
		local now = RealTime()
		local ldt = st.leadOutT and now - st.leadOutT or dt
		st.leadOutT = now
		local y, p = approach(st.leadY, 0, 30, ldt, 2), approach(st.leadP, 0, 30, ldt, 2)
		if math.abs(y) < 0.01 then y = 0 end
		if math.abs(p) < 0.01 then p = 0 end
		ang.y, ang.p = ang.y - (st.leadY - y), ang.p - (st.leadP - p)
		st.leadY, st.leadP = y, p
		changed = true
	else
		st.leadOutT = nil
	end
	-- cameraReset, the mode 0x1033a940: yaw and pitch at their rates, the last 5 % of a rate slowing; the stick held 0.15 s ends it
	-- (user 2026-11-04: "она будет пытаться дойти до Х даже после окончания девостатора, вот пусть он быстро это сделает, а то он слишком долго делает что то очень простое") three things dragged it. The rate was fixed by the first difference, so what the mouse added took
	-- that much longer at it, a small first turn the slowest. It ran on FrameTime, under the devastator's slow motion a quarter of the clock. And "held" was a delta in every frame: frames without one come between even in a quick turn, the stick's 0.15 s never came.
	-- Now on the clock: over at its blend (and the slowing's 0.25 s) whatever the mouse did, the rate taking in what's left; the mouse within 0.05 s counts as held; and it goes with the devastator
	local r = st.reset
	if r then
		local now = RealTime()
		local rdt = r.last and now - r.last or dt
		r.last, r.t0 = now, r.t0 or now
		if cmd:GetMouseX() ~= 0 or cmd:GetMouseY() ~= 0 then r.mouseT = now end
		if r.mouseT and now - r.mouseT < 0.05 then r.input = r.input + rdt else r.input = 0 end
		if r.input > 0.15 or (r.dev and not ent:GetNW2Bool("MercerDevOn")) then
			st.reset = nil
		else
			local p0, dy = math.NormalizeAngle(ang.p), math.AngleDifference(r.y, ang.y)
			if not r.ry then
				r.ry, r.rp = math.abs(dy) / r.blend, math.abs(r.p - p0) / r.blend
			end
			local left = r.blend - (now - r.t0)
			-- (what's left within 0.25 s at most: a flick at the very end doesn't come back in a snap, and what it leaves stays when the time's up)
			local k = 1 / math.max(left, 0.25)
			ang.y = ang.y + approach(0, dy, math.max(r.ry, math.abs(dy) * k), rdt, r.ry * 0.05)
			ang.p = approach(p0, r.p, math.max(r.rp, math.abs(r.p - p0) * k), rdt, r.rp * 0.05)
			changed = true
			if left < -0.25 or (math.abs(math.AngleDifference(r.y, ang.y)) < 0.1 and math.abs(r.p - ang.p) < 0.1) then st.reset = nil end
		end
	end
	if st.mode == 3 and WallCone:GetBool() then
		local n = ent:GetNW2Vector("MercerWallNormal", vector_origin)
		if n:LengthSqr() > 0.5 then
			local dirC = -ang:Forward()
			local c = math.Clamp(dirC:Dot(n), -1, 1)
			local a = math.deg(math.acos(c))
			if a > 76 and a < 179 then
				local a2 = a - math.min(a - 75, 300 * dt)
				local t = (dirC - n * c):GetNormalized()
				local out = n * math.cos(a2 * RAD) + t * math.sin(a2 * RAD)
				local na = (-out):Angle()
				ang.p, ang.y = na.p, na.y
				changed = true
				st.whyWall = true
			end
		end
	end
	local P = PITCH[st.mode]
	local p = math.NormalizeAngle(ang.p)
	local c = math.Clamp(p, P[1], P[2])
	if c ~= p then
		if math.abs(c - p) > 2 then c = approach(p, c, 150, dt, 0) end
		ang.p = c
		changed = true
		st.whyPitch = true
	end
	if changed then cmd:SetViewAngles(ang) end
end)
-