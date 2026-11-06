- (user 2026-10-29) the game's Senses powers (startup_fig: HUD_TRANSFORM_SLOT "Senses" - ThermalVision, InfectedVision):
-- wheel nodes 5 / 6 or 9 / 0 while playing as him, the same again = off. Client only (a look).
-- (user: "not it at all - take it from the game") the game's own pipeline, rebuilt with custom screenspace pixel shaders
-- (shaders/fxc/alex_mercer_v*_ps20b.vcs, source in the tools' shaders_src, built by tools/build_shaders.py):
--   1. heat buffer: every warm body drawn flat into a render target - r = heat, g = heat * facing the camera (the game's
--      CurrentBuffer x / y), b = the infected / military (the game's Mother buffer)
--   2. alex_mercer_vacc (pp_thermal + pp_mother): the previous result through a drifting noise offset, carried over
--      (thermal PrevBufferStrength 0.169, infected 0.72 - per game frame, 30 fps), NormalMix 0.349
--   3. alex_mercer_vthermal (pp_combined_thermal + the HeatFalloff ramp) / alex_mercer_vinfected (pp_combined_mother)
-- The thermal distance fade (fadeColour (0.09, 0.22, 0.44), startFade 30 m, fadeRange 70 m, minFade 0.2) is the engine
-- fog: the frame buffer's depth only reaches 192 units.
-- alex_mercer_vision_shaders 0 = the old look without custom shaders (colour modify, fog, the bodies drawn over).
local M2U = 39.37
local REV = "r8" -- the shaders' build (tools/build_shaders.py writes this line)
-- (user screenshots 2026-10-29: the bodies flat yellow, the game's are orange with their texture showing through) a
-- body's heat: at 1 the ramp is all HottestColour; the game's characters sit round 0.7 (HotColour with some yellow)
local BODY_HEAT = 0.6 -- (0.7 still came out yellow next to the game's orange)
-- (user 2026-10-30, the game's clip: in the infected vision a target is a WHITE body with its detail showing and a thin
-- orange rim) the level the infected / military are drawn at: the trail pass reads the heat buffer sRGB-decoded
-- (written v -> read v^2.2), so 0.73 here is ~0.5 in the shaders - the level their trail starts from
local INFECTED_DRAW = 0.73
-- (user 2026-10-30, a P1 screenshot: "the effects must not be over the creatures - behind them, as an outline, and they
-- themselves as on the screenshot") the body itself is shown at its own level, none of the trail over it: 0.85 in the
-- game's combine is its grey jacket with the detail and the pale skin (at 0.5 it washed white, at 1 it went dark). The
-- glow only outside it: this level by the body (white), orange, out to nothing at INFECTED_GLOW px at 1080p (the width
-- by eye against the game's frames)
local INFECTED_BODY, INFECTED_EDGE, INFECTED_GLOW = 0.85, 0.6, 20
-- (user: "see them through walls with the thermal vision") behind a wall: this share of the heat
local HIDDEN_HEAT = 0.6
local USE_SHADERS = CreateClientConVar("alex_mercer_vision_shaders", "1", true, false,
	"Alex Mercer vision: 1 = the game's shaders, 0 = the simple look without them")

local mode -- nil / "thermal" / "infected"

local function possessedMercer()
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply.DrG_GetPossessing then return end
	local ent = ply:DrG_GetPossessing()
	if IsValid(ent) and ent:GetClass() == "drg_alex_mercer" then return ent end
end

function ALEX_MERCER_VISION_MODE() return mode end

-- (the vision's sound loop is kept by its own watchdog below, AlexMercerVisionLoop: it follows the mode)
local function setMode(m)
	mode = m
end

-- (user 2026-10-29: "as in the game") the switch goes through the server (ENT:MercerSenses, the graph's senses node:
-- standing still, the vision comes on 2.4 s into its transformation anim, with its sounds); the answer sets the mode
-- (user 2026-10-29: "a bass boost on the select sound") the wheel played ui_hud_power_select and the server's quick
-- answer played it again a tick later - two copies of one sound. Whoever asks plays the HUD sound at once (played =
-- true) and the answer stays quiet for a second
local quietUntil, pendingUntil = 0, 0
-- (user 2026-10-29: "9 / 0 pressed several times - once, not stacked") one request at a time: the next counts only
-- once the server answered (at once, or at 2.4 s for the transformation; 4 s at most). Returns whether it was sent
function ALEX_MERCER_VISION_TOGGLE(want)
	if not possessedMercer() or RealTime() < pendingUntil then return false end
	pendingUntil = RealTime() + 4
	local on = mode ~= want
	surface.PlaySound(on and "mercer/fx/ui_hud_power_select_04.wav" or "mercer/fx/ui_hud_power_deselect.wav")
	quietUntil = RealTime() + 1
	net.Start("alex_mercer_senses")
	net.WriteString(want)
	net.WriteBool(on)
	net.SendToServer()
	return true
end
net.Receive("alex_mercer_senses", function()
	local want, on, long = net.ReadString(), net.ReadBool(), net.ReadBool()
	pendingUntil = 0
	setMode(on and want or nil)
	-- the quick switch's whoosh (the node's own cues cover the long one)
	-- (user 2026-10-29) the HUD's ui_hud_power_select / _deselect, as on the wheel and the number keys
	if not long and RealTime() > quietUntil then
		surface.PlaySound(mode and "mercer/fx/ui_hud_power_select_04.wav" or "mercer/fx/ui_hud_power_deselect.wav")
	end
end)

-- who is warm (thermal) / who shows up (infected vision: "easy to pick out military units and Infected")
local INFECTED = {npc_zombie = true, npc_fastzombie = true, npc_poisonzombie = true, npc_zombine = true,
	npc_zombie_torso = true, npc_fastzombie_torso = true, npc_headcrab = true, npc_headcrab_fast = true,
	npc_headcrab_black = true, npc_headcrab_poison = true}
local MILITARY = {npc_combine_s = true, npc_metropolice = true}
local TARGET_FACTIONS = {FACTION_ZOMBIES = true, FACTION_INFECTED = true, FACTION_COMBINE = true,
	FACTION_BLACKWATCH = true, FACTION_MILITARY = true}
-- (user 2026-10-29: "Mercer himself should glow in the infected vision too, I think") on by default - his own
-- wish, the game's data says nothing about it either way
local SELF_GLOW = CreateClientConVar("alex_mercer_vision_self", "1", true, false,
	"Alex Mercer infected vision: 1 = Alex himself glows like the infected, 0 = only others")
local function isTarget(e)
	if e == possessedMercer() then return SELF_GLOW:GetBool() end
	local c = e:GetClass()
	-- (user 2026-10-29: "he sees himself but not another Mercer") any other Alex (or one built on him) is infected too
	if c == "drg_alex_mercer" or (scripted_ents.IsBasedOn and scripted_ents.IsBasedOn(c, "drg_alex_mercer")) then
		return true
	end
	if INFECTED[c] or MILITARY[c] or string.StartWith(c, "drg_proto_") then return true end
	local f = e.Factions
	if type(f) ~= "table" then return false end
	for _, n in pairs(f) do
		if TARGET_FACTIONS[n] then return true end
	end
	return false
end
local function isWarm(e)
	if e:IsPlayer() then return e:Alive() and (e ~= LocalPlayer() or LocalPlayer():ShouldDrawLocalPlayer()) end
	return e:IsNPC() or e:IsNextBot() or e:IsRagdoll()
end
-- a body cools over the half minute after death
local function heatOf(e)
	if not e:IsRagdoll() then return BODY_HEAT end
	e.MercerHeatT0 = e.MercerHeatT0 or CurTime()
	return BODY_HEAT * math.Clamp(1 - (CurTime() - e.MercerHeatT0) / 30, 0, 1)
end

local function collect()
	local out = {}
	for _, e in ipairs(ents.FindInSphere(EyePos(), 250 * M2U)) do
		if IsValid(e) and not e:GetNoDraw() and (isWarm(e) or isTarget(e)) then out[#out + 1] = e end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- the shader pipeline
local rtHeat, rtAcc, mats
local function setup()
	if mats then return mats ~= false end
	local flags = 1 + 256 + 4 + 8 -- point sampling, no mips, clamp s / t
	rtHeat = GetRenderTargetEx("alex_mercer_vheat", ScrW(), ScrH(), RT_SIZE_FULL_FRAME_BUFFER, MATERIAL_RT_DEPTH_SHARED,
		flags, 0, IMAGE_FORMAT_RGBA8888)
	-- (user: a quarter-size buffer made the bodies blocky - 4x4 px steps - back to full size; the soft rim is the
	-- thermal shader's glow)
	rtAcc = {
		GetRenderTargetEx("alex_mercer_vaccf0", ScrW(), ScrH(), RT_SIZE_FULL_FRAME_BUFFER, MATERIAL_RT_DEPTH_NONE, flags, 0,
			IMAGE_FORMAT_RGBA8888),
		GetRenderTargetEx("alex_mercer_vaccf1", ScrW(), ScrH(), RT_SIZE_FULL_FRAME_BUFFER, MATERIAL_RT_DEPTH_NONE, flags, 0,
			IMAGE_FORMAT_RGBA8888)}
	local noise = Material("alex_mercer/vision/noise2.png", "noclamp smooth"):GetTexture("$basetexture")
	-- (the shaders' build tag in both names: GMod keeps a loaded shader and CreateMaterial hands back the cached material
	-- under an old name - tools/build_shaders.py sets REV)
	local function ss(name, base, extra, tag)
		local kv = {
			["$pixshader"] = name .. "_" .. REV .. "_ps20", ["$basetexture"] = base, ["$texture1"] = "", ["$texture2"] = "",
			-- (GMod's screenspace_general has no $x360appchooser (TF2's): its own $vertextransform - without it
			-- render.DrawScreenQuad's quad skipped the projection and slid off to the top right, one texel stretched over it)
			["$texture3"] = "", ["$vertextransform"] = 1, ["$ignorez"] = 1, ["$copyalpha"] = 0,
			["$alpha_blend_color_overlay"] = 0, ["$alpha_blend"] = 0, ["$linearwrite"] = 0,
			["$linearread_basetexture"] = 0, ["$linearread_texture1"] = 0, ["$linearread_texture2"] = 0,
			["$linearread_texture3"] = 0}
		for k, v in pairs(extra or {}) do kv[k] = v end
		local m = CreateMaterial(name .. "_" .. REV .. (tag or "") .. "_m", "screenspace_general", kv)
		if noise then m:SetTexture("$texture2", noise) end
		return m
	end
	-- (user 2026-10-30, the game's clip: "the silhouette stays on him in the game, ours slides off") screenspace_general
	-- reads a texture with sRGB decoding unless $linearread_<x> is 1: the drift noise, 0.5 +- 0.12 as stored, came in
	-- as ~0.21 - every pixel's offset (n * 2 - 1) leant the same way, the previous frame was read from up-left and the
	-- trail flowed right / down a few px every frame (the "crawls down diagonally", "flies down", "slides right" of all
	-- the rounds before). The trail pass reads its noise linear now (its own material name: CreateMaterial keeps the
	-- old keyvalues under the old one)
	mats = {acc = ss("alex_mercer_vacc", "alex_mercer_vheat", {["$linearread_texture2"] = 1}, "_lin"),
		thermal = ss("alex_mercer_vthermal", "_rt_FullFrameFB"),
		infected = ss("alex_mercer_vinfected", "_rt_FullFrameFB")}
	mats.acc:SetTexture("$basetexture", rtHeat)
	-- (user 2026-10-29: "the infected glow slides off to the right") the trail's drift noise: fine cells (noise3.png,
	-- tools/vision_noise.py) so the outline's parts drift different ways - a rim that stays on the body; the thermal
	-- shimmer keeps noise2.png
	local fine = Material("alex_mercer/vision/noise3.png", "noclamp smooth"):GetTexture("$basetexture")
	if fine then mats.acc:SetTexture("$texture2", fine) end
	-- the infected shader's own look at this frame's bodies (the silhouette, not the trail): the body as itself inside,
	-- the glow outside
	mats.infected:SetTexture("$texture3", rtHeat)
	return true
end

local flat = CreateMaterial("alex_mercer_vflat", "UnlitGeneric", {["$basetexture"] = "color/white", ["$model"] = 1})
-- (models/debug/debugwhite came out unlit - the facing was 1 all over, no cooler rims) a lit white of our own
local lit = CreateMaterial("alex_mercer_vlit", "VertexLitGeneric", {["$basetexture"] = "color/white", ["$model"] = 1})
local cur = 1

-- 1. the heat buffer (each pass keeps the brightest value: BLENDFUNC_MAX)
-- (user screenshots: white squares under the people - their shadows, drawn after PostDrawOpaqueRenderables, where this
-- used to run) drawn at the end of the frame, over the finished scene's depth
-- (user screenshot: a cone from the soldier to the screen's centre, his body unlit) cam.Start3D() there took a default
-- camera, not the possession view's own fov: the heat landed beside the body. The scene's exact view is kept while it
-- renders and the heat is drawn through it (fov, clip planes - the depth test needs the same projection)
local sceneView
hook.Add("PostDrawOpaqueRenderables", "AlexMercerVision", function(depth, sky)
	if depth or sky or not mode then return end
	sceneView = render.GetViewSetup()
end)
local function drawHeat()
	local list = collect()
	local v = sceneView
	-- (user screenshot: with fov_unscaled the heat came out bigger and pushed off the centre - cam.Start doesn't widen
	-- it for 16:9) the view's own horizontal fov and aspect, as the scene was drawn
	if v then
		cam.Start({type = "3D", origin = v.origin, angles = v.angles, fov = v.fov, aspect = v.aspect, znear = v.znear,
			zfar = v.zfar, x = v.x, y = v.y, w = v.width, h = v.height})
	else
		cam.Start3D()
	end
	render.PushRenderTarget(rtHeat)
	render.Clear(0, 0, 0, 255, false, false)
	if #list > 0 then
		render.OverrideDepthEnable(true, false)
		render.OverrideBlend(true, BLEND_ONE, BLEND_ONE, BLENDFUNC_MAX)
		render.MaterialOverride(flat)
		-- thermal: the warm behind walls too, dimmer (r = heat, g = a middling facing)
		if mode == "thermal" then
			cam.IgnoreZ(true)
			for _, e in ipairs(list) do
				if isWarm(e) then
					local h = heatOf(e) * HIDDEN_HEAT
					render.SetColorModulation(h, h * 0.6, 0)
					e:DrawModel()
				end
			end
			cam.IgnoreZ(false)
		end
		-- in sight: r = heat, b = infected / military, flat
		for _, e in ipairs(list) do
			render.SetColorModulation(isWarm(e) and heatOf(e) or 0, 0, isTarget(e) and INFECTED_DRAW or 0)
			e:DrawModel()
		end
		-- g = heat * facing the camera, lit from the eye only
		render.MaterialOverride(lit)
		render.SuppressEngineLighting(true)
		render.ResetModelLighting(0, 0, 0)
		local fwd = v and v.angles:Forward() or EyeAngles():Forward()
		render.SetLocalModelLights({{type = MATERIAL_LIGHT_DIRECTIONAL, color = Vector(0, 1, 0), dir = fwd}})
		for _, e in ipairs(list) do
			if isWarm(e) then
				local h = heatOf(e)
				render.SetColorModulation(h, h, h)
				e:DrawModel()
			end
		end
		render.SetLocalModelLights({})
		render.SuppressEngineLighting(false)
		render.MaterialOverride()
		render.SetColorModulation(1, 1, 1)
		render.OverrideBlend(false)
		render.OverrideDepthEnable(false)
	end
	render.PopRenderTarget()
	cam.End3D()
end

-- each vision's own numbers (thermal and infected apart: a change to one leaves the other as it is)
local DRIFT = {thermal = 1, infected = 1}
-- the trail buffers emptied (a vision starting from none: last time's trail would flash at its old places)
local function clearTrail()
	if not rtAcc then return end
	for _, rt in ipairs(rtAcc) do
		render.PushRenderTarget(rt)
		render.Clear(0, 0, 0, 255)
		render.PopRenderTarget()
	end
end
local function shaderPass()
	drawHeat()
	-- 2. carry-over (the game's strengths are per 30 fps frame)
	local dt = math.max(RealFrameTime(), 0.001)
	local prev, nxt = rtAcc[cur], rtAcc[3 - cur]
	mats.acc:SetTexture("$texture1", prev)
	mats.acc:SetFloat("$c0_x", CurTime())
	mats.acc:SetFloat("$c0_y", 0.169 ^ (dt * 30))
	mats.acc:SetFloat("$c0_z", 0.72 ^ (dt * 30))
	mats.acc:SetFloat("$c0_w", math.min(dt * 30, 1))
	-- (user 2026-10-29: "make them independent") each vision's own trail drift, 1 = the game's 15 px per frame at 720p
	mats.acc:SetFloat("$c1_x", DRIFT.thermal)
	mats.acc:SetFloat("$c1_y", DRIFT.infected)
	-- the buffers' size: every read snaps onto a texel centre (D3D9's half pixel either way)
	mats.acc:SetFloat("$c1_z", nxt:Width())
	mats.acc:SetFloat("$c1_w", nxt:Height())
	render.PushRenderTarget(nxt)
	render.SetMaterial(mats.acc)
	render.DrawScreenQuad()
	render.PopRenderTarget()
	cur = 3 - cur
	-- 3. on screen
	render.UpdateScreenEffectTexture()
	local m = mats[mode]
	m:SetTexture("$basetexture", render.GetScreenEffectTexture())
	m:SetTexture("$texture1", nxt)
	m:SetFloat("$c0_x", CurTime())
	m:SetFloat("$c0_y", 0.05) -- the shimmer at ~60 m (pow(depth / shimmerRange 500, 1.5))
	-- the thermal glow round the bodies: 5 px at 1080p, out to twice that; the infected one: INFECTED_GLOW px, at
	-- INFECTED_EDGE by the body, the body itself at INFECTED_BODY
	local infected = mode == "infected"
	local reach = (infected and INFECTED_GLOW or 5) * ScrH() / 1080
	m:SetFloat("$c1_x", reach / ScrW())
	m:SetFloat("$c1_y", reach / ScrH())
	m:SetFloat("$c1_z", infected and INFECTED_EDGE or 1)
	if infected then m:SetFloat("$c1_w", INFECTED_BODY) end
	-- the accumulation buffer's size, for the hand-made filtering
	local qw, qh = nxt:Width(), nxt:Height()
	m:SetFloat("$c2_x", 1 / qw)
	m:SetFloat("$c2_y", 1 / qh)
	m:SetFloat("$c2_z", qw)
	m:SetFloat("$c2_w", qh)
	render.SetMaterial(m)
	render.DrawScreenQuad()
end

---------------------------------------------------------------------------------------------------------------------
-- the simple look (alex_mercer_vision_shaders 0)
local COOL, HOT, HOTTEST = Vector(0, 0.52, 1), Vector(0.69, 0.27, 0.19), Vector(0.92, 0.80, 0.04)
local TINT = Vector(18, 12, 6):GetNormalized() * 1.6
local function heatColour(h)
	h = math.Clamp(h, 0.001, 1)
	local c = LerpVector(math.Clamp(1 + math.log(h ^ 0.2), 0, 1), COOL, HOT)
	return LerpVector(math.Clamp(h * 2 - 1, 0, 1), c, HOTTEST)
end
local THERMAL_CM = {["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
	["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1.3, ["$pp_colour_colour"] = 0,
	["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0}
local INFECTED_CM = {["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
	["$pp_colour_brightness"] = -0.02, ["$pp_colour_contrast"] = 1.15, ["$pp_colour_colour"] = 0.5,
	["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0}
local function multiply(r, g, b)
	cam.Start2D()
	render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ZERO, BLENDFUNC_ADD)
	surface.SetDrawColor(r * 255, g * 255, b * 255, 255)
	surface.DrawRect(0, 0, ScrW(), ScrH())
	render.OverrideBlend(false)
	cam.End2D()
end
local function simplePass()
	local list = collect()
	if mode == "thermal" then
		DrawColorModify(THERMAL_CM)
		multiply(0.42, 0.62, 1)
	else
		DrawColorModify(INFECTED_CM)
		multiply(1, 0.55, 0.3)
		DrawMaterialOverlay("effects/water_warp01", 0.012)
	end
	local fwd = EyeAngles():Forward()
	cam.Start3D()
	render.MaterialOverride(lit)
	render.SuppressEngineLighting(true)
	for _, e in ipairs(list) do
		local full, rim
		if mode == "thermal" and isWarm(e) then
			local h = heatOf(e)
			full, rim = heatColour(h), heatColour(h * (1 - 0.349))
		elseif mode == "infected" and isTarget(e) then
			full, rim = TINT, TINT * 0.55
		end
		if full then
			for i = 0, 5 do render.SetModelLighting(i, rim.x, rim.y, rim.z) end
			render.SetLocalModelLights({{type = MATERIAL_LIGHT_DIRECTIONAL, color = (full - rim) * 2, dir = fwd}})
			e:DrawModel()
		end
	end
	render.SetLocalModelLights({})
	render.SuppressEngineLighting(false)
	render.MaterialOverride()
	cam.End3D()
end

-- (user 2026-10-29: "the shaders should come in softer, the screen changes too sharply") the vision fades in and out
-- over alex_mercer_vision_fade seconds (our own number - the graphs give none for the vision itself): the screen as
-- it was before the pass is kept and laid back over the result by 1 - strength
local FADE = CreateClientConVar("alex_mercer_vision_fade", "0.5", true, false,
	"Alex Mercer vision: seconds the vision takes to fade in / out (0 = at once)")
local shown, strength = nil, 0
local rtBefore, matBefore
local function keepScreen()
	local w, h = ScrW(), ScrH()
	if not rtBefore or rtBefore:Width() ~= w or rtBefore:Height() ~= h then
		rtBefore = GetRenderTargetEx("alex_mercer_vision_before_" .. w .. "x" .. h, w, h, RT_SIZE_NO_CHANGE,
			MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_BGRA8888)
		matBefore = CreateMaterial("alex_mercer_vision_before_" .. w .. "x" .. h, "UnlitGeneric",
			{["$basetexture"] = rtBefore:GetName(), ["$vertexalpha"] = 1, ["$vertexcolor"] = 1, ["$ignorez"] = 1})
	end
	render.UpdateScreenEffectTexture()
	render.CopyTexture(render.GetScreenEffectTexture(), rtBefore)
end
hook.Add("RenderScreenspaceEffects", "AlexMercerVision", function()
	if mode and not possessedMercer() then setMode(nil) end
	local fade = math.max(FADE:GetFloat(), 0)
	-- (user 2026-10-29: "the visions don't come in smoothly now") one vision to the other: the shown one fades out
	-- first, then the new one in (it switched in a single frame); a frame's step at most 1/20 s (a hitch - the first
	-- start's loading - jumped the fade half way)
	local want = (mode and (not shown or shown == mode)) and 1 or 0
	local step = math.min(RealFrameTime(), 0.05)
	if fade <= 0 then strength = want
	else strength = strength + math.Clamp(want - strength, -step / fade, step / fade) end
	if strength <= 0 then
		strength = 0
		shown = nil
		if not mode then return end
	end
	if not shown then
		shown = mode
		if USE_SHADERS:GetBool() and setup() then clearTrail() end
	end
	if strength <= 0 then return end
	local partial = strength < 1
	if partial then keepScreen() end
	local m = mode
	mode = shown -- (the pass reads the mode: on the fade-out the one going away)
	if USE_SHADERS:GetBool() and setup() then shaderPass() else simplePass() end
	mode = m
	if partial then
		cam.Start2D()
		surface.SetMaterial(matBefore)
		surface.SetDrawColor(255, 255, 255, 255 * (1 - strength))
		surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
		cam.End2D()
	end
end)

-- The HUD's vision loop (boot_strap.p3d ui_hud_infected_vision_loop - for both visions, the user's taste; the game's
-- thermal one, ui_hud_thermal_vision_loop, is in the addon too).
-- (user 2026-10-29: "sometimes the vision's sound stays after it is off") one channel, kept by a watchdog every frame:
-- none while no vision is on (or he is no longer played), its volume easing in and out with the vision's fade, silent
-- behind the game's menu (the channel doesn't pause with the game). Every channel ever started is kept in a global: a
-- reload of this script lost its reference and the loop played on with nobody to stop it - at load the old ones stop
ALEX_MERCER_VISION_LOOPS = ALEX_MERCER_VISION_LOOPS or {}
for ch in pairs(ALEX_MERCER_VISION_LOOPS) do
	if IsValid(ch) then ch:Stop() end
end
ALEX_MERCER_VISION_LOOPS = {}
local LOOPS = ALEX_MERCER_VISION_LOOPS
local loopCh, loopAsked, loopVol = nil, false, 0
hook.Add("Think", "AlexMercerVisionLoop", function()
	local on = mode ~= nil and possessedMercer() ~= nil
	loopVol = math.Approach(loopVol, on and 1 or 0, math.min(RealFrameTime(), 0.05) / math.max(FADE:GetFloat(), 0.01))
	local keep = on or loopVol > 0
	-- every channel but the one in use stops (a late second one, or all of them once nothing is on)
	for ch in pairs(LOOPS) do
		if not IsValid(ch) then
			LOOPS[ch] = nil
		elseif ch ~= loopCh or not keep then
			ch:Stop()
			LOOPS[ch] = nil
		end
	end
	if not keep then
		loopCh = nil
		return
	end
	if IsValid(loopCh) then
		loopCh:SetVolume(gui.IsGameUIVisible() and 0 or loopVol)
		return
	end
	if loopAsked or not on then return end
	loopAsked = true
	sound.PlayFile("sound/mercer/fx/ui_hud_infected_vision_loop.wav", "noplay noblock", function(ch)
		loopAsked = false
		if not IsValid(ch) then return end
		LOOPS[ch] = true -- (not the one in use: the watchdog stops it next frame)
		if IsValid(loopCh) then return end
		loopCh = ch
		ch:EnableLooping(true)
		ch:SetVolume(0)
		ch:Play()
	end)
end)

-- thermal: fadeColour with distance - from startFade 30 m over fadeRange 70 m, never past minFade 0.2
local FADE = Vector(0.09, 0.22, 0.44)
local function fog(scale)
	-- (user 2026-10-29: "not smooth") the fog went on at full in the first frame, under the fade: it follows the shown
	-- vision's strength now
	if shown ~= "thermal" or strength <= 0 or not possessedMercer() then return end
	scale = scale or 1
	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(30 * M2U * scale)
	render.FogEnd(100 * M2U * scale)
	render.FogMaxDensity(0.2 * strength)
	render.FogColor(FADE.x * 255, FADE.y * 255, FADE.z * 255)
	return true
end
hook.Add("SetupWorldFog", "AlexMercerVision", function() return fog(1) end)
hook.Add("SetupSkyboxFog", "AlexMercerVision", function(scale) return fog(scale) end)
hook.Remove("PreDrawHalos", "AlexMercerVision") -- (the old look's glow; the shader has its own)
-