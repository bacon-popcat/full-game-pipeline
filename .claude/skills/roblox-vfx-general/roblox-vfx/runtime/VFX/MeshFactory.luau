-- ModuleScript: <VFX folder>/MeshFactory
-- Authoring-time tool. Run it in Studio's Edit mode (command bar, a plugin,
-- or the Studio MCP's execute_luau). The game itself never uses this module;
-- it only uses the published mesh templates this creates.
--
-- Typical use:
--   local MF = require(game.ReplicatedStorage.VFX.MeshFactory)
--   local mesh = MF.Generators.Crescent({ Radius = 4, Width = 1.2, Arc = 170 })
--   local preview = MF.Preview(mesh)           -- look at it / screenshot it
--   preview:Destroy()
--   MF.Publish(mesh, "SlashCrescent", "Crescent", { Radius = 4, Width = 1.2, Arc = 170 })
--
-- Conventions for every generator:
--   * Y is up. Flat shapes lie in the XZ plane.
--   * U runs along the shape's length/around it, V runs across it (0 -> 1),
--     so a horizontal gradient texture fades along a slash.
--   * Keep meshes small: under ~1000 triangles for VFX (the budget in SKILL.md).

local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshFactory = {}
MeshFactory.Generators = {}

local TAU = 2 * math.pi

