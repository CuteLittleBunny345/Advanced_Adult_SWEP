- Critical Pain's tendril (prototype_devastator critical_pain/attack, drg_alex_mercer.lua MercerDevastate "impale"): a
-- biomass tendril whipping out of Mercer's chest at a target - a curved beam (a quadratic Bezier bowing up and aside)
-- that shoots out over 0.1 s, holds on the target and draws back over the last 0.15 s.
-- data: Entity = Mercer, Start = where it leaves him, Origin = the target point, Magnitude = its life (s)
local MAT = Material("alex_mercer/fx/tendril")
local SEGS = 16

function EFFECT:Init(data)
	self.Ent = data:GetEntity()
	self.From = data:GetStart()
	self.To = data:GetOrigin()
	self.Life = math.max(data:GetMagnitude(), 0.2)
	self.T0 = CurTime()
	local side = (self.To - self.From):Cross(Vector(0, 0, 1))
	if side:LengthSqr() > 1 then side:Normalize() end
	self.Bow = side * math.Rand(-60, 60) + Vector(0, 0, math.Rand(30, 70))
	self:SetRenderBoundsWS(self.From, self.To, Vector(160, 160, 160))
end

function EFFECT:Think()
	return CurTime() - self.T0 < self.Life
end

function EFFECT:Render()
	local t = CurTime() - self.T0
	local reach = math.min(1, t / 0.1)
	if t > self.Life - 0.15 then reach = math.Clamp((self.Life - t) / 0.15, 0, 1) end
	if reach <= 0 then return end
	local from = self.From
	if IsValid(self.Ent) then from = self.Ent:WorldSpaceCenter() + Vector(0, 0, 10) end
	local to = self.To
	local mid = (from + to) * 0.5 + self.Bow
	render.SetMaterial(MAT)
	render.StartBeam(SEGS + 1)
	for i = 0, SEGS do
		local u = i / SEGS * reach
		local p = LerpVector(u, LerpVector(u, from, mid), LerpVector(u, mid, to))
		render.AddBeam(p, Lerp(i / SEGS, 10, 3), u * 3, Color(170, 60, 55, 255))
	end
	render.EndBeam()
end
-