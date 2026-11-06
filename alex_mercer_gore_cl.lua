- The dismembered halves (server: alex_mercer_gore.lua): each prop_ragdoll is the whole model drawn clipped at the
-- cut, which rides one of its bones (MCutBone / MCutP / MCutN, the kept side along the normal). The inside shows
-- through the cut as flesh (the model's back faces drawn with the flesh material) - the game's gibs carry their own
-- caps (char_ped_gibs). Horizontal cut: the top half also draws its arms whole (they hang below the cut), the bottom
-- half never draws them. For a few seconds after the cut it bleeds from it.

local FLESH = Material("models/flesh")
CreateConVar("alex_mercer_gore", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Alex Mercer: his slashes cut the humans they kill in two, as the game", 0, 1)
CreateConVar("alex_mercer_gore_debug", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Alex Mercer: print the dismemberment's decisions", 0, 1)
local BLEED_T = 3
local cut = {}

local ARM = {"UpperArm", "Forearm", "Hand", "Finger", "Ulna", "Wrist", "Elbow", "Bicep", "Trapezius"}
local function isArm(name)
	if not name or not string.find(name, "_[LR]_") then return false end
	for _, k in ipairs(ARM) do if string.find(name, k, 1, true) then return true end end
	return false
end

local ZERO = Vector(0, 0, 0)
-- hide = "arms": collapse the arm bones; "rest": collapse everything but the arms
-- (user 2026-10-29: "two copies of the cut NPC, crooked") a half is the whole ragdoll: the bones of the side cut off
-- (collisionless, 1 kg) still swung about and poked through the clip plane. A bone whose origin AND parent's origin
-- are past the cut (2 u in) is collapsed - its skin gathers at its origin, behind the plane; a bone straddling the cut
-- (the pelvis at a waist cut) is left to the clip plane. Not in the "rest" pass (the top half's arms drawn whole).
local function cutOff(ent, b, P, N)
	local m = ent:GetBoneMatrix(b)
	if not m or (m:GetTranslation() - P):Dot(N) > -2 then return false end
	local par = ent:GetBoneParent(b)
	if not par or par < 0 then return false end
	local pm = ent:GetBoneMatrix(par)
	return pm ~= nil and (pm:GetTranslation() - P):Dot(N) <= -2
end
local function collapse(ent, n)
	local hide = ent.MCutHide
	local P, N = ent.MCutP, ent.MCutN
	if not hide and not P then return end
	for b = 0, n - 1 do
		local arm = ent.MCutArmSet[b]
		local off = (hide == "arms" and arm) or (hide == "rest" and not arm)
		if not off and hide ~= "rest" and P and not (hide == "arms" and arm) then off = cutOff(ent, b, P, N) end
		if off then
			local m = ent:GetBoneMatrix(b)
			if m then
				m:Scale(ZERO)
				ent:SetBoneMatrix(b, m)
			end
		end
	end
end

local function plane(ent)
	local m = ent:GetBoneMatrix(ent:GetNW2Int("MCutBone"))
	if not m then return end
	local P = LocalToWorld(ent:GetNW2Vector("MCutP"), Angle(), m:GetTranslation(), m:GetAngles())
	local N = LocalToWorld(ent:GetNW2Vector("MCutN"), Angle(), vector_origin, m:GetAngles())
	N:Normalize()
	return P, N
end

local function draw(ent)
	local P, N = plane(ent)
	if not P then return ent:DrawModel() end
	-- (the plane for the bone collapse comes from the frame before - the first frame draws clipped only)
	ent.MCutP, ent.MCutN = P, N
	local arms = ent:GetNW2Int("MCutArms")
	local old = render.EnableClipping(true)
	render.PushCustomClipPlane(N, N:Dot(P))
	ent.MCutHide = arms == 2 and "arms" or nil
	ent:InvalidateBoneCache()
	ent:DrawModel()
	-- the inside, seen through the cut
	render.CullMode(MATERIAL_CULLMODE_CW)
	render.MaterialOverride(FLESH)
	ent:DrawModel()
	render.MaterialOverride()
	render.CullMode(MATERIAL_CULLMODE_CCW)
	render.PopCustomClipPlane()
	render.EnableClipping(old)
	if arms == 1 then
		-- the arms, whole (they hang below a waist cut)
		ent.MCutHide = "rest"
		ent:InvalidateBoneCache()
		ent:DrawModel()
	end
	if ent.MCutHide then
		ent.MCutHide = nil
		ent:InvalidateBoneCache()
	end
end

local function setup(ent)
	ent.MCutArmSet = {}
	for b = 0, ent:GetBoneCount() - 1 do ent.MCutArmSet[b] = isArm(ent:GetBoneName(b)) end
	ent:AddCallback("BuildBonePositions", collapse)
	ent.RenderOverride = draw
	cut[ent] = true
end

-- the halves arrive as plain ragdolls; their cut comes with the NW vars
-- (user 2026-10-29: "two copies") they were looked at every 0.2 s - for up to that long both halves drew as whole
-- bodies. A new ragdoll is watched every frame for its first second; the 0.2 s scan stays as the fallback
local fresh = {}
hook.Add("OnEntityCreated", "AlexMercerGoreCl", function(e)
	if e:GetClass() == "prop_ragdoll" then fresh[e] = CurTime() + 1 end
end)
local nextScan = 0
hook.Add("Think", "AlexMercerGoreCl", function()
	local now = CurTime()
	for e, until_ in pairs(fresh) do
		if not IsValid(e) or now > until_ or cut[e] then
			fresh[e] = nil
		elseif e:GetNW2Bool("MCut") then
			setup(e)
			fresh[e] = nil
		end
	end
	if now >= nextScan then
		nextScan = now + 0.2
		for _, e in ipairs(ents.FindByClass("prop_ragdoll")) do
			if not cut[e] and e:GetNW2Bool("MCut") then setup(e) end
		end
	end
	-- bleeding from the cut
	for e in pairs(cut) do
		if not IsValid(e) then
			cut[e] = nil
		elseif e.MCutP and now - e:GetNW2Float("MCutT") < BLEED_T and now >= (e.MCutNextBleed or 0) then
			local k = 1 - (now - e:GetNW2Float("MCutT")) / BLEED_T
			e.MCutNextBleed = now + 0.12 + (1 - k) * 0.25
			local ed = EffectData()
			ed:SetOrigin(e.MCutP + VectorRand() * 3)
			ed:SetNormal((e.MCutN + VectorRand() * 0.35):GetNormalized())
			ed:SetScale(0.6 + k * 0.6)
			ed:SetFlags(13) -- blood_gush
			util.Effect("alex_mercer_vfx", ed)
		end
	end
end)
-