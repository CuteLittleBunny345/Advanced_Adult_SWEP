- Shield block: sparks and a puff of torn biomass in front of Mercer.
function EFFECT:Init(data)
	local pos = data:GetOrigin()
	local em = ParticleEmitter(pos)
	for _ = 1, 14 do
		local p = em:Add("effects/spark", pos)
		if p then
			p:SetVelocity(VectorRand() * 220)
			p:SetDieTime(math.Rand(0.15, 0.35))
			p:SetStartAlpha(255)
			p:SetEndAlpha(0)
			p:SetStartSize(3)
			p:SetEndSize(0)
			p:SetStartLength(14)
			p:SetEndLength(2)
			p:SetColor(255, 170, 120)
			p:SetGravity(Vector(0, 0, -400))
		end
	end
	for _ = 1, 5 do
		local p = em:Add("effects/blood_core", pos)
		if p then
			p:SetVelocity(VectorRand() * 60)
			p:SetDieTime(0.4)
			p:SetStartAlpha(200)
			p:SetEndAlpha(0)
			p:SetStartSize(6)
			p:SetEndSize(0)
			p:SetColor(80, 0, 0)
		end
	end
	em:Finish()
	sound.Play("physics/flesh/flesh_impact_hard" .. math.random(6) .. ".wav", pos, 75, math.random(80, 100))
end

function EFFECT:Think() return false end
function EFFECT:Render() end
-