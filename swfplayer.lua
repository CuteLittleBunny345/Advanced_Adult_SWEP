- Minimal Flash (Scaleform) timeline player for Prototype's own HUD movies, exported by tools/hudexport.py:
-- every sprite stores its display list for each frame (char, 2D matrix, colour transform, instance name),
-- frame labels and the frames that call stop(). Instances play at 30 fps like Flash, can be driven like
-- ActionScript (GotoAndStop / GotoAndPlay / Child("a.b.c") / visible) and are drawn with the game's
-- textures. Colour transforms are exact: pass 1 = texture * multiply, pass 2 (additive) = add * alpha,
-- using a white silhouette of the same texture.
-- (2026-11-04, mercer_trace: the Lua collector's runs, 0.3-0.6 s every 5.5 s, hold the frames in which his NextBot update is lost) nothing here is made anew a frame: this player left 20-30 KB of tables and
-- strings a frame for it. The matrices and colours of a draw live on a stack of tables, a frame's display list keeps its keys. tools/hudalloc.py: the same draw calls to the number.
ALEX_MERCER_SWF = ALEX_MERCER_SWF or {}
local SWF = ALEX_MERCER_SWF
local FPS = 30
local NONE = {}
local function keyOf(e)
	local k = e.key
	if not k then
		k = e.d .. ":" .. e.c
		e.key = k
	end
	return k
end

local mats = {}
local function mat(stem)
	local m = mats[stem]
	if not m then
		m = Material("alex_mercer/hud/" .. stem .. ".png", "smooth")
		mats[stem] = m
	end
	return m
end
SWF.Material = mat

local Inst = {}
Inst.__index = Inst

-- movie = ALEX_MERCER_HUD[name]; char = sprite id
function SWF.New(movie, char)
	local inst = setmetatable({movie = movie, char = char or movie.root, frame = 0, playing = true, t = 0,
		kids = {}, visible = true}, Inst)
	inst:EnterFrame()
	return inst
end

function Inst:Sprite() return self.movie.sprites[self.char] end

function Inst:Stops()
	local sp = self:Sprite()
	if not sp then return {} end
	if not sp.stopSet then
		sp.stopSet = {}
		for _, f in ipairs(sp.stops or {}) do sp.stopSet[f] = true end
	end
	return sp.stopSet
end

-- Flash runs a frame's actions when the playhead enters it: stop() there halts the clip on that frame.
function Inst:EnterFrame()
	if self:Stops()[self.frame] then self.playing = false end
	local sp = self:Sprite()
	local j = sp and sp.jumps and sp.jumps[self.frame]
	if j and self.playing then
		local fr = self:Label(j)
		if fr and fr ~= self.frame then
			self.frame = fr
			if self:Stops()[self.frame] then self.playing = false end
		end
	end
	self:Sync()
end

function Inst:Label(f)
	if isstring(f) then
		local sp = self:Sprite()
		return sp and sp.labels[f]
	end
	return f
end

function Inst:GotoAndStop(f)
	local fr = self:Label(f)
	if not fr then return false end
	self.frame, self.playing, self.t = fr, false, 0
	self:Sync()
	return true
end

function Inst:GotoAndPlay(f)
	local fr = self:Label(f)
	if not fr then return false end
	self.frame, self.playing, self.t = fr, true, 0
	self:EnterFrame()
	return true
end

-- keep child instances in step with the current frame's display list (same depth + char = same clip)
function Inst:Sync()
	local sp = self:Sprite()
	if not sp then return end
	local dl = sp.frames[self.frame + 1] or NONE
	local alive = dl.alive
	if not alive then
		alive = {}
		for _, e in ipairs(dl) do alive[keyOf(e)] = true end
		if dl ~= NONE then dl.alive = alive end
	end
	for _, e in ipairs(dl) do
		local key = e.key
		if not self.kids[key] and self.movie.sprites[e.c] then
			local kid = setmetatable({movie = self.movie, char = e.c, frame = 0, playing = true, t = 0, kids = {},
				visible = true, name = e.n}, Inst)
			kid:EnterFrame()
			self.kids[key] = kid
		end
	end
	for key in pairs(self.kids) do
		if not alive[key] then self.kids[key] = nil end
	end
end

-- named child on the current frame ("powerring.Node3.icon")
local PATHS = {}
function Inst:Child(path)
	local cur = self
	local parts = PATHS[path]
	if not parts then
		parts = {}
		for part in string.gmatch(path, "[^%.]+") do parts[#parts + 1] = part end
		PATHS[path] = parts
	end
	for _, part in ipairs(parts) do
		local sp = cur:Sprite()
		if not sp then return end
		cur:Sync()
		local found
		for _, e in ipairs(sp.frames[cur.frame + 1] or NONE) do
			if e.n == part then found = cur.kids[keyOf(e)] break end
		end
		if not found then return end
		cur = found
	end
	return cur
end

function Inst:Advance(dt)
	local sp = self:Sprite()
	if not sp then return end
	if self.playing then
		self.t = self.t + dt
		local step = 1 / FPS
		while self.playing and self.t >= step do
			self.t = self.t - step
			self.frame = self.frame + 1
			if self.frame >= #sp.frames then self.frame = 0 end
			self:EnterFrame()
		end
	end
	for _, kid in pairs(self.kids) do kid:Advance(dt) end
end

-- 2D affine helpers: {a, b, c, d, tx, ty} with x' = a x + c y + tx, y' = b x + d y + ty
local function mul(p, q)
	return {p[1] * q[1] + p[3] * q[2], p[2] * q[1] + p[4] * q[2], p[1] * q[3] + p[3] * q[4],
		p[2] * q[3] + p[4] * q[4], p[1] * q[5] + p[3] * q[6] + p[5], p[2] * q[5] + p[4] * q[6] + p[6]}
end
SWF.Mul = mul

local function rotation(deg)
	local r = math.rad(deg)
	local c, s = math.cos(r), math.sin(r)
	return {c, s, -s, c, 0, 0}
end
SWF.Rotation = rotation

-- the same on the stack: what a draw makes lives until that Inst:Draw returns
local stack, top = {}, 0
local function slot()
	top = top + 1
	local t = stack[top]
	if not t then
		t = {}
		stack[top] = t
	end
	return t
end
local function pmul6(p, a, b, c, d, e, f)
	local t = slot()
	t[1], t[2], t[3], t[4], t[5], t[6] = p[1] * a + p[3] * b, p[2] * a + p[4] * b, p[1] * c + p[3] * d, p[2] * c + p[4] * d, p[1] * e + p[3] * f + p[5], p[2] * e + p[4] * f + p[6]
	return t
end
local function pmul(p, q) return pmul6(p, q[1], q[2], q[3], q[4], q[5], q[6]) end

-- parent colour transform applied over the child's: (tex * cm + ca) * pm + pa
local function cxmul(p, c)
	if not c then return p end
	if not p then return c end
	local t = slot()
	t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8] = p[1] * c[1], p[2] * c[2], p[3] * c[3], p[4] * c[4],
		p[1] * c[5] + p[5], p[2] * c[6] + p[6], p[3] * c[7] + p[7], p[4] * c[8] + p[8]
	return t
end

-- The movie plane can lean in 3D: SWF.Proj = {cx, cy, f, r} (pivot on screen, focal length in pixels, 3x3 rotation
-- row-major), nil = flat. Quads go out as screen-space polygons with their winding fixed up, so mirrored quads (the
-- ring's left half is its right half flipped: VGUI culled those -> "half a picture") draw like any other, and leaning
-- ones are split into a grid that follows the perspective.
local function project(x, y)
	local P = SWF.Proj
	if not P then return x, y end
	local qx, qy, r = x - P.cx, y - P.cy, P.r
	local k = P.f / (P.f + r[7] * qx + r[8] * qy)
	return P.cx + (r[1] * qx + r[2] * qy) * k, P.cy + (r[4] * qx + r[5] * qy) * k
end
SWF.Project = project

local grid, poly = {}, {}
local WHITE = setmetatable({}, {__index = function(t, stem)
	local name = stem .. "_w"
	t[stem] = name
	return name
end})
local function drawCells(n, cw)
	local row = n + 1
	for j = 0, n - 1 do
		for i = 0, n - 1 do
			local a, b = grid[j * row + i + 1], grid[j * row + i + 2]
			local c, d = grid[(j + 1) * row + i + 2], grid[(j + 1) * row + i + 1]
			-- surface.DrawPoly wants the vertices clockwise on screen
			if cw then
				poly[1], poly[2], poly[3], poly[4] = a, b, c, d
			else
				poly[1], poly[2], poly[3], poly[4] = a, d, c, b
			end
			surface.DrawPoly(poly)
		end
	end
end

local function drawQuad(stem, m, cx, x0, y0, x1, y1, u0, v0, u1, v1)
	local mr, mg, mb, ma = 1, 1, 1, 1
	local ar, ag, ab = 0, 0, 0
	if cx then
		mr, mg, mb, ma = cx[1], cx[2], cx[3], cx[4]
		ar, ag, ab = cx[5], cx[6], cx[7]
		ma = math.Clamp(ma + (cx[8] or 0), 0, 1)
	end
	if ma <= 0.002 then return end
	local n = 1
	if SWF.Proj then
		local wpx = math.sqrt(m[1] * m[1] + m[2] * m[2]) * math.abs(x1 - x0)
		local hpx = math.sqrt(m[3] * m[3] + m[4] * m[4]) * math.abs(y1 - y0)
		n = math.Clamp(math.ceil(math.max(wpx, hpx) / 40), 1, 10)
	end
	local k = 0
	for j = 0, n do
		local ly, v = y0 + (y1 - y0) * j / n, v0 + (v1 - v0) * j / n
		for i = 0, n do
			local lx = x0 + (x1 - x0) * i / n
			local sx, sy = project(m[1] * lx + m[3] * ly + m[5], m[2] * lx + m[4] * ly + m[6])
			k = k + 1
			local g = grid[k]
			if not g then
				g = {}
				grid[k] = g
			end
			g.x, g.y, g.u, g.v = sx, sy, u0 + (u1 - u0) * i / n, v
		end
	end
	local cw = (m[1] * m[4] - m[2] * m[3]) * (x1 - x0) * (y1 - y0) > 0
	surface.SetMaterial(mat(stem))
	surface.SetDrawColor(math.Clamp(mr, 0, 1) * 255, math.Clamp(mg, 0, 1) * 255, math.Clamp(mb, 0, 1) * 255, ma * 255)
	drawCells(n, cw)
	if ar > 0.002 or ag > 0.002 or ab > 0.002 then
		render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
		surface.SetMaterial(mat(WHITE[stem]))
		surface.SetDrawColor(math.Clamp(ar, 0, 1) * 255, math.Clamp(ag, 0, 1) * 255, math.Clamp(ab, 0, 1) * 255, ma * 255)
		drawCells(n, cw)
		render.OverrideBlend(false)
	end
end
SWF.DrawQuad = drawQuad

local IDENT = {1, 0, 0, 1, 0, 0}

function Inst:DrawChar(char, m, cx, entry)
	local movie = self.movie
	local sh = movie.shapes[char]
	if sh then
		if sh.quads then
			for _, q in ipairs(sh.quads) do
				drawQuad(movie.images[q[1]], m, cx, q[2], q[3], q[4], q[5], q[6], q[7], q[8], q[9])
			end
		elseif sh.png then
			drawQuad(sh.png, m, cx, sh.x, sh.y, sh.x + sh.w, sh.y + sh.h, 0, 0, 1, 1)
		end
		return
	end
	local tx = movie.texts and movie.texts[char]
	if tx and self.drawText then self.drawText(entry and entry.n, tx, m, cx) end
end

-- screen bounds of a char under matrix m (masks): {x0, y0, x1, y1}
local box = {}
local function grow(b, x, y)
	if not b then
		box[1], box[2], box[3], box[4] = x, y, x, y
		return box
	end
	b[1], b[2], b[3], b[4] = math.min(b[1], x), math.min(b[2], y), math.max(b[3], x), math.max(b[4], y)
	return b
end
local function growRect(b, m, x0, y0, x1, y1)
	b = grow(b, SWF.Apply(m, x0, y0))
	b = grow(b, SWF.Apply(m, x1, y0))
	b = grow(b, SWF.Apply(m, x0, y1))
	return grow(b, SWF.Apply(m, x1, y1))
end
function Inst:CharBounds(char, m, b, kid)
	local movie = self.movie
	local sh = movie.shapes[char]
	if sh then
		if sh.quads then
			for _, q in ipairs(sh.quads) do b = growRect(b, m, q[2], q[3], q[4], q[5]) end
		elseif sh.png then
			b = growRect(b, m, sh.x, sh.y, sh.x + sh.w, sh.y + sh.h)
		end
		return b
	end
	local sp = movie.sprites[char]
	if sp then
		for _, e in ipairs(sp.frames[(kid and kid.frame or 0) + 1] or NONE) do
			local mark = top
			b = self:CharBounds(e.c, e.m and pmul(m, e.m) or m, b, kid and kid.kids[keyOf(e)])
			top = mark
		end
	end
	return b
end

-- a mask into the stencil: its shapes' outlines (hudexport.py "outline": the filled path) as untextured polygons,
-- else their quads' rectangles; nothing of it shows (colour writes off, alpha 0)
local mpoly = {}
function Inst:MaskOutline(char, m, kid)
	local movie = self.movie
	local sh = movie.shapes[char]
	if sh then
		local o = sh.outline
		if not o then
			local q = sh.quads and sh.quads[1] or (sh.png and {0, sh.x, sh.y, sh.x + sh.w, sh.y + sh.h})
			if not q then return end
			o = {q[2], q[3], q[4], q[3], q[4], q[5], q[2], q[5]}
		end
		local n = #o / 2
		local area = 0
		for i = 1, n do
			local x, y = SWF.Apply(m, o[i * 2 - 1], o[i * 2])
			mpoly[i] = mpoly[i] or {}
			mpoly[i].x, mpoly[i].y = x, y
		end
		for i = n + 1, #mpoly do mpoly[i] = nil end
		for i = 1, n do
			local a, b = mpoly[i], mpoly[i % n + 1]
			area = area + a.x * b.y - b.x * a.y
		end
		-- (DrawPoly wants them clockwise on screen: y down -> positive area)
		if area < 0 then
			for i = 1, math.floor(n / 2) do mpoly[i], mpoly[n + 1 - i] = mpoly[n + 1 - i], mpoly[i] end
		end
		draw.NoTexture()
		surface.SetDrawColor(0, 0, 0, 1)
		surface.DrawPoly(mpoly)
		return
	end
	local sp = movie.sprites[char]
	if not sp then return end
	for _, e in ipairs(sp.frames[(kid and kid.frame or 0) + 1] or NONE) do
		local mark = top
		self:MaskOutline(e.c, e.m and pmul(m, e.m) or m, kid and kid.kids[keyOf(e)])
		top = mark
	end
end

-- draw this clip with parent matrix m / colour cx
function Inst:Draw(m, cx)
	if not self.visible then return end
	-- (an error in a draw leaves the stack as it is: this keeps that from growing)
	if top > 4096 then top = 0 end
	local mark = top
	m = m or IDENT
	if self.rotation then
		local r = math.rad(self.rotation)
		local co, si = math.cos(r), math.sin(r)
		m = pmul6(m, co, si, -si, co, 0, 0)
	end
	if self.scale then m = pmul6(m, self.scale, 0, 0, self.scale, 0, 0) end
	if self.override then
		-- icon replaced by script (labels the movie lacks, e.g. the cut power AlexSpines)
		drawQuad(self.override, m, cx, -32, -32, 32, 32, 0, 0, 1, 1)
		top = mark
		return
	end
	local sp = self:Sprite()
	if not sp then
		top = mark
		return
	end
	-- masks (PlaceObject clipDepth): not drawn; the depths up to it are clipped to the mask's screen box (a scissor:
	-- the game's masks are rectangles). kid.clipX = {x0, x1} in this clip's space = the mask's span set by script
	-- (the game's engine moves the health bar's masks), the height from the mask itself
	-- (user 2026-10-28: the awareness meter stood half full) a turned mask (the meter's: a rectangle swept round the
	-- arc) is no screen box: drawn into the stencil instead, its layers drawn only where it is
	local clipTo, clipped, stenciled
	local base = top
	for _, e in ipairs(sp.frames[self.frame + 1] or NONE) do
		top = base
		local kid = self.kids[keyOf(e)]
		if clipTo and e.d > clipTo then
			if stenciled then
				render.SetStencilEnable(false)
				stenciled = nil
			else
				render.SetScissorRect(0, 0, 0, 0, false)
			end
			clipTo = nil
		end
		if e.k then
			if kid and kid.hidden then goto skip end
			local km = e.m and pmul(m, e.m) or m
			-- (2026-10-28) a movie flagged stencil (the awareness lens, the disguise icons: a disc mask over the shutter -
			-- its square box showed the glow under it as a square) masks by the shapes' outlines, every mask
			if self.movie.stencil or math.abs(km[2]) > 1e-3 or math.abs(km[3]) > 1e-3 then
				render.SetStencilEnable(true)
				render.SetStencilWriteMask(255)
				render.SetStencilTestMask(255)
				render.SetStencilReferenceValue(1)
				render.ClearStencil()
				render.SetStencilCompareFunction(STENCIL_ALWAYS)
				render.SetStencilPassOperation(STENCIL_REPLACE)
				render.SetStencilFailOperation(STENCIL_KEEP)
				render.SetStencilZFailOperation(STENCIL_KEEP)
				render.OverrideColorWriteEnable(true, false)
				self:MaskOutline(e.c, km, kid)
				render.OverrideColorWriteEnable(false)
				render.SetStencilCompareFunction(STENCIL_EQUAL)
				render.SetStencilPassOperation(STENCIL_KEEP)
				clipTo, stenciled = e.k, true
				goto skip
			end
			local b = self:CharBounds(e.c, km, nil, kid)
			if b and kid and kid.clipX then
				local xa = SWF.Apply(m, kid.clipX[1], 0)
				local xb = SWF.Apply(m, kid.clipX[2], 0)
				b[1], b[3] = math.min(xa, xb), math.max(xa, xb)
			end
			if b and b[3] > b[1] and b[4] > b[2] then
				render.SetScissorRect(math.floor(b[1]), math.floor(b[2]), math.ceil(b[3]), math.ceil(b[4]), true)
			else
				render.SetScissorRect(0, 0, 1, 1, true) -- an empty mask hides its layers
			end
			clipTo, clipped = e.k, true
			goto skip
		end
		local em = e.m
		-- a script-set position (_x / _y the game's engine writes, e.g. the lock reticle's corners on the target box)
		local cm
		if kid and kid.place then
			cm = pmul6(m, em and em[1] or 1, em and em[2] or 0, em and em[3] or 0, em and em[4] or 1, kid.place[1], kid.place[2])
		else
			cm = em and pmul(m, em) or m
		end
		local cc = cxmul(cx, e.cx)
		-- (kid.hidden: a layer turned off by script)
		if kid and kid.hidden then goto skip end
		if kid then
			kid.drawText = self.drawText
			kid:Draw(cm, cc)
		else
			self:DrawChar(e.c, cm, cc, e)
		end
		::skip:: -- (not "continue": a GLua keyword)
	end
	if clipped then render.SetScissorRect(0, 0, 0, 0, false) end
	if stenciled then render.SetStencilEnable(false) end
	top = mark
end

-- point (x, y) in the clip's space -> screen, given its full matrix
function SWF.Apply(m, x, y)
	return m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
end
-