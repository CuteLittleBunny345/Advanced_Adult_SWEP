- Ground impact (heavy landing, charged jump, ground spikes): a ring of dust and flying debris.
function EFFECT:Init(data)
	local pos, scale = data:GetOrigin(), math.Clamp(data:GetScale(), 0.3, 3)
	local em = ParticleEmitter(pos)
	for i = 1, math.floor(28 * scale) do
		local a = math.rad(i / (28 * scale) * 360)
		local dir = Vector(math.cos(a), math.sin(a), 0)
		local p = em:Add("particle/particle_smokegrenade", pos + dir * 10 + Vector(0, 0, 8))
		if p then
			p:SetVelocity(dir * math.Rand(250, 420) * scale + Vector(0, 0, math.Rand(10, 60)))
			p:SetAirResistance(220)
			p:SetDieTime(math.Rand(1.0, 1.8))
			p:SetStartAlpha(180)
			p:SetEndAlpha(0)
			p:SetStartSize(25 * scale)
			p:SetEndSize(80 * scale)
			p:SetRoll(math.Rand(0, 360))
			p:SetRollDelta(math.Rand(-1, 1))
			local g = math.random(90, 120)
			p:SetColor(g, g * 0.9, g * 0.8)
		end
	end
	for _ = 1, math.floor(14 * scale) do
		local p = em:Add("effects/fleck_cement" .. math.random(2), pos + Vector(0, 0, 5))
		if p then
			p:SetVelocity(VectorRand() * 250 * scale + Vector(0, 0, 350 * scale))
			p:SetDieTime(math.Rand(1, 2))
			p:SetStartAlpha(255)
			p:SetEndAlpha(255)
			p:SetStartSize(math.Rand(2, 4))
			p:SetEndSize(1)
			p:SetRoll(math.Rand(0, 360))
			p:SetRollDelta(math.Rand(-6, 6))
			p:SetGravity(Vector(0, 0, -600))
			p:SetCollide(true)
			p:SetBounce(0.3)
		end
	end
	em:Finish()
end

function EFFECT:Think() return false end
function EFFECT:Render() end
-