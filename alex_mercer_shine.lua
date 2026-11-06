- (user 2026-10-30: the jacket "rubbery", in the game matte, leathery; the jeans too) Mercer's own shine as the game's
-- char_alex / char_alex_cloth shaders have it (tools/cloth_shine.py): the highlight's width from the game's roughness
-- (Source's phong is R.L - the first port used the game's N.H exponent, ~2.6x too narrow) and head-on F0 without the
-- port's x2. The VMTs carry the game's values; 0 puts the old ones back live, for comparing (no restart).
local GameShine = CreateClientConVar("alex_mercer_shine_game", "1", true, false,
	"Alex Mercer: the jacket / jeans / face shine as in the game (0 = the old, glossier one)", 0, 1)

local SETS = {
	-- {material, game {exponent, boost, exponent texture}, old {exponent, boost, exponent texture}}
	{"models/mercer/alex_body_dm", {12, 1, "models/mercer/alex_body_dm_exp_v2"}, {32, 1.312, "models/mercer/alex_body_dm_exp"}},
	{"models/mercer/alex_head_dm", {12, 1}, {32, 1.312}},
}

local function apply()
	local game = GameShine:GetBool()
	for _, s in ipairs(SETS) do
		local m = Material(s[1])
		if m and not m:IsError() then
			local v = game and s[2] or s[3]
			m:SetFloat("$phongexponent", v[1])
			m:SetFloat("$phongboost", v[2])
			if v[3] then m:SetTexture("$phongexponenttexture", v[3]) end
			m:Recompute()
		end
	end
end

hook.Add("InitPostEntity", "alex_mercer_shine", apply)
cvars.AddChangeCallback("alex_mercer_shine_game", apply, "alex_mercer_shine")
apply() -- (an autorefresh of this file mid-game too)
-