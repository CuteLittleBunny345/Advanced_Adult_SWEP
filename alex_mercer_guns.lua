- (user 2026-10-23) the soldiers' firearms from Prototype, for Mercer to pick up (E), fire (LMB) and drop (E).
-- Models: Soldier.p3d rifle001 / rifleSAW001 / rifleSniper001 / grenadeLauncher001 / rocketLauncher001
-- (tools/build_guns.py). Numbers: startup_tod.p3d GunAmmoProfile / MissileProfile *_ammo_player - clipCapacity,
-- fireRate (shots/s), damageOnNPC, distanceToLive (m); the firing kind (held / tapped) from the prototype_firearm graph
-- (build/graph_firearm.txt: rifle / saw on Attack Down, the others on Attack Pressed). muzzle = the barrel's tip in the
-- model (inches, from the mesh).
AddCSLuaFile()

local DamageScale = CreateConVar("alex_mercer_gun_damage", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED},
	"Mercer's firearms: damage multiplier (1 = the game's numbers)", 0, 20)

ALEX_MERCER_GUNS = {
	rifle = {name = "M16", model = "models/mercer/weapons/rifle.mdl", clip = 60, rate = 10, dmg = 10, range = 175,
		auto = true, spread = 0.025, snd = "mercer/weapons/m-16_single_shot_alex_02_mono.wav",
		tail = "mercer/weapons/m-16_tail_alex_01_mono.wav",
		muzzle = Vector(25.6, 0, 5.2)},
	saw = {name = "SAW", model = "models/mercer/weapons/saw.mdl", clip = 300, rate = 15, dmg = 10, range = 175,
		auto = true, spread = 0.04, snd = "mercer/weapons/saw_single_shot_alex_mono.wav",
		tail = "mercer/weapons/m-16_tail_alex_01_mono.wav",
		muzzle = Vector(26.2, 0, 6.3)},
	sniper = {name = "Sniper Rifle", model = "models/mercer/weapons/sniper.mdl", clip = 5, rate = 1, dmg = 25,
		range = 175, spread = 0, snd = "mercer/weapons/m-16_single_shot_alex_02_mono.wav", pitch = 72,
		tail = "mercer/weapons/m-16_tail_alex_01_mono.wav",
		muzzle = Vector(31.1, 0.5, 5.2)},
	grenade_launcher = {name = "Grenade Launcher", model = "models/mercer/weapons/grenade_launcher.mdl", clip = 18,
		rate = 4, dmg = 55, range = 175, projectile = "grenade", snd = "mercer/weapons/grenade_launch_01.wav",
		muzzle = Vector(22.3, 0, 4.4)},
	rocket_launcher = {name = "Rocket Launcher", model = "models/mercer/weapons/rocket_launcher.mdl", clip = 4,
		rate = 0.6667, dmg = 350, range = 200, projectile = "rocket", snd = "mercer/weapons/rocket_launcher_01.wav",
		muzzle = Vector(21.1, -1.9, 6.3)},
}
-- (2026-11-04) the models to draw, new names with the game's materials (tools/build_guns.py); .model stays the name the pack's
-- soldiers find their gun by (ENT.GunModel, MercerGunKindOf)
for _, g in pairs(ALEX_MERCER_GUNS) do g.mdl = string.gsub(g.model, "%.mdl$", "_v2.mdl") end
function ALEX_MERCER_GUN_DAMAGE(g) return g.dmg * DamageScale:GetFloat() end
-- GMod's own guns lying about (dropped by NPCs, spawned from the Weapons tab): Mercer's E takes them as the game's
-- nearest gun (drg_alex_mercer swaps the entity for ours, full clip)
ALEX_MERCER_GUN_FROM = {weapon_ar2 = "rifle", weapon_smg1 = "rifle", weapon_crossbow = "sniper", weapon_rpg = "rocket_launcher"}

