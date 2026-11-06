- Sprint start: a white ring expanding around Mercer (seen in the game when he breaks into a sprint).
local MAT = Material("effects/select_ring")

function EFFECT:Init(data)
	self.Ent = data:GetEntity()
	self.Start = CurTime()
	self.Life = 0.35
	self.Pos = data:GetOrigin()
	self.Normal = data:GetNormal()
	self:SetRenderBounds(Vector(-200, -200, -200), Vector(200, 200, 200))
end

function EFFECT:Think()
	if IsValid(self.Ent) then self.Pos = self.Ent:WorldSpaceCenter() end
	self:SetPos(self.Pos)
	return CurTime() - self.Start < self.Life
end

function EFFECT:Render()
	local k = (CurTime() - self.Start) / self.Life
	local size = 30 + k * 140
	render.SetMaterial(MAT)
	render.DrawQuadEasy(self.Pos, self.Normal, size, size, Color(255, 255, 255, 255 * (1 - k)), 0)
	render.DrawQuadEasy(self.Pos, -self.Normal, size, size, Color(255, 255, 255, 255 * (1 - k)), 0)
end
-