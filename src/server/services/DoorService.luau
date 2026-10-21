--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DoorService = {}

local initialized = false
local startTriggered = false
local doorLocked = false
local isDoorOpen = false

local doorModel: Model? = nil
local doorCFrameVal: CFrameValue? = nil
local closedCFrame: CFrame? = nil
local openCFrame: CFrame? = nil
local activeTrigger: Part? = nil

type OnPlayerCrossed = (Player) -> boolean

local function setupDoor(course: Folder)
	local doorWidth = Config.DoorWidth or 10
	local wallHeight = Config.MapBoundsWallHeight or 15

	local model = Instance.new("Model")
	model.Name = "MapDoor"

	local success, asset = pcall(function()
		return InsertService:LoadAsset(Config.DoorAssetId or 0)
	end)

	if success and asset then
		for _, item in ipairs(asset:GetChildren()) do
			item.Parent = model
		end
	else
		warn("[DoorService] Fallo al cargar el Asset ID.")
	end

	-- Limpieza profunda: Desactivar scripts y basura visual del asset
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BaseScript") or part:IsA("LocalScript") then
			part:Destroy()
		elseif part:IsA("Highlight") or part:IsA("SelectionBox") then
			part:Destroy()
		end
	end

	local hasParts = false
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			hasParts = true
			break
		end
	end

	if not hasParts then
		local part = Instance.new("Part")
		part.Size = Vector3.new(doorWidth, wallHeight, 1)
		part.Color = Color3.fromRGB(150, 150, 150)
		part.Material = Enum.Material.Metal
		part.Parent = model
	end

	-- Forzar visibilidad y colisión
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = true
			part.Transparency = 0
			part.LocalTransparencyModifier = 0
			for _, child in ipairs(part:GetChildren()) do
				-- Al ser Texture una subclase de Decal, esto atrapa a ambos
				if child:IsA("Decal") then
					child.Transparency = 0
				end
			end
		end
	end

	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end

	if not model.PrimaryPart then
		warn("[DoorService] ERROR: No hay partes en el modelo.")
		return
	end

	-- 1. AUTO-ESCALADO
	local extents = model:GetExtentsSize()
	if extents.X > 0 and extents.Y > 0 then
		local scaleX = doorWidth / extents.X
		local scaleY = wallHeight / extents.Y
		local scaleFactor = math.min(scaleX, scaleY)
		model:ScaleTo(scaleFactor)
	end

	-- 2. POSICIONAMIENTO
	extents = model:GetExtentsSize()
	local margin = Config.MapBoundsMargin or 2
	local minZ = math.min((Config.CrystalMinZ or 0) - margin, (Config.StartLineZ or 0) - margin)
	local wallThickness = Config.MapBoundsWallThickness or 1
	local wallZ = minZ - (wallThickness / 2)

	-- Importante: asignar Parent antes de PivotTo
	model.Parent = course
	model:PivotTo(CFrame.new(0, extents.Y / 2, wallZ))

	doorModel = model
	local pivot = model:GetPivot()
	closedCFrame = pivot
	openCFrame = pivot * CFrame.new(-extents.X - 1, 0, 0)

	print("[DoorService] Puerta colocada en Z: " .. tostring(wallZ) .. " | Tamaño: " .. tostring(extents))

	-- 3. ANIMACIÓN
	local cframeVal = Instance.new("CFrameValue")
	cframeVal.Value = pivot
	doorCFrameVal = cframeVal

	cframeVal:GetPropertyChangedSignal("Value"):Connect(function()
		if doorModel then
			doorModel:PivotTo(cframeVal.Value)
		end
	end)

	-- Sensor de Proximidad
	local proximity = Instance.new("Part")
	proximity.Name = "DoorProximity"
	proximity.Size = Vector3.new(doorWidth + 10, extents.Y, Config.DoorOpenDistance or 8)
	proximity.Position = Vector3.new(0, extents.Y / 2, wallZ - 2)
	proximity.Anchored = true
	proximity.CanCollide = false
	proximity.CanTouch = true
	proximity.Transparency = 1
	proximity.Parent = course

	proximity.Touched:Connect(function(hit)
		if doorLocked or isDoorOpen or not doorCFrameVal or not openCFrame then
			return
		end
		local char = hit:FindFirstAncestorOfClass("Model")
		local player = Players:GetPlayerFromCharacter(char)
		if player then
			isDoorOpen = true
			local tweenInfo =
				TweenInfo.new(Config.DoorOpenDuration or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(doorCFrameVal, tweenInfo, { Value = openCFrame }):Play()
		end
	end)
end

function DoorService.Initialize(onPlayerCrossed: OnPlayerCrossed)
	if initialized then
		return
	end
	initialized = true

	local oldCourse = Workspace:FindFirstChild("CrystalQuestCourse")
	if oldCourse then
		oldCourse:Destroy()
	end

	local course = Instance.new("Folder")
	course.Name = "CrystalQuestCourse"
	course.Parent = Workspace

	setupDoor(course)

	-- Trigger de cruce (inicia la ronda)
	local trigger = Instance.new("Part")
	trigger.Name = "DoorTrigger"
	trigger.Size = Vector3.new(Config.DoorWidth or 10, Config.StartLineTriggerHeight, Config.StartLineTriggerDepth)
	trigger.Position = Vector3.new(0, trigger.Size.Y / 2, Config.StartLineZ + 2)
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.CanTouch = true
	trigger.CanQuery = false
	trigger.Transparency = 1
	trigger.Parent = course

	activeTrigger = trigger

	trigger.Touched:Connect(function(hit: BasePart)
		if startTriggered then
			return
		end

		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then
			return
		end

		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		startTriggered = true
		trigger.CanTouch = false

		if doorCFrameVal and closedCFrame then
			print("[DoorService] Cerrando puerta...")
			doorLocked = true
			local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(doorCFrameVal, tweenInfo, { Value = closedCFrame }):Play()
		end

		local accepted = onPlayerCrossed(player)

		if not accepted then
			startTriggered = false
			trigger.CanTouch = true
			doorLocked = false
		end
	end)
end

function DoorService.Reset()
	startTriggered = false
	doorLocked = false
	isDoorOpen = false
	if activeTrigger then
		activeTrigger.CanTouch = true
	end

	if doorCFrameVal and closedCFrame then
		doorCFrameVal.Value = closedCFrame
	end
end

return DoorService
