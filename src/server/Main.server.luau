--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"));
local DataService = require(script.Parent.DataService);
local RoundService = require(script.Parent.RoundService);
local services = script.Parent:WaitForChild("services");
local CrystalService = require(services:WaitForChild("CrystalService"));
local StartLineService = require(services:WaitForChild("StartLineService"));
local MonetizationService = require(services:WaitForChild("MonetizationService"));
local PlayerLifecycleService = require(services:WaitForChild("PlayerLifecycleService"));

type CrystalType = Config.CrystalType;

-- =========================================================
-- INICIALIZACIÓN DE MONETIZACIÓN
-- =========================================================
MonetizationService.Initialize(PlayerLifecycleService.UpdateLeaderstats)


-- =========================================================
-- ECONOMÍA
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
        PlayerLifecycleService.UpdateLeaderstats(player)
    end;
end;

-- =========================================================
-- COORDINACIÓN DE LA RONDA
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

-- =========================================================
-- INICIALIZACIÓN DEL JUEGO
-- =========================================================

StartLineService.Initialize(onStartLineCrossed);
PlayerLifecycleService.Initialize()

