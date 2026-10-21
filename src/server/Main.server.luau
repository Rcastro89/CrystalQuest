--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local services = script.Parent:WaitForChild("services")
local DataService = require(services:WaitForChild("DataService"))
local RoundService = require(services:WaitForChild("RoundService"))
local CrystalService = require(services:WaitForChild("CrystalService"))
local EnemyService = require(services:WaitForChild("EnemyService"))
local DoorService = require(services:WaitForChild("DoorService")) -- NUEVO
local MonetizationService = require(services:WaitForChild("MonetizationService"))
local PlayerLifecycleService = require(services:WaitForChild("PlayerLifecycleService"))
local EconomyService = require(services:WaitForChild("EconomyService"))

type CrystalType = Config.CrystalType

-- =========================================================
-- EVITAR QUE LOS JUGADORES SE REAPAREZCAN AUTOMÁTICAMENTE
-- =========================================================
Players.RespawnTime = math.huge

-- =========================================================
-- INICIALIZACIÓN DE MONETIZACIÓN
-- =========================================================
MonetizationService.Initialize(PlayerLifecycleService.UpdateLeaderstats)
EconomyService.Initialize(PlayerLifecycleService.UpdateLeaderstats)

-- =========================================================
-- REMOTES
-- =========================================================
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local retryEvent = remotes:FindFirstChild("RetryRound")
if not retryEvent then
	retryEvent = Instance.new("RemoteEvent")
	retryEvent.Name = "RetryRound"
	retryEvent.Parent = remotes
end

-- =========================================================
-- COORDINACIÓN DE LA RONDA
-- =========================================================
local function isPlayerReady(player: Player): boolean
	return DataService.Get(player) ~= nil
end

local function onCrystalCollected(player: Player, crystalType: CrystalType)
	if not isPlayerReady(player) then
		return
	end
	RoundService.RegisterCrystalCollected(crystalType)
	EconomyService.AwardCrystalReward(player, crystalType)
end

local function onDoorCrossed(player: Player): boolean
	if not isPlayerReady(player) then
		warn("[Main] El jugador todavía no está preparado: " .. player.Name)
		return false
	end

	EconomyService.ResetRoundScore(player)

	local totalBlue, totalYellow = CrystalService.SpawnRound(isPlayerReady, onCrystalCollected)
	RoundService.Start(totalBlue, totalYellow)

	local enemySpawned = EnemyService.SpawnRound(function(touchedPlayer: Player)
		warn("[Main] " .. touchedPlayer.Name .. " tocó al enemigo.")
		RoundService.Lose()
	end)

	if not enemySpawned then
		warn("[Main] No se pudo generar el enemigo en esta ronda.")
	end

	return true
end

-- =========================================================
-- LÓGICA DE DERROTA Y REINTENTO
-- =========================================================
local gameState = ReplicatedStorage:WaitForChild("GameState")
local roundStatus = gameState:WaitForChild("Status") :: StringValue

roundStatus.Changed:Connect(function(newStatus)
	if newStatus == "Lost" then
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					humanoid.Health = 0
				end
			end
		end
	elseif newStatus == "Won" then
		CrystalService.Reset()
		EnemyService.Reset()
	end
end)

retryEvent.OnServerEvent:Connect(function(player)
	RoundService.Reset()
	CrystalService.Reset()
	EnemyService.Reset()
	DoorService.Reset() -- Actualizado a DoorService
	EconomyService.ResetRoundScore(player)
	player:LoadCharacterAsync()
end)

-- =========================================================
-- INICIALIZACIÓN DEL JUEGO
-- =========================================================
EnemyService.Initialize()
DoorService.Initialize(onDoorCrossed) -- Actualizado a DoorService
PlayerLifecycleService.Initialize()