--------------------------------------------------------------------------------
-- Core builder: positions/uvs are parallel arrays (one per vertex),
-- tris are {i, j, k} index triples into those arrays.
--   opts.doubleSided   add back faces (for thin shapes: slashes, rings, tubes)
--   opts.orientOutward fix winding so faces point away from the center
--                      (for closed, roughly convex shapes: rocks, shards, spikes)
--------------------------------------------------------------------------------
local function build(positions, uvs, tris, opts)
	opts = opts or {}

	if opts.orientOutward then
		local center = Vector3.zero
		for _, p in positions do
			center += p
		end
		center /= #positions
		for i, t in tris do
			local a, b, c = positions[t[1]], positions[t[2]], positions[t[3]]
			local normal = (b - a):Cross(c - a)
			if normal:Dot((a + b + c) / 3 - center) < 0 then
				tris[i] = { t[1], t[3], t[2] }
			end
		end
	end

	if opts.doubleSided then
		-- Back faces get their own vertices so their normals don't cancel out
		local n = #positions
		for i = 1, n do
			positions[n + i] = positions[i]
			uvs[n + i] = uvs[i]
		end
		local count = #tris
		for i = 1, count do
			local t = tris[i]
			table.insert(tris, { t[1] + n, t[3] + n, t[2] + n })
		end
	end

	local mesh = AssetService:CreateEditableMesh()
	local vertexIds = mesh:BatchAdd(Enum.MeshAttribute.Vertex, positions)

	local faces = table.create(#tris)
	for i, t in tris do
		faces[i] = { vertexIds[t[1]], vertexIds[t[2]], vertexIds[t[3]] }
	end
	local faceIds = mesh:BatchAdd(Enum.MeshAttribute.Face, faces)

	local uvIds = mesh:BatchAdd(Enum.MeshAttribute.UV, uvs)
	local faceUVs = table.create(#tris)
	for i, t in tris do
		faceUVs[i] = { uvIds[t[1]], uvIds[t[2]], uvIds[t[3]] }
	end
	mesh:BatchSetFaceAttributes(faceIds, faceUVs)

	mesh:RemoveUnused() -- drop the auto-created default UVs we replaced
	return mesh
end
MeshFactory.Build = build

-- Shared strip builder: two rows of points -> quads between them
local function stripTris(segments, tris)
	for i = 0, segments - 1 do
		local a0, b0, a1, b1 = 2 * i + 1, 2 * i + 2, 2 * i + 3, 2 * i + 4
		table.insert(tris, { a0, a1, b0 })
		table.insert(tris, { b0, a1, b1 })
	end
end

--------------------------------------------------------------------------------
-- Generators
--------------------------------------------------------------------------------

-- Slash arc lying flat, centered on +X. Tapers to points at both ends.
-- Radius, Width, Arc (degrees), Segments, Taper (bool)
function MeshFactory.Generators.Crescent(p)
	p = p or {}
	local radius = p.Radius or 4
	local width = p.Width or 1.2
	local arc = math.rad(p.Arc or 160)
	local segments = p.Segments or 32
	local taper = p.Taper ~= false

	local positions, uvs, tris = {}, {}, {}
	for i = 0, segments do
		local t = i / segments
		local angle = -arc / 2 + arc * t
		local w = if taper then width * math.max(math.sin(math.pi * t), 0.02) else width
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		table.insert(positions, dir * radius)
		table.insert(positions, dir * (radius - w))
		table.insert(uvs, Vector2.new(t, 0))
		table.insert(uvs, Vector2.new(t, 1))
	end
	stripTris(segments, tris)
	return build(positions, uvs, tris, { doubleSided = true })
end

-- Flat ring (annulus). InnerRadius, OuterRadius, Segments
function MeshFactory.Generators.Ring(p)
	p = p or {}
	local inner = p.InnerRadius or 0.8
	local outer = p.OuterRadius or 1
	local segments = p.Segments or 48

	local positions, uvs, tris = {}, {}, {}
	for i = 0, segments do
		local t = i / segments
		local dir = Vector3.new(math.cos(TAU * t), 0, math.sin(TAU * t))
		table.insert(positions, dir * outer)
		table.insert(positions, dir * inner)
		table.insert(uvs, Vector2.new(t, 0))
		table.insert(uvs, Vector2.new(t, 1))
	end
	stripTris(segments, tris)
	return build(positions, uvs, tris, { doubleSided = true })
end

-- Open tube, optionally flared at the top (shockwave walls, energy pillars).
-- Radius, Height, Flare (top radius multiplier), Segments
function MeshFactory.Generators.Tube(p)
	p = p or {}
	local radius = p.Radius or 1
	local height = p.Height or 1
	local flare = p.Flare or 1.2
	local segments = p.Segments or 48

	local positions, uvs, tris = {}, {}, {}
	for i = 0, segments do
		local t = i / segments
		local dir = Vector3.new(math.cos(TAU * t), 0, math.sin(TAU * t))
		table.insert(positions, dir * radius)
		table.insert(positions, dir * radius * flare + Vector3.new(0, height, 0))
		table.insert(uvs, Vector2.new(t, 0))
		table.insert(uvs, Vector2.new(t, 1))
	end
	stripTris(segments, tris)
	return build(positions, uvs, tris, { doubleSided = true })
end

-- Cone spike pointing up (ground spikes, ice spears). Radius, Height, Sides
function MeshFactory.Generators.Spike(p)
	p = p or {}
	local radius = p.Radius or 0.5
	local height = p.Height or 3
	local sides = p.Sides or 8

	local positions = { Vector3.new(0, height, 0), Vector3.zero } -- 1 = tip, 2 = base center
	local uvs = { Vector2.new(0.5, 1), Vector2.new(0.5, 0) }
	for i = 0, sides - 1 do
		local t = i / sides
		table.insert(positions, Vector3.new(math.cos(TAU * t), 0, math.sin(TAU * t)) * radius)
		table.insert(uvs, Vector2.new(t, 0))
	end

	local tris = {}
	for i = 0, sides - 1 do
		local a = 3 + i
		local b = 3 + (i + 1) % sides
		table.insert(tris, { 1, a, b })
		table.insert(tris, { 2, b, a })
	end
	return build(positions, uvs, tris, { orientOutward = true })
end

-- Crystal shard: jittered double pyramid. Length, Width, Sides, Seed
function MeshFactory.Generators.Shard(p)
	p = p or {}
	local length = p.Length or 2
	local width = p.Width or 0.5
	local sides = p.Sides or 5
	local rng = Random.new(p.Seed or 1)

	local positions = {
		Vector3.new(0, length * 0.65, 0),
		Vector3.new(0, -length * 0.35, 0),
	}
	local uvs = { Vector2.new(0.5, 1), Vector2.new(0.5, 0) }
	for i = 0, sides - 1 do
		local t = i / sides
		local angle = TAU * t + rng:NextNumber(-0.25, 0.25)
		local r = width * rng:NextNumber(0.7, 1.1)
		local y = rng:NextNumber(-0.1, 0.1) * length
		table.insert(positions, Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r))
		table.insert(uvs, Vector2.new(t, 0.4))
	end

	local tris = {}
	for i = 0, sides - 1 do
		local a = 3 + i
		local b = 3 + (i + 1) % sides
		table.insert(tris, { 1, a, b })
		table.insert(tris, { 2, b, a })
	end
	return build(positions, uvs, tris, { orientOutward = true })
end

-- Lumpy rock: noise-displaced sphere. Radius, Rings, Segments, Roughness, Squash (Vector3), Seed
function MeshFactory.Generators.Rock(p)
	p = p or {}
	local radius = p.Radius or 0.5
	local rings = p.Rings or 6
	local segments = p.Segments or 8
	local roughness = p.Roughness or 0.3
	local squash = p.Squash or Vector3.new(1, 0.75, 1)
	local seed = p.Seed or 1

	local function displace(dir)
		local n = math.noise(dir.X * 1.7 + seed * 13.1, dir.Y * 1.7, dir.Z * 1.7)
		return dir * radius * (1 + n * roughness * 2) * squash
	end

	local positions = { displace(Vector3.yAxis) } -- 1 = top pole
	local uvs = { Vector2.new(0.5, 1) }
	for r = 1, rings - 1 do
		local phi = math.pi * r / rings
		for s = 0, segments - 1 do
			local theta = TAU * s / segments
			local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta))
			table.insert(positions, displace(dir))
			table.insert(uvs, Vector2.new(s / segments, 1 - r / rings))
		end
	end
	table.insert(positions, displace(-Vector3.yAxis)) -- bottom pole
	table.insert(uvs, Vector2.new(0.5, 0))
	local bottom = #positions

	local function ringIndex(r, s)
		return 2 + (r - 1) * segments + (s % segments)
	end

	local tris = {}
	for s = 0, segments - 1 do
		table.insert(tris, { 1, ringIndex(1, s), ringIndex(1, s + 1) })
		table.insert(tris, { bottom, ringIndex(rings - 1, s + 1), ringIndex(rings - 1, s) })
	end
	for r = 1, rings - 2 do
		for s = 0, segments - 1 do
			local a, b = ringIndex(r, s), ringIndex(r, s + 1)
			local c, d = ringIndex(r + 1, s), ringIndex(r + 1, s + 1)
			table.insert(tris, { a, c, b })
			table.insert(tris, { b, c, d })
		end
	end
	return build(positions, uvs, tris, { orientOutward = true })
