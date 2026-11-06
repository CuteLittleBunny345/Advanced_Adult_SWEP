- Bridge for the server: util.Effect("alex_mercer_vfx", data) with data:GetFlags() = effect index below
-- plays one of Prototype's particle effects (lua/autorun/client/alex_mercer_vfx.lua).
local NAMES = {"land_soft", "land_heavy", "land_huge", "foot", "wall", "boost", "dash", "dive", "air_dash", "skid", "hit", "pound",
	"blood_gush", "blood_mist", "blood_squib", "sparks", "concrete", "crush_concrete", "crush_generic", "crush_metal",
	"wood", "slash_metal", "wave", "decal_crack", "decal_line", "decal_spike", "decal_scorch",
	"decal_blood", "air_dash_wave", "boost_wave", "pound_generic", "decal_step", "bullet_dive_wave", "bullet_land_wave", "bullet_land_hot"}

function EFFECT:Init(data)
	local name = NAMES[data:GetFlags()]
	if name and ALEX_MERCER_VFX then
		-- (the entity, when the server sends one: the Mercer it belongs to - the dash waves' blur is his player's)
		local e = data:GetEntity()
		if name == "hit" then return ALEX_MERCER_VFX.HitFlash(data:GetOrigin(), data:GetNormal(), data:GetScale() > 0 and data:GetScale() or 1) end
		ALEX_MERCER_VFX.Play(name, data:GetOrigin(), data:GetNormal(), data:GetScale() > 0 and data:GetScale() or 1,
			IsValid(e) and e or nil)
	end
end

function EFFECT:Think() return false end
function EFFECT:Render() end
-