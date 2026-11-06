- Spawn menu -> DrGBase tab -> Prototype -> Alex Mercer: the addon's settings (the convars live in the entity file /
-- alex_mercer_footik.lua; changing them works at once, on Mercers already spawned too).
-- (user 2026-11-04: "скажи чтоб поубирали лишние галочки, там например со старой камерой может быть, вот типа то что необязательно переключать знаешь, foot on uneven ground тоже можно убрать и сделать
-- автоматически для всех включенными"; of the camera: "Камеру игры") what is here is what a player would really set; the rest stay as console settings, on for all: autorun/alex_mercer_menu_out.lua
-- every setting the addon has, for "Reset to default" (each one back to the value it was created with)
local ALL = {"alex_mercer_hp_scale", "alex_mercer_dmg_scale", "alex_mercer_air_dashes", "alex_mercer_turn_speed",
	"alex_mercer_wall_turn", "alex_mercer_sprint_level", "alex_mercer_sprint_accel", "alex_mercer_trails",
	"alex_mercer_footik", "alex_mercer_walk_toggle", "alex_mercer_shove", "alex_mercer_friendly", "alex_mercer_minimap", "alex_mercer_gore",
	"alex_mercer_gore_debug", "alex_mercer_hit_reactions", "alex_mercer_heavy_hit", "alex_mercer_knockback_immunity", "alex_mercer_hit_cuts",
	"alex_mercer_devastator_free", "alex_mercer_dust", "alex_mercer_radialblur", "alex_mercer_bare_damage",
	"alex_mercer_claws_damage", "alex_mercer_gun_damage", "alex_mercer_wheel_key", "alex_mercer_game_air_keys",
	"alex_mercer_jump_level", "alex_mercer_air_dash_long", "alex_mercer_dust_native", "alex_mercer_dash_fx",
	"alex_mercer_land_run", "alex_mercer_land_huge", "alex_mercer_disguise_sight", "alex_mercer_consume_active",
	"alex_mercer_vest", "alex_mercer_jump_edges", "alex_mercer_vehicle_damage", "alex_mercer_mass_launch",
	"alex_mercer_car_vault", "alex_mercer_shield_slot", "alex_mercer_lock_vehicles", "alex_mercer_dive_hard",
	"alex_mercer_camera_game", "alex_mercer_camera_air_keep", "alex_mercer_camera_wall_keep", "alex_mercer_hunter_grab", "alex_mercer_shine_game", "alex_mercer_footprints",
	"alex_mercer_strike_speed", "alex_mercer_claw_speed", "alex_mercer_sharp_controls", "alex_mercer_strike_magnet", "alex_mercer_whip_step",
	"alex_mercer_camera_follow", "alex_mercer_camera_game_lag", "alex_mercer_hunter_glide_knock", "alex_mercer_muscle_throw",
	"alex_mercer_climb_catch", "alex_mercer_wall_overhang", "alex_mercer_wall_poses", "alex_mercer_air_unstick", "alex_mercer_ball_land", "alex_mercer_dive_video", "alex_mercer_wall_top_soft", "alex_mercer_stealth_nolook", "alex_mercer_throw_run", "alex_mercer_slowmo_graph", "alex_mercer_missile_grab", "alex_mercer_air_grab", "alex_mercer_disguise_rates", "alex_mercer_anim_every_tick", "alex_mercer_fill_ticks", "alex_mercer_camera_run_lag", "alex_mercer_fkick_graph", "alex_mercer_lock_game", "alex_mercer_jump_graph", "alex_mercer_shove_small", "alex_mercer_camera_lead", "alex_mercer_camera_wall_cone", "alex_mercer_vault_graph", "alex_mercer_wall_jump_graph", "alex_mercer_camera_wall_center"}
local function resetAll()
	for _, n in ipairs(ALL) do
		local cv = GetConVar(n)
		if cv then RunConsoleCommand(n, cv:GetDefault()) end
	end
	surface.PlaySound("buttons/button14.wav")
end
hook.Add("PopulateToolMenu", "alex_mercer_menu", function()
	spawnmenu.AddToolMenuOption("DrGBase", "Prototype", "alex_mercer_settings", "Alex Mercer", "", "", function(panel)
		-- (user: no cap - any number typed in, Enter to apply)
		panel:TextEntry("Health multiplier", "alex_mercer_hp_scale")
		panel:ControlHelp("Type any number, Enter. Original health: 3000 (x1). Critical mass from consuming goes up to half "
			.. "of it again on top.")
		panel:TextEntry("Damage multiplier", "alex_mercer_dmg_scale")
		panel:ControlHelp("Type any number, Enter. Scales all the damage he deals: fists, powers, devastators. 1 = original.")
		panel:NumSlider("Strike speed", "alex_mercer_strike_speed", 0.5, 3, 2)
		panel:ControlHelp("How fast his strikes play, LMB and RMB, for every power. Not the devastators. 1 = the game's own.")
		panel:NumSlider("Claws strike speed", "alex_mercer_claw_speed", 0.5, 3, 2)
		panel:ControlHelp("On top of the strike speed, for the Claws only. 1 = the game's own.")
		panel:NumSlider("Air dashes per jump (Ctrl)", "alex_mercer_air_dashes", 0, 10, 0)
		panel:ControlHelp("How many air dashes he gets before landing. The game: 2.")
		panel:NumSlider("Turning speed", "alex_mercer_turn_speed", 0.25, 6, 2)
		panel:ControlHelp("How fast he turns when running and sprinting. 1 = the game's own (heavy with a mouse), 2 = default.")
		panel:NumSlider("Turning speed on walls", "alex_mercer_wall_turn", 0.25, 6, 2)
		panel:ControlHelp("How fast he changes direction while running on a wall. 1 = the game's own (80 deg/s), 2 = twice as fast.")
		panel:NumSlider("Jump upgrades", "alex_mercer_jump_level", 0, 4, 0)
		panel:ControlHelp("The game's Jump 1-4 upgrades: how high the fully charged jump goes. 4 = 40 m standing / 25 m running, 0 = 7 m.")
		panel:CheckBox("Long air dash upgrade", "alex_mercer_air_dash_long")
		panel:ControlHelp("The game's AirDashLong: the air dash pushes longer and faster (45 m/s), going much farther.")
		panel:NumSlider("Sprint upgrades", "alex_mercer_sprint_level", 0, 3, 0)
		panel:ControlHelp("The game's Sprint 1-3 upgrades: 0 = 13 m/s top speed ... 3 = 20 m/s.")
		panel:NumSlider("Motion trails strength", "alex_mercer_trails", 0, 4, 1)
		panel:ControlHelp("The red ribbons on jumps, flips, the glide and strikes: 1 = as in the game, 0 = off.")
		panel:CheckBox("Air dash / glide on Shift (like the game)", "alex_mercer_game_air_keys")
		panel:ControlHelp("On = in the air tap Shift for the air dash, hold Shift for the glide, as in Prototype. Off = "
			.. "Ctrl air dash, Alt glide.")
		panel:CheckBox("Walk toggle (Alt)", "alex_mercer_walk_toggle")
		panel:ControlHelp("On = Alt on the ground switches walking on / off (the sprint switches it off). Off = he walks "
			.. "only while Alt is held. In the air Alt is the glide either way.")
		panel:CheckBox("Shove people", "alex_mercer_shove")
		panel:ControlHelp("Running into people shoves them aside; in the armour he bashes them away on the sprint. Off = he "
			.. "runs past without touching them.")
		panel:CheckBox("Minimap", "alex_mercer_minimap")
		panel:ControlHelp("The game's minimap bottom left while you play as him: the map under him from above.")
		panel:CheckBox("Friendly to players (AI)", "alex_mercer_friendly")
		panel:ControlHelp("The AI Alex leaves players and their allied NPCs alone until one of them attacks him - that one "
			.. "becomes his enemy.")
		-- (the NPC pack's Hunters: shown only with the pack there - without it the setting does nothing)
		if scripted_ents.GetStored("drg_proto_hunter") then
			panel:CheckBox("Grab / throw / consume Hunters (NPC pack)", "alex_mercer_hunter_grab")
			panel:ControlHelp("E at a Hunter: the game's brawler grab. In its first half second LMB throws it, RMB consumes it when stunned or at 15 % health or under; else it shoves him off.")
		end
		panel:CheckBox("Dismemberment / gore", "alex_mercer_gore")
		panel:ControlHelp("Claws, blades and ground spikes cut the humans they kill in two, "
			.. "with blood. Off = plain corpses.")
		panel:CheckBox("Hit reactions", "alex_mercer_hit_reactions")
		panel:ControlHelp("As in the game: bullets don't move him; a blow pushes him back by its side; a heavy blow, a "
			.. "blast or a car throws him (Space in the air = recover, otherwise he breakfalls on landing). Off = he takes "
			.. "the damage without reacting.")
		panel:NumSlider("Heavy blow (% of his max health)", "alex_mercer_heavy_hit", 1, 100, 0)
		panel:ControlHelp("A blow taking at least this share of his max health throws him; a smaller one only pushes him.")
		panel:NumSlider("Knockback immunity (s)", "alex_mercer_knockback_immunity", 0, 15, 1)
		panel:ControlHelp("After he lands from being thrown: this many seconds with no hit reactions (damage still counts).")
		panel:CheckBox("Devastators without critical mass", "alex_mercer_devastator_free")
		panel:ControlHelp("Devastators (hold LMB+RMB, LMB+E or RMB+E to the full charge) normally need critical mass - "
			.. "the health bar's overflow from consuming. On = always, to try them out.")
		panel:Button("Reset to default").DoClick = resetAll
		panel:ControlHelp("Every Alex Mercer setting back to the mod's own value.")
		panel:Help("Tab while playing as him: lock onto a target (instead of the scoreboard), Tab again to let go. The "
			.. "camera turns to it, his attacks fly at it (elbow drop, stomp, flying kick, air attacks, throws); hold Tab "
			.. "and move the mouse left / right to switch targets.")
	end)
end)
-