end

-- Smooth UV sphere for textured balls (fireballs, orbs). Radius, Rings, Segments.
-- U = longitude (0 -> 1 around Y, seam duplicated), V = latitude (0 = top pole),
-- so an equirectangular texture (2:1) wraps it without stretching at the seam.
function MeshFactory.Generators.Sphere(p)
	p = p or {}
	local radius = p.Radius or 0.5
	local rings = p.Rings or 14
	local segments = p.Segments or 28

	local positions, uvs, tris = {}, {}, {}
	local function index(r, s)
		return r * (segments + 1) + s + 1
	end
	for r = 0, rings do
		local phi = math.pi * r / rings
		for s = 0, segments do
			local theta = TAU * s / segments
			local dir = Vector3.new(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta))
			table.insert(positions, dir * radius)
			-- pole vertices get the middle of their segment so the cap texture isn't skewed
			local u = if r == 0 or r == rings then (s + 0.5) / segments else s / segments
			table.insert(uvs, Vector2.new(u, r / rings))
		end
	end
	for r = 0, rings - 1 do
		for s = 0, segments - 1 do
			local a, b = index(r, s), index(r, s + 1)
			local c, d = index(r + 1, s), index(r + 1, s + 1)
			if r > 0 then
				table.insert(tris, { a, b, c })
			end
			if r < rings - 1 then
				table.insert(tris, { b, d, c })
			end
		end
	end
	return build(positions, uvs, tris, { orientOutward = true })
