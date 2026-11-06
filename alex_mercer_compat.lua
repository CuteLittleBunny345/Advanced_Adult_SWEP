- (2026-11-04, a player: "there seems to be some addon conflict with the fov changing and devastator sounds with slow motion, tho without other addons, everything works fine") What another addon's hook can do to him, in whatever order the
-- hooks run: hook.Call goes by pairs and stops at the first value it gets back, no hook can choose its place. Each such hook of another addon is wrapped here, so nothing changes without one:
-- * CalcView (client): while he is possessed the view it returns is dropped, it still runs. The first to return would take his camera and his FOV, which come from DrGBase's hook (alex_mercer_fx_cl.lua);
-- * EntityEmitSound: game.SetTimeScale does not touch sounds (GMod's wiki), and the wiki's own example has addons pitch every sound by it: under a time scale his own sounds keep the pitch they were emitted with (a devastator's slow motion is
--   0.25: two octaves down otherwise). Their other changes stand, a false still silences it.
-- alex_mercer_conflicts (console): such hooks and the files they come from. alex_mercer_compat 0: the hooks left as they are. Not seen in GMod: no such addon has been here to try
AddCSLuaFile()

local Compat = CreateConVar("alex_mercer_compat", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED},
	"Keep other addons' CalcView and EntityEmitSound hooks off Alex Mercer's camera and his sounds in slow motion (0 = leave them)", 0, 1)
local HIS = "drg_alex_mercer"
-- each wrap's original (weak: a hook removed goes with it)
local orig = setmetatable({}, {__mode = "k"})

-- ours, and DrGBase's that his camera comes from
local function own(name)
	return name == "DrGBasePossessionCalcView" or (isstring(name) and string.find(string.lower(name), "mercer", 1, true) ~= nil)
end

-- (a hook keyed by an entity or a panel gets it first)
local GUARD = {
	EntityEmitSound = function(fn, keyed)
		return function(a, b)
			local t = keyed and b or a
			local e = istable(t) and t.Entity
			if not (Compat:GetBool() and game.GetTimeScale() ~= 1 and IsValid(e) and e:GetClass() == HIS) then return fn(a, b) end
			local p = t.Pitch
			local r = fn(a, b)
			t.Pitch = p
			return r
		end
	end,
}
if CLIENT then
	local function possessed()
		local ply = LocalPlayer()
		if not IsValid(ply) or not ply.DrG_GetPossessing then return false end
		local ent = ply:DrG_GetPossessing()
		return IsValid(ent) and ent:GetClass() == HIS
	end
	GUARD.CalcView = function(fn)
		return function(...)
			local a, b, c, d, e, f = fn(...)
			if Compat:GetBool() and possessed() then return end
			return a, b, c, d, e, f
		end
	end
end

local function scan()
	local hooks = hook.GetTable()
	for event, guard in pairs(GUARD) do
		local add
		for name, fn in pairs(hooks[event] or {}) do
			if isfunction(fn) and not orig[fn] and not own(name) then
				add = add or {}
				add[name] = fn
			end
		end
		for name, fn in pairs(add or {}) do
			local w = guard(fn, not isstring(name))
			orig[w] = fn
			hook.Add(event, name, w)
		end
	end
end
-- (hooks come and go after the map's start: looked at again; nothing happens while there's nothing new)
hook.Add("InitPostEntity", "AlexMercerCompat", scan)
timer.Create("AlexMercerCompat", 2, 0, scan)

local function list(realm)
	print(string.format("[alex_mercer] %s: time scale %g, alex_mercer_compat %d", realm, game.GetTimeScale(), Compat:GetInt()))
	for _, event in ipairs({"CalcView", "EntityEmitSound"}) do
		for name, fn in pairs(hook.GetTable()[event] or {}) do
			if not own(name) then
				local i = debug.getinfo(orig[fn] or fn, "S")
				print(string.format("  %s %s: %s:%d", event, tostring(name), i.short_src, i.linedefined))
			end
		end
	end
end
if SERVER then
	concommand.Add("alex_mercer_conflicts_sv", function(ply)
		if IsValid(ply) and not game.SinglePlayer() and not ply:IsSuperAdmin() then return end
		list("server")
	end)
else
	concommand.Add("alex_mercer_conflicts", function()
		list("client")
		RunConsoleCommand("alex_mercer_conflicts_sv")
	end)
end
-