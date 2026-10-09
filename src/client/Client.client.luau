--!strict
local Players = game:GetService("Players");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local MarketplaceService = game:GetService("MarketplaceService");

local Config = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
);

local player = Players.LocalPlayer;
local playerGui = player:WaitForChild("PlayerGui");

local remotes = ReplicatedStorage:WaitForChild("Remotes");

local purchaseUpgrade = remotes:WaitForChild(
    "PurchaseUpgrade"
) :: RemoteFunction;

-- =========================================================
-- 1. CREACIÓN DE LA INTERFAZ
-- =========================================================
local gui = Instance.new("ScreenGui");
gui.Name = "CrystalQuestGui";
gui.ResetOnSpawn = false;
gui.Parent = playerGui;

local panel = Instance.new("Frame");
panel.Name = "Panel";
panel.Size = UDim2.fromOffset(320, 320);
panel.Position = UDim2.fromOffset(20, 20);
panel.BackgroundColor3 = Color3.fromRGB(32, 38, 52);
panel.Parent = gui;

local function makeLabel(
    name: string,
    text: string,
    position: UDim2,
    size: UDim2
): TextLabel

    local label = Instance.new("TextLabel");
    label.Name = name;
    label.Text = text;
    label.Position = position;
    label.Size = size;
    label.BackgroundTransparency = 1;
    label.TextColor3 = Color3.new(0.807843, 0.105882, 0.105882);
    label.TextScaled = true;
    label.Parent = panel;

    return label;
end;

local function makeButton(
    name: string,
    text: string,
    y: number
): TextButton

    local button = Instance.new("TextButton");
    button.Name = name;
    button.Text = text;
    button.Position = UDim2.fromOffset(12, y);
    button.Size = UDim2.new(1, -24, 0, 36);
    button.BackgroundColor3 = Color3.fromRGB(66, 103, 180);
    button.TextColor3 = Color3.new(1, 1, 1);
    button.TextScaled = true;
    button.Parent = panel;

    return button;
end;

local objectiveLabel = makeLabel(
    "ObjectiveLabel",
    "Cristales azules y amarillos: ...",
    UDim2.fromOffset(12, 8),
    UDim2.new(1, -24, 0, 28)
);

local timerLabel = makeLabel(
    "TimerLabel",
    "Tiempo: ...",
    UDim2.fromOffset(12, 36),
    UDim2.new(1, -24, 0, 34)
);

local coinsLabel = makeLabel(
    "CoinsLabel",
    "Monedas: ...",
    UDim2.fromOffset(12, 70),
    UDim2.new(1, -24, 0, 34)
);
local upgradeButton = makeButton(
    "UpgradeButton",
    "Mejora x2 (25 monedas)",
    110
);

local productButton = makeButton(
    "ProductButton",
    "Comprar 100 monedas",
    152
);

local passButton = makeButton(
    "PassButton",
    "Comprar Game Pass x2",
    194
);

local statusLabel = makeLabel(
    "StatusLabel",
    "¡Recoge todos los cristales azules!",
    UDim2.fromOffset(12, 238),
    UDim2.new(1, -24, 0, 60)
);


local gameState = ReplicatedStorage:WaitForChild("GameState");

local timeRemaining = gameState:WaitForChild(
    "TimeRemaining"
) :: IntValue;

local blueRemaining = gameState:WaitForChild(
    "BlueRemaining"
) :: IntValue;

local yellowRemaining = gameState:WaitForChild(
    "YellowRemaining"
) :: IntValue;

local roundStatus = gameState:WaitForChild(
    "Status"
) :: StringValue;

local function updateRoundUI()
    print("Actualizando UI de la ronda..." .. timeRemaining.Value);
    objectiveLabel.Text =
        "Cristales azules y amarillos: "
            .. tostring(blueRemaining.Value + yellowRemaining.Value);

    timerLabel.Text =
        "Tiempo: "
            .. tostring(timeRemaining.Value);

    if roundStatus.Value == "Waiting" then

        statusLabel.Text =
            "Preparando la ronda...";

    elseif roundStatus.Value == "Playing" then

        statusLabel.Text =
            "¡Recoge todos los cristales azules y amarillos!";

    elseif roundStatus.Value == "Won" then

        statusLabel.Text =
            "¡GANASTE! Recogiste todos los cristales azules y amarillos.";

    elseif roundStatus.Value == "Lost" then

        statusLabel.Text =
            "¡PERDISTE! Se acabó el tiempo.";

    end;
end;

timeRemaining.Changed:Connect(updateRoundUI);

blueRemaining.Changed:Connect(updateRoundUI);

yellowRemaining.Changed:Connect(updateRoundUI);

roundStatus.Changed:Connect(updateRoundUI);

updateRoundUI();

-- =========================================================
-- 2. ACTUALIZACIÓN DEL SALDO
-- =========================================================
local leaderstats = player:WaitForChild("leaderstats");
local coinsValue = leaderstats:WaitForChild("Coins") :: IntValue;

local function updateCoins()
    coinsLabel.Text = "Monedas: " .. tostring(coinsValue.Value);
end;

coinsValue:GetPropertyChangedSignal("Value"):Connect(updateCoins);

updateCoins();

-- =========================================================
-- 3. COMPRA DE LA MEJORA
-- =========================================================
upgradeButton.Activated:Connect(function()
    upgradeButton.Active = false;
    statusLabel.Text = "Procesando compra...";

    local ok, result = pcall(function()
        return purchaseUpgrade:InvokeServer("DoublePickup");
    end);

    if ok and type(result) == "table" then
        statusLabel.Text = tostring(result.message);
    else
        statusLabel.Text = "No se pudo completar la solicitud.";
    end;

    upgradeButton.Active = true;
end);

-- =========================================================
-- 4. DEVELOPER PRODUCT
-- =========================================================
productButton.Activated:Connect(function()
    if Config.CoinPackProductId <= 0 then
        statusLabel.Text = "Falta configurar el ID del producto.";
        return;
    end;

    local ok = pcall(function()
        MarketplaceService:PromptProductPurchase(
            player,
            Config.CoinPackProductId
        );
    end);

    if not ok then
        statusLabel.Text = "No se pudo abrir la compra.";
    end;
end);

-- =========================================================
-- 5. GAME PASS
-- =========================================================
passButton.Activated:Connect(function()
    if Config.GamePassDoubleCoinsId <= 0 then
        statusLabel.Text = "Falta configurar el ID del Game Pass.";
        return;
    end;

    local ok = pcall(function()
        MarketplaceService:PromptGamePassPurchase(
            player,
            Config.GamePassDoubleCoinsId
        );
    end);

    if not ok then
        statusLabel.Text = "No se pudo abrir la compra.";
    end;
end);