end

-- Any open sheet you can describe as a function: point(u, v) returns the Vector3 of each
-- grid corner for u, v in 0..1, and that corner's UV is (u, v). Columns x Rows quads,
-- double-sided. Triangles that collapse (corners meeting at a pole or a tip) are skipped.
-- Use it for shapes no generator covers: a torn shockwave (vary the radius with u), a
-- forked lightning card, petals, a wobbling wave. Not in Generators (a function can't be
-- saved as Params): publish the result with MF.Publish(mesh, name, "Surface", { Note = "..." }).
-- (Shape helpers after Roqer's vfx_surface/vfx_swirl/vfx_shell, https://github.com/S4US/Roqer, AGPL-3.0.)
function MeshFactory.Surface(point, columns, rows)
	columns = columns or 32
	rows = rows or 1
	local positions, uvs, tris = {}, {}, {}
	local function index(c, r)
		return c * (rows + 1) + r + 1
	end
	for c = 0, columns do
		for r = 0, rows do
			local u, v = c / columns, r / rows
			table.insert(positions, point(u, v))
			table.insert(uvs, Vector2.new(u, v))
		end
	end
	local function addTri(i, j, k)
		local a, b, c = positions[i], positions[j], positions[k]
		if (b - a):Cross(c - a).Magnitude > 1e-8 then
			table.insert(tris, { i, j, k })
		end
	end
	for c = 0, columns - 1 do
		for r = 0, rows - 1 do
			local a, b = index(c, r), index(c + 1, r)
			local d, e = index(c, r + 1), index(c + 1, r + 1)
			addTri(a, b, e)
			addTri(a, e, d)
		end
	end
	return build(positions, uvs, tris, { doubleSided = true })
end

-- Ribbon spiralling up around Y: a tornado, an aura, a charge-up. It turns Turns times while
-- rising from 0 to Height, its radius going from Radius to TopRadius, and the ribbon is Width
-- tall. U runs along the ribbon from the bottom end, V across it from its lower edge.
-- Radius, TopRadius, Height, Width, Turns, Segments
function MeshFactory.Generators.Swirl(p)
	p = p or {}
	local radius = p.Radius or 2
	local top = p.TopRadius or radius
	local height = p.Height or 4
	local width = p.Width or 0.6
	local turns = p.Turns or 1.5
	return MeshFactory.Surface(function(u, v)
		local angle = TAU * turns * u
		local r = radius + (top - radius) * u
		return Vector3.new(math.cos(angle) * r, height * u + width * (v - 0.5), math.sin(angle) * r)
	end, p.Segments or 96, 1)
end

-- Open half sphere standing on the ground (Y = 0): a barrier, a blast bubble, a shield.
-- U runs around, V from the ground up to the top. Radius, Segments, Rings
function MeshFactory.Generators.Dome(p)
	p = p or {}
	local radius = p.Radius or 1
	return MeshFactory.Surface(function(u, v)
		local polar = (math.pi / 2) * (1 - v)
		local ring = radius * math.sin(polar)
		return Vector3.new(math.cos(TAU * u) * ring, radius * math.cos(polar), math.sin(TAU * u) * ring)
	end, p.Segments or 32, p.Rings or 8)
end

--------------------------------------------------------------------------------
-- Preview and publish
--------------------------------------------------------------------------------

-- Temporary MeshPart in the workspace for inspection/screenshots.
-- It is NOT saved with the place. Destroy it when done.
function MeshFactory.Preview(mesh, cframe)
	local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
	part.Name = "MeshPreview"
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.CFrame = cframe or CFrame.new(0, 6, 0)
	part.Parent = workspace
	return part
end

local function serialize(params)
	local out = {}
	for key, value in params or {} do
		out[key] = if typeof(value) == "Vector3" then { value.X, value.Y, value.Z } else value
	end
	return HttpService:JSONEncode(out)
end

local function defaultCreator()
	local ok, userId = pcall(function()
		return game:GetService("StudioService"):GetUserId()
	end)
	if ok and userId and userId > 0 then
		return { Id = userId, Type = Enum.AssetCreatorType.User }
	end
	error("MeshFactory: pass creator = { Id = <userId or groupId>, Type = Enum.AssetCreatorType.User/Group }")
end

-- Uploads the mesh as a real Mesh asset and saves a template MeshPart in
-- ReplicatedStorage/Assets/Meshes/<name>. Returns assetId, template.
function MeshFactory.Publish(mesh, name, generatorName, params, creator)
	creator = creator or defaultCreator()

	local ok, result, idOrError = pcall(function()
		return AssetService:CreateAssetAsync(mesh, Enum.AssetType.Mesh, {
			CreatorId = creator.Id,
			CreatorType = creator.Type,
			Name = name,
			Description = ("VFX mesh (%s)"):format(generatorName or "custom"),
		})
	end)
	if not ok then
		error(("MeshFactory: CreateAssetAsync failed: %s"):format(tostring(result)))
	end
	if result ~= Enum.CreateAssetResult.Success then
		error(("MeshFactory: upload rejected: %s %s"):format(tostring(result), tostring(idOrError)))
	end
	local assetId = idOrError

	-- Precise: with Automatic, thin curved cards (crescents) turn into straight-sided wedges at range
	local template = AssetService:CreateMeshPartAsync(Content.fromAssetId(assetId), {
		RenderFidelity = Enum.RenderFidelity.Precise,
	})
	template.Name = name
	template.Anchored = true
	template.CanCollide = false
	template.CanQuery = false
	template.CanTouch = false
	template.CastShadow = false
	template:SetAttribute("AssetId", assetId)
	template:SetAttribute("Generator", generatorName or "custom")
	template:SetAttribute("Params", serialize(params))

	local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
	assets.Name = "Assets"
	assets.Parent = ReplicatedStorage
	local meshes = assets:FindFirstChild("Meshes") or Instance.new("Folder")
	meshes.Name = "Meshes"
	meshes.Parent = assets

	local existing = meshes:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	template.Parent = meshes
	return assetId, template
end

-- Find an already-published template made with the same generator + params.
function MeshFactory.FindExisting(generatorName, params)
	local meshes = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Meshes")
	if not meshes then
		return nil
	end
	local key = serialize(params)
	for _, child in meshes:GetChildren() do
		if child:GetAttribute("Generator") == generatorName and child:GetAttribute("Params") == key then
			return child
		end
	end
	return nil
end

-- One call: reuse if it exists, otherwise generate + publish.
function MeshFactory.Make(name, generatorName, params, creator)
	local existing = MeshFactory.FindExisting(generatorName, params)
	if existing then
		return existing:GetAttribute("AssetId"), existing
	end
	local generator = MeshFactory.Generators[generatorName]
	assert(generator, "MeshFactory: unknown generator " .. tostring(generatorName))
	local mesh = generator(params)
	local assetId, template = MeshFactory.Publish(mesh, name, generatorName, params, creator)
	mesh:Destroy()
	return assetId, template
end

return MeshFactory
