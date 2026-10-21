--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DoorService = {}

local initialized = false
local startTriggered = false
local activeTrigger: Part? = nil

type OnPlayerCrossed = (Player) -> boolean

function DoorService.Initialize(onPlayerCrossed: OnPlayerCrossed)
	if initialized then return end
	initialized = true

	local oldCourse = Workspace:FindFirstChild("CrystalQuestCourse")
	if oldCourse then oldCourse:Destroy() end

	local course = Instance.new("Folder")
	course.Name = "CrystalQuestCourse"
	course.Parent = Workspace

	-- Creamos el sensor visual y de colisión en el hueco
	local trigger = Instance.new("Part")
	trigger.Name = "DoorTrigger"
	trigger.Size = Vector3.new(Config.DoorWidth or 10, Config.StartLineTriggerHeight, Config.StartLineTriggerDepth)
	trigger.Position = Vector3.new(0, trigger.Size.Y / 2, Config.StartLineZ)
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.CanTouch = true
	trigger.CanQuery = false
	trigger.Transparency = 0.5
	trigger.Material = Enum.Material.Neon
	trigger.Color = Color3.fromRGB(255, 230, 70) -- Amarillo
	trigger.Parent = course
	
	activeTrigger = trigger

	trigger.Touched:Connect(function(hit: BasePart)
		if startTriggered then return end

		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then return end

		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end

		startTriggered = true
		trigger.CanTouch = false

		local accepted = onPlayerCrossed(player)

		if not accepted then
			startTriggered = false
			trigger.CanTouch = true
			return
		end

		trigger.Color = Color3.fromRGB(70, 255, 100) -- Verde
		trigger.Transparency = 1 -- Desaparece al iniciar
		print("[DoorService] Ronda iniciada por " .. player.Name)
	end)
end

function DoorService.Reset()
	startTriggered = false
	if activeTrigger then
		activeTrigger.CanTouch = true
		activeTrigger.Color = Color3.fromRGB(255, 230, 70)
		activeTrigger.Transparency = 0.5
	end
end

return DoorService