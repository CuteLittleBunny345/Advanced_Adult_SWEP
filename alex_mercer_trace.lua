- (user 2026-11-04: "При прыжках и некоторых действиях как будто рванно двигается... там как будто фпс проседает либо же он действительно рванно двигается")
-- mercer_trace, typed in the console while playing as him: 20 s, then it stops by itself. Into garrysmod/data/alex_mercer_trace.txt: a row for every frame
-- drawn (the frame's time, where he is drawn, the raw network place, his pelvis, his hand, the camera, the sequence and cycle) and, in single player or as
-- the host, a row for every server tick (what the server set, how often its callbacks ran). It shows whether the frame time jumps (FPS) or his pose does at
-- even frames; the summary is at the file's top, tools/trace_read.py reads the rest. Off until typed, no setting, no checkbox. It only reads, but for this, put back at the end,
-- so that the same run measures each, 7 s apiece: as it is (alex_mercer_anim_every_tick's flag off whatever the setting), the flag, the flag and his lost ticks filled (alex_mercer_fill_ticks), off again (that it comes off).
-- mercer_mem, typed the same way: 10 s, who makes the Lua garbage, below.
AddCSLuaFile()

local NET = "alex_mercer_trace"
local FILE = "alex_mercer_trace.txt"
local SECS = 28
local THIRD2, THIRD3, THIRD4 = 7, 14, 21

if SERVER then
	util.AddNetworkString(NET)
	local COUNTED = {"BodyUpdate", "PossessionControls", "CustomThink"}
	local rec
	local function unwrap(r)
		if IsValid(r.m) then
			for name, orig in pairs(r.orig) do r.m[name] = orig end
			r.m.MercerFillOn = nil
			r.m:MercerEveryTickSet(r.m.MercerEveryTick:GetBool() and game.SinglePlayer())
		end
		r.m, r.orig = nil, {}
	end
	local function stop()
		local r = rec
		rec = nil
		hook.Remove("Tick", NET)
		unwrap(r)
		local out = {"[server] t dt cur x y z vx vy vz seq cyc rate ground node body controls think phase mem", "[server flag] off: " .. tostring(r.flagOff) .. "; on: " .. tostring(r.flagOn) .. "; off again: " .. tostring(r.flagAgain)}
		for _, v in ipairs(r.rows) do out[#out + 1] = v end
		out[#out + 1] = "[server sequences] " .. table.concat(r.seqs, " ")
		out[#out + 1] = "[server nodes] " .. table.concat(r.nodes, " ")
		file.Append(FILE, table.concat(out, "\n") .. "\n")
	end
	-- the id of a name in a list written at the end
	local function idOf(list, ids, name)
		local i = ids[name]
		if not i then
			list[#list + 1] = (#list + 1) .. "=" .. name
			i = #list
			ids[name] = i
		end
		return i
	end
	local function tick()
		local r = rec
		if not r then return end
		local now = SysTime()
		if now >= r.stopAt or not IsValid(r.ply) then return stop() end
		local m = r.ply.DrG_Possessing and r.ply:DrG_Possessing()
		if not IsValid(m) or m:GetClass() ~= "drg_alex_mercer" then return end
		if m ~= r.m then
			unwrap(r)
			r.m = m
			for i, name in ipairs(COUNTED) do
				local orig = m[name]
				r.orig[name] = orig
				m[name] = function(...)
					r.calls[i] = r.calls[i] + 1
					return orig(...)
				end
			end
			if not r.plain then r.flagOff = m:MercerEveryTickSet(false) end
			r.phase = 0
		end
		if r.plain then
			r.phase = 0
		elseif r.phase == 0 and now - r.t0 >= THIRD2 then
			r.flagOn = m:MercerEveryTickSet(true)
			r.phase = 1
		elseif r.phase == 1 and now - r.t0 >= THIRD3 then
			m.MercerFillOn = true
			r.phase = 2
		elseif r.phase == 2 and now - r.t0 >= THIRD4 then
			m.MercerFillOn = nil
			r.flagAgain = m:MercerEveryTickSet(false)
			r.phase = 3
		end
		-- (the place the last tick sent: this hook may come after the one that takes a filled tick's back)
		local p, v = m.MercerFillSent or m:GetPos(), m.loco:GetVelocity()
		m.MercerFillSent = nil
		local c = r.calls
		local mem = collectgarbage("count")
		local seq = idOf(r.seqs, r.seqIds, m:GetSequenceName(m:GetSequence()) or "?")
		local node = m.MercerNode and idOf(r.nodes, r.nodeIds, m.MercerNode.path) or 0
		r.rows[#r.rows + 1] = string.format("S %.2f %.2f %.3f %.2f %.2f %.2f %.1f %.1f %.1f %d %.4f %.2f %d %d %d %d %d %d %d", (now - r.t0) * 1000, (now - r.last) * 1000, CurTime(),
			p.x, p.y, p.z, v.x, v.y, v.z, seq, m:GetCycle(), m:GetPlaybackRate(), m:IsOnGround() and 1 or 0, node, c[1], c[2], c[3], r.phase or 0, mem - (r.mem or mem))
		r.mem = mem
		r.last = now
		r.calls = {0, 0, 0}
	end
	net.Receive(NET, function(_, ply)
		if rec or not (game.SinglePlayer() or ply:IsListenServerHost()) then return end
		local now = SysTime()
		-- (mercer_trace <seconds>: nothing switched, the game as it stands)
		local secs = net.ReadFloat()
		rec = {ply = ply, t0 = now, last = now, stopAt = now + (secs > 0 and secs or SECS), plain = secs > 0, rows = {}, seqs = {}, seqIds = {}, nodes = {}, nodeIds = {}, calls = {0, 0, 0}, orig = {}}
		hook.Add("Tick", NET, tick)
	end)
	return
end

-- t dt ticks cur | x y z (drawn) | nx ny nz (raw network) | yaw | px py pz (pelvis) | hx hy hz (right wrist) | cx cy cz (camera) | cyaw cpitch | seq cyc rate ground | v vz (the engine's estimate) | mem | phase (1: the flag on, 2: and the lost ticks filled, 3: off again)
local COLS = "t dt ticks cur x y z nx ny nz yaw px py pz hx hy hz cx cy cz cyaw cpitch seq cyc rate ground v vz mem phase"
local FORMAT = "C %.2f %.2f %d %.3f %.2f %.2f %.2f %.2f %.2f %.2f %.1f %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.1f %.1f %d %.4f %.2f %d %.1f %.1f %d %d"
local N = 30
local T, DT, TICKS, X, Y, Z, PX, PY, PZ, HX, HY, HZ, CX, CY, CZ, SEQ, CYC, GROUND, PHASE = 1, 2, 3, 5, 6, 7, 12, 13, 14, 15, 16, 17, 18, 19, 20, 23, 24, 26, 30
local rec

local function his()
	local p = LocalPlayer()
	local m = IsValid(p) and p.DrG_Possessing and p:DrG_Possessing()
	if IsValid(m) and m:GetClass() == "drg_alex_mercer" then return m end
end

local function median(list)
	local s = {}
	for i, v in ipairs(list) do s[i] = v end
	table.sort(s)
	return s[math.ceil(#s / 2)] or 0, s[math.ceil(#s * 0.95)] or 0, s[#s] or 0
end

-- at even frame times: a speed far off the median of its neighbours is a jump of that thing itself, not of the frame
local function jumps(speeds, even, phase, floor)
	local n = 0
	for i = 4, #speeds - 3 do
		if even[i] and phase[i] then
			local near = {speeds[i - 3], speeds[i - 2], speeds[i - 1], speeds[i + 1], speeds[i + 2], speeds[i + 3]}
			table.sort(near)
			local mid = (near[3] + near[4]) / 2
			if math.abs(speeds[i] - mid) > math.max(0.6 * mid, floor) then n = n + 1 end
		end
	end
	return n
end

-- each sequence's start: how long the cycle stood before it moved, and how much of the anim that first move was: the client's stand and leap
local function starts(r, phase)
	local d = r.d
	local n = math.floor(#d / N)
	local stood, leapt, count = {}, {}, 0
	for i = 2, n - 1 do
		local b = (i - 1) * N
		if d[b + PHASE] == phase and d[b + SEQ] ~= d[b - N + SEQ] then
			local seq, t0 = d[b + SEQ], d[b + T]
			for j = i + 1, n do
				local c = (j - 1) * N
				if d[c + SEQ] ~= seq or d[c + T] - t0 > 400 then break end
				local step = d[c + CYC] - d[c - N + CYC]
				if math.abs(step) > 0.0005 then
					count = count + 1
					stood[count], leapt[count] = d[c - N + T] - t0, math.abs(step) * (r.durs[seq] or 0) * 1000
					break
				end
			end
		end
	end
	return count, median(stood), median(leapt)
end

local function summary(r)
	local d = r.d
	local n = math.floor(#d / N)
	if n < 10 then return {"# too few frames: " .. n} end
	local dts, ticks = {}, {[0] = 0, 0, 0, 0}
	for i = 1, n do
		dts[i] = d[(i - 1) * N + DT]
		local k = math.min(d[(i - 1) * N + TICKS], 3)
		ticks[k] = ticks[k] + 1
	end
	local med, p95, worst = median(dts)
	local long, even, pos, body, hand, cam, air, ground = 0, {}, {}, {}, {}, {}, {}, {}
	local function len(a, b, c) return math.sqrt(a * a + b * b + c * c) end
	pos[1], body[1], hand[1], cam[1], even[1], air[1], ground[1] = 0, 0, 0, 0, false, false, false
	for i = 2, n do
		local a, b = (i - 2) * N, (i - 1) * N
		local dt = math.max(d[b + DT], 0.1) / 1000
		if d[b + DT] > med * 2 then long = long + 1 end
		even[i] = math.abs(d[b + DT] - med) < med * 0.3
		air[i], ground[i] = d[b + GROUND] == 0, d[b + GROUND] == 1
		local sx, sy, sz = d[b + X] - d[a + X], d[b + Y] - d[a + Y], d[b + Z] - d[a + Z]
		pos[i] = len(sx, sy, sz) / dt
		body[i] = len(d[b + PX] - d[a + PX] - sx, d[b + PY] - d[a + PY] - sy, d[b + PZ] - d[a + PZ] - sz) / dt
		hand[i] = len(d[b + HX] - d[a + HX] - sx, d[b + HY] - d[a + HY] - sy, d[b + HZ] - d[a + HZ] - sz) / dt
		cam[i] = len(d[b + CX] - d[a + CX], d[b + CY] - d[a + CY], d[b + CZ] - d[a + CZ]) / dt
	end
	local out = {string.format("# %d frames, %.0f fps; frame time ms: median %.1f, 95%% %.1f, worst %.1f; over twice the median: %d (%.1f%%)", n, (n - 1) / math.max((d[(n - 1) * N + T] - d[T]) / 1000, 0.001),
		med, p95, worst, long, long / n * 100),
		string.format("# server ticks in a frame: none %d, one %d, two %d, more %d", ticks[0], ticks[1], ticks[2], ticks[3])}
	local shares = {}
	for name, phase in pairs({air = air, ground = ground}) do
		local frames = 0
		for i = 1, n do if phase[i] and even[i] then frames = frames + 1 end end
		local a, b, c, e = jumps(pos, even, phase, 60), jumps(body, even, phase, 120), jumps(hand, even, phase, 200), jumps(cam, even, phase, 60)
		out[#out + 1] = string.format("# %s, %d even frames: jumps of the place %d, the body %d, the hand %d, the camera %d", name, frames, a, b, c, e)
		shares[name] = (a + b + c + e) / math.max(frames, 1)
	end
	out[#out + 1] = string.format("# what jumps: %s; %s", long / n > 0.05 and "the frame time (FPS)" or "not the frame time", (shares.air or 0) > 0.05 and "at even frames, in the air, he does too" or "at even frames he hardly does")
	if r.plain then
		local count, stood, leapt = starts(r, 0)
		out[#out + 1] = string.format("# as it stands, the flag %s: %d sequence starts: the pose stood %.0f ms, then its first move was %.0f ms of the anim (median)", GetConVar("alex_mercer_anim_every_tick") and GetConVar("alex_mercer_anim_every_tick"):GetString() or "?", count, stood, leapt)
		return out
	end
	for phase, name in ipairs({[1] = "7-14 s, the flag on", [2] = "14-21 s, the flag on and the lost ticks filled", [3] = "21-28 s, off again"}) do
		local count, stood, leapt = starts(r, phase)
		out[#out + 1] = string.format("# %s: %d sequence starts: the pose stood %.0f ms, then its first move was %.0f ms of the anim (median)", name, count, stood, leapt)
	end
	local count, stood, leapt = starts(r, 0)
	table.insert(out, #out - 2, string.format("# 0-7 s, as it is: %d sequence starts: the pose stood %.0f ms, then its first move was %.0f ms of the anim (median)", count, stood, leapt))
	return out
end

local function stop()
	local r = rec
	rec = nil
	hook.Remove("RenderScene", NET)
	hook.Remove("PostRender", NET)
	hook.Remove("HUDPaint", NET)
	local head = summary(r)
	local out = {}
	for _, line in ipairs(head) do
		out[#out + 1] = line
		MsgN("[Mercer] " .. line)
	end
	out[#out + 1] = "[client] " .. COLS
	local d, row = r.d, {}
	for i = 0, math.floor(#d / N) - 1 do
		for j = 1, N do row[j] = d[i * N + j] end
		out[#out + 1] = string.format(FORMAT, unpack(row, 1, N))
	end
	local names = {}
	for seq, name in pairs(r.seqs) do names[#names + 1] = seq .. "=" .. name .. ":" .. string.format("%.3f", r.durs[seq] or 0) end
	out[#out + 1] = "[client sequences] " .. table.concat(names, " ")
	file.Append(FILE, table.concat(out, "\n") .. "\n")
	MsgN("[Mercer] mercer_trace done: garrysmod/data/" .. FILE)
end

local function sample()
	local r = rec
	local now = SysTime()
	local dt = now - r.last
	r.last = now
	if now >= r.stopAt then return stop() end
	local m = his()
	if not m then return end
	local mdl = m:GetModel()
	if mdl ~= r.mdl then r.mdl, r.pelvis, r.hand = mdl, m:LookupBone("Pelvis"), m:LookupBone("Wrist_R") end
	local pm, hm = r.pelvis and m:GetBoneMatrix(r.pelvis), r.hand and m:GetBoneMatrix(r.hand)
	local pp, hp = pm and pm:GetTranslation() or vector_origin, hm and hm:GetTranslation() or vector_origin
	local p, np, v = m:GetPos(), m:GetNetworkOrigin(), m:GetVelocity()
	local seq = m:GetSequence()
	if not r.seqs[seq] then r.seqs[seq], r.durs[seq] = m:GetSequenceName(seq) or "?", m:SequenceDuration(seq) end
	local tk = engine.TickCount()
	local mem = collectgarbage("count")
	local d, b = r.d, #r.d
	d[b + 1], d[b + 2], d[b + 3], d[b + 4] = (now - r.t0) * 1000, dt * 1000, tk - r.tick, UnPredictedCurTime()
	d[b + 5], d[b + 6], d[b + 7] = p.x, p.y, p.z
	d[b + 8], d[b + 9], d[b + 10] = np.x, np.y, np.z
	d[b + 11] = m:GetAngles().y
	d[b + 12], d[b + 13], d[b + 14] = pp.x, pp.y, pp.z
	d[b + 15], d[b + 16], d[b + 17] = hp.x, hp.y, hp.z
	d[b + 18], d[b + 19], d[b + 20] = r.cx, r.cy, r.cz
	d[b + 21], d[b + 22] = r.cyaw, r.cpitch
	d[b + 23], d[b + 24], d[b + 25], d[b + 26] = seq, m:GetCycle(), m:GetPlaybackRate(), m:GetNW2Bool("DrGBaseOnGround") and 1 or 0
	d[b + 27], d[b + 28] = v:Length(), v.z
	local run = now - r.t0
	d[b + 29], d[b + 30] = mem - r.mem, r.plain and 0 or run >= THIRD4 and 3 or run >= THIRD3 and 2 or run >= THIRD2 and 1 or 0
	r.tick, r.mem = tk, mem
end

concommand.Add("mercer_trace", function(_, _, cmdArgs)
	if rec then MsgN("[Mercer] mercer_trace is running") return end
	if not his() then MsgN("[Mercer] Play as Alex Mercer first") return end
	local now = SysTime()
	local secs = math.Clamp(tonumber(cmdArgs and cmdArgs[1] or "") or 0, 0, 60)
	rec = {t0 = now, last = now, stopAt = now + (secs > 0 and secs or SECS), plain = secs > 0, d = {}, seqs = {}, durs = {}, tick = engine.TickCount(), mem = collectgarbage("count"), cx = 0, cy = 0, cz = 0, cyaw = 0, cpitch = 0}
	file.Write(FILE, string.format("# mercer_trace %s, map %s, single player %s, tick %.4f, cl_interp %s, cl_updaterate %s, fps_max %s, game camera %s\n", os.date("%Y-%m-%d %H:%M:%S"), game.GetMap(), tostring(game.SinglePlayer()),
		engine.TickInterval(), GetConVar("cl_interp"):GetString(), GetConVar("cl_updaterate"):GetString(), GetConVar("fps_max"):GetString(), GetConVar("alex_mercer_camera_game") and GetConVar("alex_mercer_camera_game"):GetString() or "?"))
	-- the view as CalcView made it: the frame's own, whatever else renders later
	hook.Add("RenderScene", NET, function(origin, angles)
		local r = rec
		if r then r.cx, r.cy, r.cz, r.cyaw, r.cpitch = origin.x, origin.y, origin.z, angles.y, angles.p end
	end)
	hook.Add("PostRender", NET, sample)
	hook.Add("HUDPaint", NET, function()
		if rec then
			local left = rec.stopAt - SysTime()
			draw.SimpleText("mercer_trace " .. math.ceil(left) .. (rec.plain and "" or left > SECS - THIRD2 and " (1 of 4)" or left > SECS - THIRD3 and " (2 of 4)" or left > SECS - THIRD4 and " (3 of 4)" or " (4 of 4)"), "DermaDefaultBold", ScrW() / 2, 8, color_white, TEXT_ALIGN_CENTER)
		end
	end)
	net.Start(NET)
	net.WriteFloat(secs)
	net.SendToServer()
	MsgN(secs > 0 and ("[Mercer] mercer_trace: " .. secs .. " s, the game as it stands, nothing switched: sprint and jump") or "[Mercer] mercer_trace: 28 s, keep jumping: 7 s as it is, 7 s the flag, 7 s and the lost ticks filled, 7 s off again; they end with it")
end, nil, "Alex Mercer: 28 s of every frame and tick into data/" .. FILE .. ", for the jerks in his jumps")

-- mercer_mem [seconds, default 10], typed while playing as him: who makes the Lua garbage (mercer_trace: 143 KB a frame standing, 200-330 moving, a collector's run every 5.5 s, and it's what lengthens the frames that lose his update). Every hook with a
-- string name, his own Draw, Think and HUD, wrapped for that long and put back: KB and ms a frame each, worst first, into data/alex_mercer_mem.txt, with what's left over (what nothing wraps here: other entities' Draw and Think, panels, timers, bone callbacks, the net).
-- An inner hook counts in the outer one's call too. It changes nothing else
local MEMFILE, MEMWRAP = "alex_mercer_mem.txt", {"Draw", "DrawTranslucent", "Think", "PossessionHUD", "PossessionDraw", "PossessionRender", "RenderOverride"}
local mem
local function memWrap(key, fn)
	return function(...)
		local r = mem
		if not r then return fn(...) end
		local m, s = collectgarbage("count"), SysTime()
		local a, b, c, d, e, f = fn(...)
		local dm = collectgarbage("count") - m
		r.ms[key] = (r.ms[key] or 0) + SysTime() - s
		-- (the collector's own frees in the call say nothing of who made what)
		if dm > 0 then r.kb[key] = (r.kb[key] or 0) + dm end
		r.calls[key] = (r.calls[key] or 0) + 1
		return a, b, c, d, e, f
	end
end
local function memStop()
	local r = mem
	mem = nil
	hook.Remove("PostRender", MEMFILE)
	local now = hook.GetTable()
	for _, w in ipairs(r.hooks) do
		if now[w[1]] and now[w[1]][w[2]] == w[4] then hook.Add(w[1], w[2], w[3]) end
	end
	if IsValid(r.m) then
		for name, orig in pairs(r.orig) do r.m[name] = orig end
	end
	local list, sum = {}, 0
	for k, v in pairs(r.kb) do
		list[#list + 1] = k
		if not string.find(k, "^ENT:") then sum = sum + v end
	end
	table.sort(list, function(a, b) return r.kb[a] > r.kb[b] end)
	local n = math.max(r.frames, 1)
	local out = {string.format("# mercer_mem %s, map %s: %d frames, %.0f fps; Lua garbage %.0f KB a frame, %.1f MB/s; in the wrapped hooks %.0f KB a frame, the rest %.0f; collector's frees %.0f MB", os.date("%Y-%m-%d %H:%M:%S"), game.GetMap(), r.frames, r.frames / math.max(SysTime() - r.t0, 0.001),
		r.total / n, r.total / 1024 / math.max(SysTime() - r.t0, 0.001), sum / n, (r.total - sum) / n, r.freed / 1024), "KB/frame ms/frame calls/frame  who"}
	for _, k in ipairs(list) do
		out[#out + 1] = string.format("%8.1f %8.3f %8.1f  %s", r.kb[k] / n, (r.ms[k] or 0) * 1000 / n, (r.calls[k] or 0) / n, k)
	end
	file.Write(MEMFILE, table.concat(out, "\n") .. "\n")
	MsgN("[Mercer] " .. out[1])
	MsgN("[Mercer] mercer_mem done: garrysmod/data/" .. MEMFILE)
end
concommand.Add("mercer_mem", function(_, _, args)
	if mem then MsgN("[Mercer] mercer_mem is running") return end
	local r = {t0 = SysTime(), stopAt = SysTime() + math.Clamp(tonumber(args[1] or "") or 10, 2, 60), kb = {}, ms = {}, calls = {}, frames = 0, total = 0, freed = 0, last = collectgarbage("count"), hooks = {}, orig = {}}
	for ev, list in pairs(hook.GetTable()) do
		for name, fn in pairs(list) do
			if isstring(name) and isfunction(fn) and name ~= MEMFILE then
				r.hooks[#r.hooks + 1] = {ev, name, fn}
			end
		end
	end
	for _, w in ipairs(r.hooks) do
		w[4] = memWrap(w[1] .. "/" .. w[2], w[3])
		hook.Add(w[1], w[2], w[4])
	end
	r.m = his()
	if r.m then
		for _, name in ipairs(MEMWRAP) do
			local fn = r.m[name]
			if isfunction(fn) then
				r.orig[name] = fn
				r.m[name] = memWrap("ENT:" .. name, fn)
			end
		end
	end
	mem = r
	hook.Add("PostRender", MEMFILE, function()
		local q = mem
		if not q then return end
		local now = collectgarbage("count")
		local d = now - q.last
		q.last = now
		q.frames = q.frames + 1
		if d > 0 then q.total = q.total + d else q.freed = q.freed - d end
		if SysTime() >= q.stopAt then memStop() end
	end)
	MsgN("[Mercer] mercer_mem: " .. math.floor(r.stopAt - r.t0) .. " s, play on: run, jump")
end, nil, "Alex Mercer: who makes the Lua garbage, into data/" .. MEMFILE)
-