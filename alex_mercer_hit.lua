- Strike impact: a spray of blood at the victim, bigger for heavier mutations.
function EFFECT:Init(data)
	local pos, scale = data:GetOrigin(), math.Clamp(data:GetScale(), 0.5, 3)
	local ed = EffectData()
	ed:SetOrigin(pos)
	util.Effect("BloodImpact", ed)
	local em = ParticleEmitter(pos)
	for _ = 1, math.floor(10 * scale) do
		local p = em:Add("effects/blood_core", pos)
		if p then
			p:SetVelocity(VectorRand() * 160 * scale)
			p:SetDieTime(math.Rand(0.3, 0.7))
			p:SetStartAlpha(255)
			p:SetEndAlpha(0)
			p:SetStartSize(math.Rand(4, 9) * scale)
			p:SetEndSize(1)
			p:SetColor(math.random(110, 160), 0, 0)
			p:SetGravity(Vector(0, 0, -500))
			p:SetCollide(true)
		end
	end
	em:Finish()
end

function EFFECT:Think() return false end
function EFFECT:Render() end
-