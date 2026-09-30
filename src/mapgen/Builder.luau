--!strict
-- MapGen/Builder — gateway pembuat instance map (satu-satunya tempat Instance.new di MapGen).
-- Semua part: Anchored; bayangan & tabrakan mengikuti anggaran (Rencana_Workspace.md §5):
--   ukuran terbesar < 2 stud atau Neon/tak terlihat → CastShadow off; < 1 stud atau decor → tanpa tabrakan/sentuh/query.

local Palette = require(script.Parent.Palette)

export type PartSpec = {
	size: Vector3,
	cf: CFrame,
	color: string?,
	material: string?,
	transparency: number?,
	shape: string?, -- "Block" (default) | "Wedge" | "Cylinder" | "Ball"
	decor: boolean?, -- true = tidak bisa ditabrak (hiasan)
}

local function color(key: string?): Color3
	local c = Palette.colors[key or "Blockout"] or Palette.colors.Blockout
	return Color3.fromRGB(c[1], c[2], c[3])
end

local Builder = {}
Builder.__index = Builder

function Builder.new(rootName: string, kit: Instance?)
	local self = setmetatable({}, Builder)
	self.root = Instance.new("Folder")
	self.root.Name = rootName
	self.kit = kit
	self.parts = 0
	self.terrainOps = {} :: { any }
	self.missingKit = {} :: { string }
	return self
end

-- Operasi terrain hanya DICATAT di sini; MapGen menjalankannya saat JALAN (bisa diperiksa dulu saat CEK).
function Builder:terrain(kind: string, material: string, cf: CFrame, size: Vector3)
	table.insert(self.terrainOps, { op = kind, material = material, cf = cf, size = size })
end

function Builder:terrainColor(material: string, colorKey: string)
	table.insert(self.terrainOps, { op = "Color", material = material, color = color(colorKey) })
end

function Builder:water(props: { [string]: any })
	table.insert(self.terrainOps, { op = "Water", props = props, color = color(props.color) })
end

function Builder:folder(parent: Instance?, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or self.root
	return f
end

function Builder:model(parent: Instance?, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent or self.root
	return m
end

function Builder:part(parent: Instance, name: string, spec: PartSpec): BasePart
	local p: BasePart
	if spec.shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if spec.shape == "Cylinder" then
			block.Shape = Enum.PartType.Cylinder
		elseif spec.shape == "Ball" then
			block.Shape = Enum.PartType.Ball
		end
		p = block
	end
	p.Name = name
	p.Anchored = true
	p.Size = spec.size
	p.CFrame = spec.cf
	p.Color = color(spec.color)
	local mat = spec.material or "Plastic"
	p.Material = (Enum.Material :: any)[Palette.materials[mat] or mat]
	p.Transparency = spec.transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local biggest = math.max(spec.size.X, spec.size.Y, spec.size.Z)
	local invisible = (spec.transparency or 0) >= 1
	p.CastShadow = not (biggest < 2 or invisible or mat == "Neon")
	if spec.decor or biggest < 1 then
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
	end
	p.Parent = parent
	self.parts += 1
	return p
end

-- Papan tulisan Y2K (SurfaceGui) di satu sisi part.
function Builder:sign(board: BasePart, text: string, face: string, colorKey: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = (Enum.NormalId :: any)[face]
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = color(colorKey)
	t.TextStrokeTransparency = 0.2
	t.Text = text
	t.Parent = gui
	gui.Parent = board
end

-- Label melayang (hanya untuk blockout / tinjauan).
function Builder:label(parent: Instance, adornee: BasePart, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "ZoneLabel"
	gui.Size = UDim2.fromOffset(220, 50)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = adornee
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0
	t.Text = text
	t.Parent = gui
	gui.Parent = parent
end

local function eachPart(inst: Instance, fn: (BasePart) -> ())
	if inst:IsA("BasePart") then
		fn(inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			fn(d)
		end
	end
end

-- Salin mesh dari ServerStorage.MapKit (dicari rekursif), taruh dengan tengah-bawahnya di cf (menapak tanah),
-- beri nama. Isi kit bernama generik ("Part", "Meshes/…") → Piece_NN / Group_NN.
function Builder:clone(parent: Instance, kitName: string, cf: CFrame, name: string): Instance?
	local src = self.kit and self.kit:FindFirstChild(kitName, true)
	if not src then
		table.insert(self.missingKit, kitName)
		return nil
	end
	local Naming = require(script.Parent.Naming)
	local c = src:Clone()
	local i = 0
	for _, d in c:GetDescendants() do
		if (d:IsA("BasePart") or d:IsA("Model") or d:IsA("Folder")) and Naming.problem(d.Name) then
			i += 1
			d.Name = Naming.fallback(d.ClassName, i)
		end
	end
	-- kotak pembatas lama → pindahkan supaya tengah-bawah = cf (tanpa GetBoundingBox/PivotTo: jalan juga di Lune)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	eachPart(c, function(p)
		local h = p.Size / 2
		lo = Vector3.new(math.min(lo.X, p.CFrame.X - h.X), math.min(lo.Y, p.CFrame.Y - h.Y), math.min(lo.Z, p.CFrame.Z - h.Z))
		hi = Vector3.new(math.max(hi.X, p.CFrame.X + h.X), math.max(hi.Y, p.CFrame.Y + h.Y), math.max(hi.Z, p.CFrame.Z + h.Z))
	end)
	local pivot = CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	local move = cf * pivot:Inverse()
	eachPart(c, function(p)
		p.CFrame = move * p.CFrame
		p.Anchored = true
		self.parts += 1
	end)
	c.Name = name
	c:SetAttribute("KitSource", nil)
	c.Parent = parent
	return c
end

return Builder
