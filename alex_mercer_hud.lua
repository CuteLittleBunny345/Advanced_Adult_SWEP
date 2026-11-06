- Shared setup for Alex Mercer's HUD (the game's power wheel, lua/autorun/client/alex_mercer_wheel.lua).
-- (The wheel used to slow time down; the game does not, so that is gone.)
if SERVER then
	AddCSLuaFile("alex_mercer/swfplayer.lua")
	AddCSLuaFile("alex_mercer/hud_powershud.lua")
	AddCSLuaFile("alex_mercer/fxprogs.lua") -- the graphs' effect programs (tools/fxprog.py)
	AddCSLuaFile("alex_mercer/animscale.lua") -- the animations' joint scale (tools/build_animscale.py)
	AddCSLuaFile("alex_mercer/hud_health.lua")
	AddCSLuaFile("alex_mercer/hud_healthhud.lua") -- the game's animated health bar (tools/hudexport.py)
	AddCSLuaFile("alex_mercer/hud_minimaphud.lua") -- the game's minimap (tools/hudexport.py)
	AddCSLuaFile("alex_mercer/hud_awarenesshud.lua") -- the game's awareness lens (tools/hudexport.py)
	AddCSLuaFile("alex_mercer/hud_perceptionhud.lua") -- the game's disguise icons (tools/hudexport.py)
	AddCSLuaFile("alex_mercer/hud_mclargebracket.lua") -- the big brackets of a new target lock (tools/lockhud_export.py)
	AddCSLuaFile("alex_mercer/hud_locktargethud.lua") -- the game's target lock reticle (tools/hudexport.py) -- the game's health bar parts (tools/healthhud.py)
end
-