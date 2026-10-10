--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"));

local services = script.Parent:WaitForChild("services");
local DataService = require(services:WaitForChild("DataService"));
local RoundService = require(services:WaitForChild("RoundService"));
local CrystalService = require(services:WaitForChild("CrystalService"));
local StartLineService = require(services:WaitForChild("StartLineService"));
local MonetizationService = require(services:WaitForChild("MonetizationService"));
local PlayerLifecycleService = require(services:WaitForChild("PlayerLifecycleService"));
local EconomyService = require(services:WaitForChild("EconomyService"));

type CrystalType = Config.CrystalType;

-- =========================================================
-- INICIALIZACIÓN DE MONETIZACIÓN
-- =========================================================
MonetizationService.Initialize(PlayerLifecycleService.UpdateLeaderstats);
EconomyService.Initialize(PlayerLifecycleService.UpdateLeaderstats);

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

    -- La economía gestiona el saldo y los multiplicadores.
    EconomyService.AwardCrystalReward(player, crystalType)
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
PlayerLifecycleService.Initialize();
