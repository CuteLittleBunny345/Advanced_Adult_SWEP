- (players 2026-11-03: "i keep pressing space, i can't jump") alex_mercer_jump_check, typed in the console while playing
-- as him: 10 s to press Space a few times, then a report of the jump key's whole way - what it is bound to, the presses
-- the client and the server saw, his state at each press (why it did nothing), whether the think reaches the key at all,
-- the hooks on the user command, the movement addons. Printed and copied to the clipboard for the player to send; it
-- only reads, and goes nowhere by itself.
AddCSLuaFile()

local SECS = 10
local NET = "alex_mercer_jump_check"

local function hookNames(event)
	local out = {}
	for k in pairs(hook.GetTable()[event] or {}) do out[#out + 1] = tostring(k) end
	table.sort(out)
	return event .. " (" .. #out .. "): " .. table.concat(out, ", ", 1, math.min(#out, 30))
end
local function yn(v) return v and 1 or 0 end

if SERVER then
	util.AddNetworkString(NET)
	local nextRun = {}
	-- what MercerJumpCharge tests, in its order
	local function stateLine(m, t)
		local n = m.MercerNode
		return string.format("  %5.2f s  ground=%d anim=%d node=%s wall=%d bullet=%d grind=%d charging=%d grab=%d",
			t, yn(m:IsOnGround()), yn(m:IsPlayingAnimation()), n and n.path or "-", yn(m:GetNW2Bool("MercerWall")),
			yn(m.MercerBullet), yn(m.MercerGrind), yn(m.MercerChargeStart), yn(m.MercerGrab))
	end
	net.Receive(NET, function(_, ply)
		if CurTime() < (nextRun[ply] or 0) then return end
		nextRun[ply] = CurTime() + SECS + 5
		local m = ply.DrG_Possessing and ply:DrG_Possessing()
		if not IsValid(m) or m:GetClass() ~= "drg_alex_mercer" then return end
		local id = NET .. ply:EntIndex()
		local t0 = CurTime()
		local thinks0 = m.MercerJumpThinks or 0
		local R = {press = 0, pressTick = 0, release = 0, ticks = 0, charges = 0, jumps = 0, lines = {}}
		local tickWas = false
		hook.Add("KeyPress", id, function(p, key)
			if p ~= ply or key ~= IN_JUMP or not IsValid(m) then return end
			R.press = R.press + 1
			if #R.lines < 12 then R.lines[#R.lines + 1] = stateLine(m, CurTime() - t0) end
		end)
		hook.Add("KeyRelease", id, function(p, key)
			if p == ply and key == IN_JUMP then R.release = R.release + 1 end
		end)
		-- (KeyPressed as a tick sees it: what the old way of reading the key got)
		hook.Add("Tick", id, function()
			R.ticks = R.ticks + 1
			local k = IsValid(ply) and ply:KeyPressed(IN_JUMP) or false
			if k and not tickWas then R.pressTick = R.pressTick + 1 end
			tickWas = k
		end)
		-- the two calls counted for these seconds (on this entity only; taken off below)
		local charge, release = m.MercerJumpCharge, m.MercerJumpRelease
		m.MercerJumpCharge = function(e)
			local was = e.MercerChargeStart
			local r = charge(e)
			if e.MercerChargeStart and not was then R.charges = R.charges + 1 end
			return r
		end
		m.MercerJumpRelease = function(e)
			if e.MercerChargeStart or e.MercerWallCharge then R.jumps = R.jumps + 1 end
			return release(e)
		end
		timer.Simple(SECS, function()
			hook.Remove("KeyPress", id)
			hook.Remove("KeyRelease", id)
			hook.Remove("Tick", id)
			local thinks = 0
			if IsValid(m) then
				m.MercerJumpCharge, m.MercerJumpRelease = nil, nil
				thinks = (m.MercerJumpThinks or 0) - thinks0
			end
			if not IsValid(ply) then return end
			local upd, edges = GetConVar("nb_update_frequency"), GetConVar("alex_mercer_jump_edges")
			local out = {
				string.format("server: singleplayer=%d dedicated=%d tick=%.1f nb_update_frequency=%s jump_edges=%s",
					yn(game.SinglePlayer()), yn(game.IsDedicated()), 1 / engine.TickInterval(), upd and upd:GetString() or "?",
					edges and edges:GetString() or "?"),
				string.format("the think reached the key %d times in %d ticks (0 = a Lua error stops it: send the red text too)",
					thinks, R.ticks),
				string.format("server presses: KeyPress hook %d, KeyPressed at a tick %d; releases %d", R.press, R.pressTick, R.release),
				string.format("charges started %d, releases with a charge %d", R.charges, R.jumps),
				"his state at each press:",
			}
			for _, l in ipairs(R.lines) do out[#out + 1] = l end
			for _, e in ipairs({"StartCommand", "SetupMove", "Move", "FinishMove", "KeyPress"}) do
				out[#out + 1] = "server hooks " .. hookNames(e)
			end
			net.Start(NET)
			net.WriteString(table.concat(out, "\n"))
			net.Send(ply)
		end)
	end)
else
	-- addons that often touch the jump key or the movement, by their titles
	local WORDS = {"hop", "jump", "movement", "stamina", "parkour", "prone", "sprint", "dodge", "climb", "slide", "vault"}
	local function addonLines()
		local mounted, drg, near = 0, "not found", {}
		for _, a in ipairs(engine.GetAddons() or {}) do
			if a.mounted then
				mounted = mounted + 1
				local low = string.lower(a.title or "")
				if string.find(low, "drgbase", 1, true) then drg = (a.title or "?") .. " (" .. tostring(a.wsid) .. ")" end
				for _, w in ipairs(WORDS) do
					if string.find(low, w, 1, true) then
						near[#near + 1] = a.title
						break
					end
				end
			end
		end
		return {"addons mounted: " .. mounted .. "; DrGBase: " .. drg,
			"movement-like addons: " .. (#near > 0 and table.concat(near, "; ", 1, math.min(#near, 20)) or "none")}
	end
	local running
	local function finish(serverText)
		timer.Remove(NET)
		hook.Remove("Think", NET)
		hook.Remove("CreateMove", NET)
		local C = running
		running = nil
		if not C then return end
		local cmdrate, updrate = GetConVar("cl_cmdrate"), GetConVar("cl_updaterate")
		local bound = C.bound
		local out = {"---- Mercer jump check: copy from here ----",
			string.format("client: fps=%.0f cl_cmdrate=%s cl_updaterate=%s branch=%s version=%s",
				C.frames / math.max(RealTime() - C.t0, 0.01), cmdrate and cmdrate:GetString() or "?",
				updrate and updrate:GetString() or "?", tostring(BRANCH), tostring(VERSIONSTR)),
			"+jump is bound to: " .. tostring(bound) .. "; SPACE runs: " .. tostring(input.LookupKeyBinding(KEY_SPACE)),
			string.format("client presses: the key %d, user commands with jump %d", C.key, C.cmd)}
		for _, l in ipairs(addonLines()) do out[#out + 1] = l end
		for _, e in ipairs({"CreateMove", "StartCommand", "SetupMove", "PlayerBindPress"}) do
			out[#out + 1] = "client hooks " .. hookNames(e)
		end
		out[#out + 1] = serverText or "server: no answer"
		out[#out + 1] = "---- to here ----"
		local text = table.concat(out, "\n")
		for _, l in ipairs(out) do MsgN(l) end
		SetClipboardText(text)
		chat.AddText(Color(255, 200, 120), "[Mercer] Jump check done: the report is in the console and on your clipboard.")
	end
	concommand.Add(NET, function()
		if running then return end
		local ply = LocalPlayer()
		local m = ply.DrG_Possessing and ply:DrG_Possessing()
		if not IsValid(m) or m:GetClass() ~= "drg_alex_mercer" then
			MsgN("[Mercer] Play as Alex Mercer first (possess him), then run alex_mercer_jump_check again.")
			return
		end
		local bound = input.LookupBinding("+jump")
		local code = bound and input.GetKeyCode(bound) or 0
		local C = {key = 0, cmd = 0, frames = 0, t0 = RealTime(), bound = bound}
		running = C
		local keyWas, cmdWas = false, false
		hook.Add("Think", NET, function()
			C.frames = C.frames + 1
			local d = code > 0 and input.IsButtonDown(code) or false
			if d and not keyWas then C.key = C.key + 1 end
			keyWas = d
		end)
		hook.Add("CreateMove", NET, function(cmd)
			local d = cmd:KeyDown(IN_JUMP)
			if d and not cmdWas then C.cmd = C.cmd + 1 end
			cmdWas = d
		end)
		net.Start(NET)
		net.SendToServer()
		-- (no answer from the server: still the client's half)
		timer.Create(NET, SECS + 6, 1, function() finish(nil) end)
		chat.AddText(Color(255, 200, 120), "[Mercer] Jump check: press your jump key a few times over the next 10 seconds.")
	end)
	net.Receive(NET, function() finish(net.ReadString()) end)
end
-