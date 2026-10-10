--!strict
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local EnemyService = {}

local initialized = false
local roundSpawned = false

function EnemyService.Initialize()
	if initialized then
		warn("[EnemyService] El servicio ya fue inicializado.")
		return
	end

	initialized = true

	local oldFolder = Workspace:FindFirstChild("CrystalQuestEnemies")
	if oldFolder then
		oldFolder:Destroy()
	end
end

-- =========================================================
-- POSICIÓN DEL ENEMIGO (EN EL ÁREA DE CRISTALES)
-- =========================================================
local function generateEnemyPosition(): Vector3?
	local minDistance = Config.MonsterMinDistanceFromOthers or Config.CrystalMinDistance

	for _ = 1, Config.CrystalMaxPositionAttempts do
		local x = math.random(Config.CrystalMinX, Config.CrystalMaxX)
		local z = math.random(Config.CrystalMinZ, Config.CrystalMaxZ)
		local candidate = Vector3.new(x, Config.CrystalGroundY, z)

		local crystalFolder = Workspace:FindFirstChild("CrystalQuestCollectibles")
		if crystalFolder then
			local valid = true
			for _, child in ipairs(crystalFolder:GetChildren()) do
				if child:IsA("Model") or child:IsA("BasePart") then
					local pivotPos: Vector3
					if child:IsA("Model") then
						pivotPos = child:GetPivot().Position
					else
						pivotPos = (child :: BasePart).Position
					end

					local offset = Vector3.new(candidate.X - pivotPos.X, 0, candidate.Z - pivotPos.Z)

					if offset.Magnitude < minDistance then
						valid = false
						break
					end
				end
			end
			if not valid then
				continue
			end
		end

		return candidate
	end

	warn("[EnemyService] No se encontró posición válida para el enemigo.")
	return nil
end

-- =========================================================
-- CREACIÓN DEL ENEMIGO (POR AHORA DECORATIVO)
-- =========================================================
local function createEnemy(position: Vector3, parentFolder: Folder)
	local scale = Config.MonsterSizeScale or 1
	local monsterModel: Model? = nil

	local ok, loaded = pcall(function()
		return InsertService:LoadAsset(Config.MonsterAssetId or 0)
	end)

	if ok and loaded then
		local child = loaded:FindFirstChildWhichIsA("Model")
		if not child then
			local any = loaded:GetChildren()[1]
			if any and any:IsA("Model") then
				child = any
			end
		end
		if child then
			monsterModel = child :: Model
		end
	else
		warn("[EnemyService] Error cargando enemigo ID " .. tostring(Config.MonsterAssetId) .. ": " .. tostring(loaded))
	end

	local displayModel: Model
	if monsterModel then
		displayModel = monsterModel
	else
		displayModel = Instance.new("Model")
		displayModel.Name = "Monster"

		local fallback = Instance.new("Part")
		fallback.Name = "MonsterFallback"
		fallback.Size = Vector3.new(4, 5, 4)
		fallback.Material = Enum.Material.Neon
		fallback.Color = Color3.fromRGB(160, 50, 200)
		fallback.Anchored = true
		fallback.CanCollide = true
		fallback.CanTouch = true
		fallback.CanQuery = false
		fallback.Parent = displayModel
		displayModel.PrimaryPart = fallback
	end

	displayModel.Name = "Enemy"

	for _, descendant in ipairs(displayModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = true
			descendant.CanTouch = true
			descendant.CanQuery = false

			local oku, _ = pcall(function()
				descendant:SetNetworkOwner(nil)
			end)
			_ = oku

			if descendant:IsA("Part") then
				local touchTransmitter = descendant:FindFirstChildOfClass("TouchTransmitter")
				if touchTransmitter then
					touchTransmitter:Destroy()
				end
			end
		elseif descendant:IsA("BaseScript") then
			descendant.Disabled = true
		elseif descendant:IsA("Animator") then
			-- Desactivamos animadores para que no reproduzca nada por defecto
			local oky, _ = pcall(function()
				descendant:Destroy()
			end)
			_ = oky
		elseif descendant:IsA("Humanoid") then
			descendant.MaxHealth = 0
			descendant.Health = 0
			descendant.WalkSpeed = 0
			descendant.JumpPower = 0
			descendant.PlatformStand = true
			descendant.AutoRotate = false
			descendant:SetStateEnabled(Enum.HumanoidStateType.Running, false)
			descendant:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			descendant:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
			descendant:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
			descendant:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
		end
	end

	local extents = displayModel:GetExtentsSize()
	local halfHeight = extents.Y / 2
	local worldCenterY = Config.CrystalGroundY + halfHeight
	displayModel:PivotTo(CFrame.new(position.X, worldCenterY, position.Z))

	if scale ~= 1 then
		local original = displayModel:GetPivot()
		displayModel:ScaleTo(scale)
		displayModel:PivotTo(original)
	end

	displayModel.Parent = parentFolder

	print(
		"[EnemyService] Enemigo colocado en ("
			.. tostring(math.floor(position.X))
			.. ", "
			.. tostring(math.floor(position.Z))
			.. ")"
	)
end

function EnemyService.SpawnRound(): boolean
	if not initialized then
		warn("[EnemyService] SpawnRound requiere Initialize() primero.")
		return false
	end

	if roundSpawned then
		warn("[EnemyService] El enemigo ya fue generado en esta ronda.")
		return false
	end

	roundSpawned = true

	local oldFolder = Workspace:FindFirstChild("CrystalQuestEnemies")
	if oldFolder then
		oldFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "CrystalQuestEnemies"
	folder.Parent = Workspace

	local position = generateEnemyPosition()
	if not position then
		return false
	end

	createEnemy(position, folder)

	return true
end

return EnemyService
