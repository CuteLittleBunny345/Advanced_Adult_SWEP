- Mutation effect: dark-red biomass bursting off Mercer's arms and shoulders for a moment.
local BONES = {"Wrist_R", "Elbow_R", "Shoulder_R", "Wrist_L", "Elbow_L", "Shoulder_L", "Spine_3"}

function EFFECT:Init(data)
	self.Ent = data:GetEntity()
	self.DieTime = CurTime() + 0.7
	self.Emitter = ParticleEmitter(data:GetOrigin())
	self:SetRenderBounds(Vector(-128, -128, -128), Vector(128, 128, 128))
end

function EFFECT:Think()
	local ent = self.Ent
	if CurTime() > self.DieTime or not IsValid(ent) then
		if self.Emitter then self.Emitter:Finish() end
		return false
	end
	self:SetPos(ent:WorldSpaceCenter())
	for _, name in ipairs(BONES) do
		local bone = ent:LookupBone(name)
		if bone then
			local pos = ent:GetBonePosition(bone)
			for _ = 1, 2 do
				local p = self.Emitter:Add("effects/blood_core", pos + VectorRand() * 3)
				if p then
					p:SetVelocity(VectorRand() * 90 + Vector(0, 0, 20))
					p:SetDieTime(math.Rand(0.3, 0.6))
					p:SetStartAlpha(255)
					p:SetEndAlpha(0)
					p:SetStartSize(math.Rand(3, 6))
					p:SetEndSize(0)
					p:SetRoll(math.Rand(0, 360))
					p:SetRollDelta(math.Rand(-4, 4))
					p:SetColor(math.random(90, 150), 5, 5)
					p:SetGravity(Vector(0, 0, -250))
				end
			end
			local s = self.Emitter:Add("particle/particle_smokegrenade", pos)
			if s then
				s:SetVelocity(VectorRand() * 25)
				s:SetDieTime(math.Rand(0.4, 0.8))
				s:SetStartAlpha(120)
				s:SetEndAlpha(0)
				s:SetStartSize(4)
				s:SetEndSize(14)
				s:SetColor(40, 0, 0)
			end
		end
	end
	return true
end

function EFFECT:Render() end
-