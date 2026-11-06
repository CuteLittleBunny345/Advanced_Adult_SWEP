- (user 2026-11-04: "поубирали лишние галочки ... сделать автоматически для всех включенными"; of the camera: "Камеру игры") the settings taken out of the menu stay as console settings, to debug and to turn off. They are
-- archived, so a 0 an old checkbox saved would stay for good with nothing left to change it: each goes to its value once, on every machine. The cookie remembers it, so one set from the console afterwards stays, as in alex_mercer_footik.lua
AddCSLuaFile()
local ONCE = CLIENT and {alex_mercer_footik = "1", alex_mercer_vest = "1", alex_mercer_shine_game = "1", alex_mercer_dust = "1", alex_mercer_dash_fx = "1", alex_mercer_consume_active = "1", alex_mercer_camera_game = "1"}
	or {alex_mercer_footprints = "1", alex_mercer_disguise_sight = "1", alex_mercer_land_run = "1", alex_mercer_gore_debug = "0"}
local function once()
	if cookie.GetNumber("alex_mercer_menu_out", 0) >= 1 then return end
	-- (the entity file's come after the autorun files)
	for name in pairs(ONCE) do
		if not GetConVar(name) then return end
	end
	cookie.Set("alex_mercer_menu_out", "1")
	for name, v in pairs(ONCE) do GetConVar(name):SetString(v) end
end
once()
hook.Add("InitPostEntity", "alex_mercer_menu_out", once)
-- (user 2026-11-04: "расчленение включи, реакцию на удары кстати тоже надо сделать нормальной") both were off by default, and a saved 0 would stay: once, its own cookie (the first one's already spent)
if SERVER then
	local function on()
		if cookie.GetNumber("alex_mercer_on_gore_hits", 0) >= 1 or not GetConVar("alex_mercer_gore") or not GetConVar("alex_mercer_hit_reactions") then return end
		cookie.Set("alex_mercer_on_gore_hits", "1")
		GetConVar("alex_mercer_gore"):SetString("1")
		GetConVar("alex_mercer_hit_reactions"):SetString("1")
	end
	on()
	hook.Add("InitPostEntity", "alex_mercer_on_gore_hits", on)
end
-- (user 2026-11-05: "надо захват в воздухе сделать, я вводил команды в консоль, все равно не работало") its new default doesn't reach a 0 saved in cfg/server.vdf. Once, on every machine; set from the console afterwards it stays (alex_mercer_air_grab 0 is the way back)
if SERVER then
	local function airGrab()
		local cv = GetConVar("alex_mercer_air_grab")
		if cookie.GetNumber("alex_mercer_on_air_grab", 0) >= 1 or not cv then return end
		cookie.Set("alex_mercer_on_air_grab", "1")
		cv:SetString("1")
	end
	airGrab()
	hook.Add("InitPostEntity", "alex_mercer_on_air_grab", airGrab)
end
-