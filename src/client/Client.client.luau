--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local services = script.Parent:WaitForChild("services")
local MapBoundsService = require(services:WaitForChild("MapBoundsService"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local purchaseUpgrade = remotes:WaitForChild("PurchaseUpgrade") :: RemoteFunction
local retryEvent = remotes:WaitForChild("RetryRound") :: RemoteEvent

-- =========================================================
-- 1. CREACIÓN DE LA INTERFAZ (HUD SUPERIOR Y BOTONES)
-- =========================================================
local gui = Instance.new("ScreenGui")
gui.Name = "CrystalQuestGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- Contenedor principal superior (Horizontal)
local topHud = Instance.new("Frame")
topHud.Name = "TopHud"
topHud.Size = UDim2.new(0, 680, 0, 60)
topHud.Position = UDim2.new(0.5, 0, 0, 20)
topHud.AnchorPoint = Vector2.new(0.5, 0)
topHud.BackgroundColor3 = Color3.fromRGB(25, 28, 36)
topHud.BackgroundTransparency = 0.15
topHud.Parent = gui

local topHudCorner = Instance.new("UICorner")
topHudCorner.CornerRadius = UDim.new(0, 12)
topHudCorner.Parent = topHud

local topHudStroke = Instance.new("UIStroke")
topHudStroke.Color = Color3.fromRGB(80, 100, 150)
topHudStroke.Thickness = 2
topHudStroke.Transparency = 0.5
topHudStroke.Parent = topHud

-- Layout para organizar los elementos del TopHud
local topLayout = Instance.new("UIListLayout")
topLayout.FillDirection = Enum.FillDirection.Horizontal
topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
topLayout.Padding = UDim.new(0, 20)
topLayout.Parent = topHud

-- Función auxiliar para crear los bloques de datos (Label + Valor)
local function createStatBlock(name: string, iconText: string, initialText: string, textColor: Color3): TextLabel
	local frame = Instance.new("Frame")
	frame.Name = name .. "Frame"
	frame.Size = UDim2.new(0, 130, 1, 0)
	frame.BackgroundTransparency = 1
	frame.Parent = topHud

	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = iconText .. " " .. initialText
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = textColor
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = frame

	return label
end

-- Creación de los textos informativos del HUD
local objectiveLabel = createStatBlock("ObjectiveLabel", "💎", "0 Cristales", Color3.fromRGB(100, 200, 255))
local roundScoreLabel = createStatBlock("RoundScoreLabel", "⭐", "-- Pts", Color3.fromRGB(255, 165, 0))
local timerLabel = createStatBlock("TimerLabel", "⏱️", "0s", Color3.fromRGB(255, 255, 255))
local coinsLabel = createStatBlock("CoinsLabel", "🪙", "0", Color3.fromRGB(255, 215, 0))

-- Contenedor inferior derecho para los botones de compra
local shopFrame = Instance.new("Frame")
shopFrame.Name = "ShopFrame"
shopFrame.Size = UDim2.new(0, 200, 0, 140)
shopFrame.Position = UDim2.new(1, -20, 1, -20)
shopFrame.AnchorPoint = Vector2.new(1, 1)
shopFrame.BackgroundColor3 = Color3.fromRGB(25, 28, 36)
shopFrame.BackgroundTransparency = 0.15
shopFrame.Parent = gui

local shopCorner = Instance.new("UICorner")
shopCorner.CornerRadius = UDim.new(0, 12)
shopCorner.Parent = shopFrame

local shopStroke = Instance.new("UIStroke")
shopStroke.Color = Color3.fromRGB(80, 100, 150)
shopStroke.Thickness = 2
shopStroke.Transparency = 0.5
shopStroke.Parent = shopFrame

local shopLayout = Instance.new("UIListLayout")
shopLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
shopLayout.VerticalAlignment = Enum.VerticalAlignment.Center
shopLayout.Padding = UDim.new(0, 8)
shopLayout.Parent = shopFrame

-- Función auxiliar para crear botones
local function makeButton(name: string, text: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Size = UDim2.new(1, -24, 0, 32)
	button.BackgroundColor3 = color
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.AutoButtonColor = true
	button.Parent = shopFrame

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = button

	return button
end

local upgradeButton = makeButton("UpgradeButton", "Mejora x2 (25)", Color3.fromRGB(66, 103, 180))
local productButton = makeButton("ProductButton", "Comprar 100 🪙", Color3.fromRGB(34, 139, 34))
local passButton = makeButton("PassButton", "Game Pass x2", Color3.fromRGB(180, 66, 160))

-- Texto de estado (flotante en el centro superior, debajo del HUD)
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(0, 600, 0, 40)
statusLabel.Position = UDim2.new(0.5, 0, 0, 90)
statusLabel.AnchorPoint = Vector2.new(0.5, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 24
statusLabel.TextStrokeTransparency = 0.5
statusLabel.Text = "¡Recoge todos los cristales azules!"
statusLabel.Parent = gui

-- =========================================================
-- NUEVO: PANTALLA DE DERROTA Y BOTÓN REINTENTAR
-- =========================================================
local gameOverFrame = Instance.new("Frame")
gameOverFrame.Name = "GameOverFrame"
gameOverFrame.Size = UDim2.new(0, 300, 0, 160)
gameOverFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
gameOverFrame.AnchorPoint = Vector2.new(0.5, 0.5)
gameOverFrame.BackgroundColor3 = Color3.fromRGB(25, 28, 36)
gameOverFrame.BackgroundTransparency = 0.1
gameOverFrame.Visible = false
gameOverFrame.Parent = gui

local goCorner = Instance.new("UICorner")
goCorner.CornerRadius = UDim.new(0, 12)
goCorner.Parent = gameOverFrame

local goStroke = Instance.new("UIStroke")
goStroke.Color = Color3.fromRGB(255, 70, 70)
goStroke.Thickness = 3
goStroke.Parent = gameOverFrame

local goTitle = Instance.new("TextLabel")
goTitle.Size = UDim2.new(1, 0, 0, 50)
goTitle.Position = UDim2.new(0, 0, 0, 15)
goTitle.BackgroundTransparency = 1
goTitle.Text = "¡HAS MUERTO!"
goTitle.TextColor3 = Color3.fromRGB(255, 70, 70)
goTitle.Font = Enum.Font.GothamBold
goTitle.TextSize = 28
goTitle.Parent = gameOverFrame

local retryBtn = Instance.new("TextButton")
retryBtn.Size = UDim2.new(0.8, 0, 0, 45)
retryBtn.Position = UDim2.new(0.1, 0, 0.6, 0)
retryBtn.BackgroundColor3 = Color3.fromRGB(66, 103, 180)
retryBtn.Text = "Volver a intentar"
retryBtn.TextColor3 = Color3.new(1, 1, 1)
retryBtn.Font = Enum.Font.GothamBold
retryBtn.TextSize = 18
retryBtn.Parent = gameOverFrame

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 6)
btnCorner.Parent = retryBtn

retryBtn.Activated:Connect(function()
	gameOverFrame.Visible = false
	retryEvent:FireServer()
end)

-- =========================================================
-- 2. VARIABLES DE ESTADO
-- =========================================================
local gameState = ReplicatedStorage:WaitForChild("GameState")

local timeRemaining = gameState:WaitForChild("TimeRemaining") :: IntValue
local blueRemaining = gameState:WaitForChild("BlueRemaining") :: IntValue
local yellowRemaining = gameState:WaitForChild("YellowRemaining") :: IntValue
local roundStatus = gameState:WaitForChild("Status") :: StringValue

local function updateRoundUI()
	objectiveLabel.Text = "💎 " .. tostring(blueRemaining.Value + yellowRemaining.Value) .. " Cristales"
	timerLabel.Text = "⏱️ " .. tostring(timeRemaining.Value) .. "s"

	if roundStatus.Value == "Waiting" then
		statusLabel.Text = "Cruza la línea de salida para comenzar."
		statusLabel.TextColor3 = Color3.fromRGB(255, 230, 70)
		gameOverFrame.Visible = false
		MapBoundsService.Reset() -- Abre la pared sur de nuevo
	elseif roundStatus.Value == "Playing" then
		statusLabel.Text = "¡Recoge todos los cristales!"
		statusLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
		MapBoundsService.CloseSouthWall()
	elseif roundStatus.Value == "Won" then
		statusLabel.Text = "¡GANASTE! Has recogido todo."
		statusLabel.TextColor3 = Color3.fromRGB(70, 255, 100)
		gameOverFrame.Visible = false
	elseif roundStatus.Value == "Lost" then
		statusLabel.Text = "¡PERDISTE! Se acabó el tiempo."
		statusLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
		gameOverFrame.Visible = true -- Muestra la pantalla de reintento
	end
end

timeRemaining.Changed:Connect(updateRoundUI)
blueRemaining.Changed:Connect(updateRoundUI)
yellowRemaining.Changed:Connect(updateRoundUI)
roundStatus.Changed:Connect(updateRoundUI)

updateRoundUI()

-- =========================================================
-- 3. ACTUALIZACIÓN DEL SALDO GLOBAL (MONEDAS)
-- =========================================================
local leaderstats = player:WaitForChild("leaderstats")
local coinsValue = leaderstats:WaitForChild("Coins") :: IntValue

local function updateCoins()
	coinsLabel.Text = "🪙 " .. tostring(coinsValue.Value)
end

coinsValue:GetPropertyChangedSignal("Value"):Connect(updateCoins)

updateCoins()

-- =========================================================
-- 4. ACTUALIZACIÓN DE PUNTOS DE LA PARTIDA ACTUAL
-- =========================================================
-- Busca 'RoundScore' en GameState, o 'Score' en leaderstats.
local roundScoreValue = gameState:FindFirstChild("RoundScore") :: IntValue?
if not roundScoreValue then
	roundScoreValue = leaderstats:FindFirstChild("Score") :: IntValue?
end

local function updateRoundScore()
	if roundScoreValue then
		roundScoreLabel.Text = "⭐ " .. tostring(roundScoreValue.Value) .. " Pts"
	end
end

if roundScoreValue then
	roundScoreValue.Changed:Connect(updateRoundScore)
	updateRoundScore()
end

-- =========================================================
-- 5. COMPRA DE LA MEJORA
-- =========================================================
upgradeButton.Activated:Connect(function()
	upgradeButton.Active = false
	statusLabel.Text = "Procesando compra..."
	statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)

	local ok, result = pcall(function()
		return purchaseUpgrade:InvokeServer("DoublePickup")
	end)

	if ok and type(result) == "table" then
		statusLabel.Text = tostring(result.message)
		statusLabel.TextColor3 = Color3.fromRGB(70, 255, 100)
	else
		statusLabel.Text = "No se pudo completar la solicitud."
		statusLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
	end

	upgradeButton.Active = true
end)

-- =========================================================
-- 6. DEVELOPER PRODUCT
-- =========================================================
productButton.Activated:Connect(function()
	if Config.CoinPackProductId <= 0 then
		statusLabel.Text = "Falta configurar el ID del producto."
		statusLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
		return
	end

	local ok = pcall(function()
		MarketplaceService:PromptProductPurchase(player, Config.CoinPackProductId)
	end)

	if not ok then
		statusLabel.Text = "No se pudo abrir la compra."
		statusLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
	end
end)

-- =========================================================
-- 7. GAME PASS
-- =========================================================
passButton.Activated:Connect(function()
	if Config.GamePassDoubleCoinsId <= 0 then
		statusLabel.Text = "Falta configurar el ID del Game Pass."
		statusLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
		return
	end

	local ok = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, Config.GamePassDoubleCoinsId)
	end)

	if not ok then
		statusLabel.Text = "No se pudo abrir la compra."
		statusLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
	end
end)

-- =========================================================
-- 8. INICIALIZACIÓN DE LÍMITES DEL MAPA (PAREDES)
-- =========================================================
MapBoundsService.Initialize()
