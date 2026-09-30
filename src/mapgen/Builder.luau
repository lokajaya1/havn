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

local Builder = {}
Builder.__index = Builder

function Builder.new(rootName: string, kit: Instance?)
	local self = setmetatable({}, Builder)
	self.root = Instance.new("Folder")
	self.root.Name = rootName
	self.kit = kit
	self.parts = 0
	return self
end

local function color(key: string?): Color3
	local c = Palette.colors[key or "Blockout"] or Palette.colors.Blockout
	return Color3.fromRGB(c[1], c[2], c[3])
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

return Builder
