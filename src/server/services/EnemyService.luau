--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local Debris = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local EnemyService = {}

local initialized = false
local roundSpawned = false
local triggered = false

type OnEnemyTouched = (Player) -> ()

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
		local candidate = Vector3.new(x, -1, z)

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

local function playLostTouchEnemySound(position: Vector3)
	print("[EnemyService] Reproduciendo sonido de contacto con enemigo en posición: " .. tostring(position))
	local attachment = Instance.new("Attachment")
	attachment.Name = "LostTouchEnemySoundAttachment"
	attachment.Position = position
	attachment.Parent = Workspace.Terrain

	local sound = Instance.new("Sound")
	sound.Name = "LostTouchEnemySound"

	sound.SoundId = Config.MonsterLostAudioId
	sound.Volume = Config.PickupSoundVolume
	sound.RollOffMaxDistance = Config.PickupSoundMaxDistance
	sound.Parent = attachment

	-- El sonido normal se limpia al terminar; este plazo es
	-- una protección por si el asset no llega a reproducirse.
	sound.Ended:Connect(function()
		attachment:Destroy()
	end)

	Debris:AddItem(attachment, 10)

	sound:Play()
end

-- =========================================================
-- MOVIMIENTO ALEATORIO DEL ENEMIGO
-- =========================================================
local function getRandomPointInMap(): Vector3
	local x = math.random(Config.CrystalMinX, Config.CrystalMaxX)
	local z = math.random(Config.CrystalMinZ, Config.CrystalMaxZ)
	return Vector3.new(x, 1, z)
end

local function walkToRandomPoint(enemyModel: Model)
	local humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	local rootPart = enemyModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart then
		return
	end

	if humanoid.Health <= 0 then
		return
	end

	local targetPos = getRandomPointInMap()

	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = false,
		WaypointSpacing = 4,
	})

	local success = pcall(function()
		path:ComputeAsync(rootPart.Position, targetPos)
	end)

	if not success or path.Status ~= Enum.PathStatus.Success then
		return
	end

	local waypoints = path:GetWaypoints()
	for i, waypoint in ipairs(waypoints) do
		if i == 1 then
			continue
		end
		if not enemyModel.Parent then
			return
		end
		humanoid:MoveTo(waypoint.Position)

		local finished = false
		local conn = humanoid.MoveToFinished:Connect(function()
			finished = true
		end)

		local timeoutAt = os.clock() + 2
		while not finished and os.clock() < timeoutAt and enemyModel.Parent do
			task.wait(0.1)
		end
		conn:Disconnect()

		if not finished then
			return
		end
	end
end

-- =========================================================
-- CREACIÓN DEL ENEMIGO (SÓLIDO, PROVOCA DERROTA SI TOCAS)
-- =========================================================
local function createEnemy(
	position: Vector3,
	parentFolder: Folder,
	onEnemyTouched: OnEnemyTouched?
): { RBXScriptConnection }
	local scale = Config.MonsterSizeScale or 1
	local monsterModel: Model? = nil
	print("Posición del enemigo: " .. tostring(position))
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
		fallback.Anchored = false
		fallback.CanCollide = true
		fallback.CanTouch = true
		fallback.CanQuery = true
		fallback.Parent = displayModel
		displayModel.PrimaryPart = fallback
	end

	displayModel.Name = "Enemy"

	local hitConnections: { RBXScriptConnection } = {}
	local enemyParts: { BasePart } = {}

	for _, descendant in ipairs(displayModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = true
			descendant.CanTouch = true
			descendant.CanQuery = true
			descendant.Massless = true

			local okOwner, _ = pcall(function()
				descendant:SetNetworkOwner(nil)
			end)
			_ = okOwner

			-- if descendant:IsA("Part") then
			-- 	local touchTransmitter = descendant:FindFirstChildOfClass("TouchTransmitter")
			-- 	if touchTransmitter then
			-- 		touchTransmitter:Destroy()
			-- 	end
			-- end
			table.insert(enemyParts, descendant)
		elseif descendant:IsA("BaseScript") then
			descendant.Disabled = true
		elseif descendant:IsA("Animator") then
			-- Se conserva el Animator para que el Humanoid tenga animación de caminar.
		elseif descendant:IsA("Humanoid") then
			descendant.MaxHealth = 100
			descendant.Health = 100
			descendant.WalkSpeed = 8
			descendant.JumpPower = 0
			descendant.PlatformStand = false
			descendant.AutoRotate = true

			-- Configurar animación de caminar manualmente,
			-- porque el script Animate del modelo no corre en el servidor.
			local animator = descendant:FindFirstChildOfClass("Animator")
			if animator then
				local walkAnim = Instance.new("Animation")
				walkAnim.AnimationId = "rbxassetid://507777826"
				local walkTrack = animator:LoadAnimation(walkAnim)
				walkTrack.Looped = true
				walkTrack.Priority = Enum.AnimationPriority.Movement

				descendant.Running:Connect(function(speed)
					if speed > 0.5 then
						if not walkTrack.IsPlaying then
							walkTrack:Play()
						end
						walkTrack:AdjustSpeed(speed / 8)
					else
						if walkTrack.IsPlaying then
							walkTrack:Stop()
						end
					end
				end)
			end
		end
	end

	if onEnemyTouched then
		for _, part in ipairs(enemyParts) do
			local conn = part.Touched:Connect(function(hit: BasePart)
				if triggered then
					return
				end

				if not roundSpawned then
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

				triggered = true
				onEnemyTouched(player)
				playLostTouchEnemySound(position)

				for _, c in ipairs(hitConnections) do
					pcall(function()
						c:Disconnect()
					end)
				end
				table.clear(hitConnections)
			end)

			table.insert(hitConnections, conn)
		end
	end

	local extents = displayModel:GetExtentsSize()
	local halfHeight = extents.Y / 2
	local worldCenterY = 1 + halfHeight
	displayModel:PivotTo(CFrame.new(position.X, worldCenterY, position.Z))

	if scale ~= 1 then
		local original = displayModel:GetPivot()
		displayModel:ScaleTo(scale)
		displayModel:PivotTo(original)
	end

	displayModel.Parent = parentFolder

	task.spawn(function()
		task.wait(1)
		while displayModel.Parent and roundSpawned do
			walkToRandomPoint(displayModel)
			task.wait(math.random(2, 5))
		end
	end)

	print(
		"[EnemyService] Enemigo colocado en ("
			.. tostring(math.floor(position.X))
			.. ", "
			.. tostring(math.floor(position.Z))
			.. ")"
	)

	return hitConnections
end

function EnemyService.SpawnRound(onEnemyTouched: OnEnemyTouched?): boolean
	if not initialized then
		warn("[EnemyService] SpawnRound requiere Initialize() primero.")
		return false
	end

	if roundSpawned then
		warn("[EnemyService] El enemigo ya fue generado en esta ronda.")
		return false
	end

	roundSpawned = true
	triggered = false

	local oldFolder = Workspace:FindFirstChild("CrystalQuestEnemies")
	if oldFolder then
		oldFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "CrystalQuestEnemies"
	folder.Parent = Workspace

	for i = 0, 32 do
		local position = generateEnemyPosition()
		if not position then
			return false
		end

		createEnemy(position, folder, onEnemyTouched)
	end

	return true
end

return EnemyService
