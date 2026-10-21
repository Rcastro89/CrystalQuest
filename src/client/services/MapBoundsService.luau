--!strict
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MapBoundsService = {}

local initialized = false

type WallOrientation = "North" | "South" | "East" | "West"

type ComputedBounds = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	centerX: number,
	centerZ: number,
	width: number,
	depth: number,
}

local function computeBounds(): ComputedBounds
	local margin = Config.MapBoundsMargin or 2

	local minX = math.min((Config.CrystalMinX or 0) - margin, -((Config.StartLineWidth or 0) / 2) - margin)
	local maxX = math.max((Config.CrystalMaxX or 0) + margin, ((Config.StartLineWidth or 0) / 2) + margin)
	local minZ = math.min((Config.CrystalMinZ or 0) - margin, (Config.StartLineZ or 0) - margin)
	local maxZ = math.max((Config.CrystalMaxZ or 0) + margin, (Config.StartLineZ or 0) + margin)

	local width = maxX - minX
	local depth = maxZ - minZ
	local centerX = (minX + maxX) / 2
	local centerZ = (minZ + maxZ) / 2

	return {
		minX = minX,
		maxX = maxX,
		minZ = minZ,
		maxZ = maxZ,
		centerX = centerX,
		centerZ = centerZ,
		width = width,
		depth = depth,
	}
end

local function validateBounds(bounds: ComputedBounds): (boolean, string?)
	if bounds.width <= 0 or bounds.depth <= 0 or bounds.width < 10 or bounds.depth < 10 then
		return false, "Área calculada no válida o demasiado pequeña."
	end
	if (Config.MapBoundsWallThickness or 1) <= 0 or (Config.MapBoundsWallHeight or 0) <= 0 then
		return false, "Medidas de pared no válidas."
	end
	return true, nil
end

local function makeWallParts(bounds: ComputedBounds, orientation: string): { Part }
	local thickness = Config.MapBoundsWallThickness or 1
	local height = Config.MapBoundsWallHeight or 15
	local halfHeight = height / 2
	local halfThick = thickness / 2
	local parts = {}

	local function createWallPart(size: Vector3, pos: Vector3, name: string)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Position = pos
		part.Anchored = true
		part.CanCollide = true
		part.CanTouch = false
		part.CanQuery = true
		part.Material = Config.MapBoundsWallMaterial or Enum.Material.Concrete
		part.Color = Config.MapBoundsWallColor or Color3.fromRGB(80, 90, 120)
		table.insert(parts, part)
	end

	if orientation == "North" then
		createWallPart(
			Vector3.new(bounds.width + thickness * 2, height, thickness),
			Vector3.new(bounds.centerX, halfHeight, bounds.maxZ + halfThick),
			"MapBoundary_North"
		)
	elseif orientation == "South" then
		local doorWidth = Config.DoorWidth or 10
		local sideWidth = (bounds.width - doorWidth) / 2

		createWallPart(
			Vector3.new(sideWidth, height, thickness),
			Vector3.new(bounds.minX + sideWidth / 2, halfHeight, bounds.minZ - halfThick),
			"MapBoundary_South_Left"
		)
		createWallPart(
			Vector3.new(sideWidth, height, thickness),
			Vector3.new(bounds.maxX - sideWidth / 2, halfHeight, bounds.minZ - halfThick),
			"MapBoundary_South_Right"
		)
	elseif orientation == "East" then
		createWallPart(
			Vector3.new(thickness, height, bounds.depth),
			Vector3.new(bounds.maxX + halfThick, halfHeight, bounds.centerZ),
			"MapBoundary_East"
		)
	else -- West
		createWallPart(
			Vector3.new(thickness, height, bounds.depth),
			Vector3.new(bounds.minX - halfThick, halfHeight, bounds.centerZ),
			"MapBoundary_West"
		)
	end

	return parts
end

function MapBoundsService.Initialize(): boolean
	if initialized then
		return false
	end
	initialized = true

	local oldFolder = Workspace:FindFirstChild("CrystalQuestBounds")
	if oldFolder then
		oldFolder:Destroy()
	end

	local bounds = computeBounds()
	local ok, err = validateBounds(bounds)
	if not ok then
		warn("[MapBounds] Validación fallida: " .. tostring(err))
		return false
	end

	local folder = Instance.new("Folder")
	folder.Name = "CrystalQuestBounds"
	folder.Parent = Workspace

	local orientations = {
		"North" :: WallOrientation,
		"South" :: WallOrientation,
		"East" :: WallOrientation,
		"West" :: WallOrientation,
	}

	for _, orientation in ipairs(orientations) do
		local walls = makeWallParts(bounds, orientation)
		for _, wall in ipairs(walls) do
			wall.Parent = folder
		end
	end

	print("[MapBounds] Habitación cerrada creada con hueco de puerta.")
	return true
end

function MapBoundsService.Reset()
	local oldFolder = Workspace:FindFirstChild("CrystalQuestBounds")
	if oldFolder then
		oldFolder:Destroy()
	end
	initialized = false
	MapBoundsService.Initialize()
end

return MapBoundsService