if SERVER then
	-- (user 2026-10-23: "the guns get picked up by themselves and turn into ammo") the possessing player's hidden body
	-- stays by Mercer, and GMod's touch pickup took every weapon / item under his feet: none while possessing him
	local function possessingMercer(ply)
		local e = ply.DrG_GetPossessing and ply:DrG_GetPossessing()
		return IsValid(e) and e:GetClass() == "drg_alex_mercer"
	end
	-- (user 2026-10-23: with that, possessing left the possessor in his hands, firing at Mercer - DrGBase GIVES the
	-- possessing player its own weapon) only what has lain in the world is refused: a Give creates the weapon that very
	-- moment, and DrGBase's own weapons always pass
	local function lying(e)
		return IsValid(e) and CurTime() - e:GetCreationTime() > 0.5 and not string.find(e:GetClass(), "drg", 1, true)
	end
	hook.Add("PlayerCanPickupWeapon", "AlexMercerNoTouchPickup", function(ply, wep)
		if lying(wep) and possessingMercer(ply) then return false end
	end)
	hook.Add("PlayerCanPickupItem", "AlexMercerNoTouchPickup", function(ply, item)
		if lying(item) and possessingMercer(ply) then return false end
	end)
end

local FLASH = CLIENT and Material("effects/muzzleflash2")
for kind, g in pairs(ALEX_MERCER_GUNS) do
	local ENT = {Type = "anim", Base = "base_anim", PrintName = g.name, Category = "Prototype", Spawnable = true,
		MercerGunKind = kind}
	function ENT:SpawnFunction(ply, tr, cls)
		if not tr.Hit then return end
		local e = ents.Create(cls)
		e:SetPos(tr.HitPos + tr.HitNormal * 12)
		e:SetAngles(Angle(0, ply:EyeAngles().y, 0))
		e:Spawn()
		e:Activate()
		return e
	end
	function ENT:Initialize()
		self:SetModel(g.mdl)
		if SERVER then
			self:PhysicsInit(SOLID_VPHYSICS)
			self:SetMoveType(MOVETYPE_VPHYSICS)
			self:SetSolid(SOLID_VPHYSICS)
			self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
			local ph = self:GetPhysicsObject()
			if IsValid(ph) then ph:Wake() end
			if self:GetNW2Int("MercerGunAmmo", -1) < 0 then self:SetNW2Int("MercerGunAmmo", g.clip) end
		end
	end
	if CLIENT then
		-- (user 2026-10-28: "in jumps the gun is still far from his hand") in his hand it is drawn where his Wrist_R is
		-- as drawn, with alex_weap_rifle_stand's grip (frame 0, R_Wrist_Grapple under Wrist_R) - not by FollowBone,
		-- whose bone the non-weapon anims key ~60 u off the wrist
		local GRIP = Matrix()
		GRIP:SetTranslation(Vector(-1.236323, -2.479855, 0.582117))
		GRIP:SetAngles(Angle(math.deg(-0.089621), math.deg(-1.793148), math.deg(-3.084410)))
		local function inHand(self)
			local par = self:GetParent()
			if not IsValid(par) or par:GetClass() ~= "drg_alex_mercer" then return end
			local wb = par:LookupBone("Wrist_R")
			if not wb then return end
			par:SetupBones()
			local W = par:GetBoneMatrix(wb)
			return W and W * GRIP
		end
		-- the muzzle flash of a shot (the graph's fxlight_point: orange, 200)
		function ENT:Draw()
			local M = inHand(self)
			if M then
				self:SetRenderOrigin(M:GetTranslation())
				self:SetRenderAngles(M:GetAngles())
				self:SetupBones()
			end
			self:DrawModel()
			if M then
				self:SetRenderOrigin()
				self:SetRenderAngles()
			end
			if CurTime() - self:GetNW2Float("MercerGunShot", -10) > 0.05 then return end
			local p = M and M * (g.muzzle + Vector(4, 0, 0)) or self:LocalToWorld(g.muzzle + Vector(4, 0, 0))
			render.SetMaterial(FLASH)
			local s = math.Rand(10, 16) * (g.projectile and 1.6 or 1)
			render.DrawSprite(p, s, s, Color(255, 220, 160))
			local dl = DynamicLight(self:EntIndex())
			if dl then
				dl.pos, dl.r, dl.g, dl.b = p, 255, 165, 62
				dl.brightness, dl.size, dl.decay, dl.dietime = 2, 200, 2000, CurTime() + 0.05
			end
		end
	end
	scripted_ents.Register(ENT, "alex_mercer_gun_" .. kind)
end

-- (2026-11-04, alex_mercer_missile_grab) a rocket caught out of the air, in his right hand. Only what is drawn: he has its class, the
-- throw makes a new one. In the rocket's anims R_Wrist_Grapple keeps his own orientation, not the hand's, and a fixed place under
-- Wrist_R (build/anims/*.smd, build/chasecam/rocket_grip.py); other anims key it far off, so it is taken from the wrist, as a gun's.
-- On it the graph's grabSlotUpdateAttachment per phase, in Source's axes (build/chasecam/rocket_angles.py): u under the wrist, c its
-- parent offset, a the inverse of its child rotation (Pure3D's FillRotateXYZ and the inverse: read as the nose up in the windup and
-- forward on the sprint's forward swing, by eye; the hold's numbers are checked: the shell's axis comes to the wrist's height, 66.9
-- against 66.7 u; on the sprint its origin 5.6 u from the wrist). On the sprint, in the jumps and falls (firearm_partition/missile) on
-- the grapple as it hangs under the hand there, turning with it: the gun's grip, same numbers in that pose.
do
	local ENT = {Type = "anim", Base = "base_anim", PrintName = "Held rocket", Spawnable = false}
	function ENT:Initialize()
		if SERVER then
			self:SetMoveType(MOVETYPE_NONE)
			self:SetSolid(SOLID_NONE)
			self:DrawShadow(false)
		else
			self:SetRenderBounds(Vector(-120, -120, -20), Vector(120, 120, 160))
		end
	end
	if CLIENT then
		local THROW = Vector(-0.429, 0.157, -3.364)
		local HAND = Matrix()
		HAND:SetTranslation(Vector(-1.236323, -2.479855, 0.582117))
		HAND:SetAngles(Angle(math.deg(-0.089621), math.deg(-1.793148), math.deg(-3.084410)))
		-- NW2 MercerMissilePhase: 1 held (row 6 away from its own loco), 2 windup, 3 release, 4 / 5 the same in the air
		local ROWS = {
			{u = Vector(-4.715, -3.506, -0.283), c = Vector(0, -3.94, -9.84), a = Angle(0, 0, 0)},
			{u = THROW, c = Vector(0, -3.94, 0), a = Angle(-54.47, -36.05, 30.64)},
			{u = THROW, c = Vector(0, -3.94, 0), a = Angle(0, 0, 0)},
			{u = THROW, c = Vector(0, -3.94, -7.87), a = Angle(25.66, -106.1, 56.31)},
			{u = THROW, c = Vector(0, -3.94, -7.87), a = Angle(-7.05, -45.44, 7.11)},
			{hand = true, c = Vector(-7.87, 0, 0), a = Angle(65, 90, 90)},
		}
		local function place(r, W, ang)
			if r.hand then
				local M = W * HAND
				local _, a = LocalToWorld(vector_origin, r.a, vector_origin, M:GetAngles())
				return M * r.c, a
			end
			local c = Vector(r.c.x, r.c.y, r.c.z)
			c:Rotate(ang)
			local _, a = LocalToWorld(vector_origin, r.a, vector_origin, ang)
			return W * r.u + c, a
		end
		function ENT:Draw()
			local par = self:GetParent()
			local wb = IsValid(par) and par:LookupBone("Wrist_R")
			if not wb then return self:DrawModel() end
			par:SetupBones()
			local W = par:GetBoneMatrix(wb)
			if not W then return self:DrawModel() end
			local ph = self:GetNW2Int("MercerMissilePhase", 1)
			if ph == 1 then
				local seq = string.lower(par:GetSequenceName(par:GetSequence()) or "")
				if not (string.find(seq, "^alex_weap_missile") or seq == "alex_loco_grap_walk_n_gv" or seq == "alex_loco_grap_run_n_gv") then ph = 6 end
			end
			-- (the item's blend, 0.1 s)
			local r = ROWS[ph] or ROWS[1]
			if r ~= self.MercerRow then
				self.MercerFrom, self.MercerRow, self.MercerRowT = self.MercerRow or r, r, CurTime()
			end
			local ang = par:GetAngles()
			local pos, a = place(r, W, ang)
			local k = (CurTime() - self.MercerRowT) / 0.1
			if k < 1 then
				local p0, a0 = place(self.MercerFrom, W, ang)
				pos, a = LerpVector(k, p0, pos), LerpAngle(k, a0, a)
			end
			self:SetRenderOrigin(pos)
			self:SetRenderAngles(a)
			self:SetupBones()
			self:DrawModel()
			self:SetRenderOrigin()
			self:SetRenderAngles()
		end
	end
	scripted_ents.Register(ENT, "alex_mercer_missile_held")
end

if CLIENT then
	-- (user 2026-10-28: prop throwing back on) an object Mercer carries (NW2 MercerObjEnt on him; the server parents it
	-- at a fixed carry spot) is drawn between his drawn wrists - its centre half its size out in front, a little up -
	-- as the guns are: a nextbot's server bones in graph nodes are off, his client bones are what is seen
	local function carriedDraw(self, flags)
		local m = self:GetNW2Entity("MercerCarrier")
		local bl = IsValid(m) and m:LookupBone("Wrist_L")
		local br = IsValid(m) and m:LookupBone("Wrist_R")
		if not (bl and br) then return self:DrawModel(flags) end
		m:SetupBones()
		local ml, mr = m:GetBoneMatrix(bl), m:GetBoneMatrix(br)
		if not (ml and mr) then return self:DrawModel(flags) end
		local mins, maxs = self:OBBMins(), self:OBBMaxs()
		-- (user 2026-10-28: "on the hands, centred - the car") the carry pose holds it over his head: its bottom on his
		-- palms (4 u over the wrists), centred between them, following them through the pickup and the throw; turned
		-- by his own yaw + the server's choice (a vehicle's own parented angles drew it off)
		local hand = (ml:GetTranslation() + mr:GetTranslation()) * 0.5
		-- (user 2026-10-28: "too high" - a car's box reaches below its wheels: the palms sunk into its lower fifth)
		local c = hand + Vector(0, 0, (maxs.z - mins.z) * 0.3)
		-- (never into the floor: in the pickup his hands start low) its bottom no lower than his feet
		c.z = math.max(c.z, m:GetPos().z + (maxs.z - mins.z) * 0.5 + 1)
		local ang = Angle(0, m:GetAngles().y + m:GetNW2Float("MercerObjYaw", 0), 0)
		local oc = self:OBBCenter()
		oc:Rotate(ang)
		self:SetRenderOrigin(c - oc)
		self:SetRenderAngles(ang)
		self:SetupBones()
		self:DrawModel(flags)
		self:SetRenderOrigin()
		self:SetRenderAngles()
	end
	hook.Add("Think", "AlexMercerCarriedProps", function()
		for _, m in ipairs(ents.FindByClass("drg_alex_mercer")) do
			local e = m:GetNW2Entity("MercerObjEnt")
			if IsValid(e) and e.RenderOverride ~= carriedDraw then
				e.MercerOldRO = e.RenderOverride
				e.RenderOverride = carriedDraw
				e:SetRenderBounds(e:OBBMins() - Vector(80, 80, 80), e:OBBMaxs() + Vector(80, 80, 80))
			end
		end
		-- let go: back to its own drawing
		for _, e in ipairs(ents.FindByClass("prop_*")) do
			if e.RenderOverride == carriedDraw and not IsValid(e:GetNW2Entity("MercerCarrier")) then
				e.RenderOverride = e.MercerOldRO
				e.MercerOldRO = nil
			end
		end
	end)
end
-