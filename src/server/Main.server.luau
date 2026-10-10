--!strict
local Players = game:GetService("Players");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"));
local DataService = require(script.Parent.DataService);
local RoundService = require(script.Parent.RoundService);
local services = script.Parent:WaitForChild("services");
local CrystalService = require(services:WaitForChild("CrystalService"));
local StartLineService = require(services:WaitForChild("StartLineService"));
local MonetizationService = require(services:WaitForChild("MonetizationService"));

type CrystalType = Config.CrystalType;

-- =========================================================
-- 2. ESTADO DE SESIÓN
-- =========================================================
local setupStarted: { [Player]: boolean } = {};

-- =========================================================
-- 3. LEADERSTATS
-- =========================================================
local function createLeaderstats(player: Player)
    local data = DataService.Get(player);

    if not data then
        return;
    end;

    local leaderstats = Instance.new("Folder");
    leaderstats.Name = "leaderstats";
    leaderstats.Parent = player;

    local coins = Instance.new("IntValue");
    coins.Name = "Coins";
    coins.Value = data.Coins;
    coins.Parent = leaderstats;
end;

local function updateLeaderstats(player: Player)
    local data = DataService.Get(player);

    if not data then
        return;
    end;

    local leaderstats = player:FindFirstChild("leaderstats");
    local coins = leaderstats and leaderstats:FindFirstChild("Coins");

    if coins and coins:IsA("IntValue") then
        coins.Value = data.Coins;
    end;
end;

MonetizationService.Initialize(updateLeaderstats);

-- =========================================================
-- 5. RECOMPENSAS
-- =========================================================
local function awardCoins(player: Player, crystalType: CrystalType)
    local data = DataService.Get(player);

    if not data then
        return;
    end;

    local multiplier = data.PickupMultiplier;

    if MonetizationService.HasDoubleCoins(player) then
        multiplier *= 2;
    end;

    local amount = Config.BluePickupReward * multiplier;

    if crystalType == "Red" then
        amount = -amount;
    elseif crystalType == "Yellow" then
        amount = Config.YellowPickupReward * multiplier;
    end;

    print(player.Name .. " recolectó un cristal: " .. amount .. " monedas." .. " Multiplicador: " .. multiplier .. " crystalType: " .. tostring(crystalType));

    if DataService.AddCoins(player, amount) then
        updateLeaderstats(player);
    end;
end;

-- =========================================================
-- INICIO DE LA RONDA AL CRUZAR LA LÍNEA
-- =========================================================
local function isPlayerReady(player: Player): boolean
    return DataService.Get(player) ~= nil;
end;

local function onCrystalCollected(
    player: Player,
    crystalType: CrystalType
)
    if not isPlayerReady(player) then
        return;
    end;

    -- Cada servicio se encarga de su propia responsabilidad.
    RoundService.RegisterCrystalCollected(crystalType);

    awardCoins(player, crystalType);
end;

local function onStartLineCrossed(player: Player): boolean
    if not isPlayerReady(player) then
        warn(
            "[Main] El jugador todavía no está preparado: "
                .. player.Name
        );

        return false;
    end;

    -- Primero generamos los objetivos del recorrido.
    local totalBlue, totalYellow = CrystalService.SpawnRound(
        isPlayerReady,
        onCrystalCollected
    );

    -- Después iniciamos el temporizador con las cantidades reales.
    RoundService.Start(totalBlue, totalYellow);

    return true;
end;

-- La línea queda preparada, pero la ronda continúa esperando.
StartLineService.Initialize(onStartLineCrossed);

-- =========================================================
-- 9. CICLO DE VIDA DEL JUGADOR
-- =========================================================
local function onPlayerAdded(player: Player)
    if setupStarted[player] then
        return;
    end;

    setupStarted[player] = true;

    local loaded = DataService.Load(player);

    if not loaded then
        -- No iniciamos una sesión vacía cuando falla la carga:
        -- podríamos terminar sobrescribiendo el progreso guardado.
        player:Kick(
            "No pudimos cargar tus datos. Vuelve a intentarlo."
        );

        return;
    end;

    if player.Parent ~= Players then
        DataService.Release(player);
        return;
    end;

    createLeaderstats(player);

    MonetizationService.InitializePlayer(player);
end;

Players.PlayerAdded:Connect(function(player)
    task.spawn(onPlayerAdded, player);
end);

-- También cubre jugadores que ya estaban conectados al iniciar el script.
for _, player in Players:GetPlayers() do
    task.spawn(onPlayerAdded, player);
end;

Players.PlayerRemoving:Connect(function(player)
    if DataService.Get(player) then
        local saved = DataService.Save(player);

        if not saved then
            warn("Fallo al guardar los datos de " .. player.Name);
        end;

        DataService.Release(player);
    end;

    setupStarted[player] = nil;
    MonetizationService.CleanupPlayer(player);
end);

-- =========================================================
-- 10. AUTOSAVE Y CIERRE DEL SERVIDOR
-- =========================================================
task.spawn(function()
    while true do
        task.wait(Config.AutosaveSeconds);

        for _, player in Players:GetPlayers() do
            if DataService.Get(player) then
                local saved = DataService.Save(player);

                if not saved then
                    warn("Fallo en autosave de " .. player.Name);
                end;

                task.wait(0.1);
            end;
        end;
    end;
end);

game:BindToClose(function()
    local pending = 0;

    for _, player in Players:GetPlayers() do
        if DataService.Get(player) then
            pending += 1;

            local playerToSave = player;

            task.spawn(function()
                local saved = DataService.Save(playerToSave);

                if not saved then
                    warn(
                        "Fallo al guardar durante el cierre: "
                            .. playerToSave.Name
                    );
                end;

                pending -= 1;
            end);
        end;
    end;

    while pending > 0 do
        task.wait(0.1);
    end;
end);
