--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage");

local Config = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
);

type CrystalType = Config.CrystalType;
local RoundService = {};

-- =========================================================
-- ESTADO REPLICADO AL CLIENTE
-- =========================================================
local gameState = Instance.new("Folder");
gameState.Name = "GameState";
gameState.Parent = ReplicatedStorage;

local timeRemaining = Instance.new("IntValue");
timeRemaining.Name = "TimeRemaining";
timeRemaining.Value = 0;
timeRemaining.Parent = gameState;

local blueRemaining = Instance.new("IntValue");
blueRemaining.Name = "BlueRemaining";
blueRemaining.Value = 0;
blueRemaining.Parent = gameState;

local yellowRemaining = Instance.new("IntValue");
yellowRemaining.Name = "YellowRemaining";
yellowRemaining.Value = 0;
yellowRemaining.Parent = gameState;

local status = Instance.new("StringValue");
status.Name = "Status";
status.Value = "Waiting";
status.Parent = gameState;

-- =========================================================
-- ESTADO INTERNO DEL SERVIDOR
-- =========================================================
local roundActive = false;
local roundStarted = false;
local endTime = 0;

-- =========================================================
-- INICIAR RONDA
-- =========================================================
function RoundService.Start(totalBlueCrystals: number, totalYellowCrystals: number)
    if roundStarted then
        warn("La ronda ya fue iniciada.");
        return;
    end;

    roundStarted = true;

    blueRemaining.Value = totalBlueCrystals;
    yellowRemaining.Value = totalYellowCrystals;

    local totalTime =
        totalBlueCrystals * Config.SecondsPerBlueCrystal;

    totalTime += totalYellowCrystals * Config.SecondsPerYellowCrystal;

    timeRemaining.Value = totalTime;

    -- Caso extremo: no se generó ningún cristal azul.
    if totalBlueCrystals + totalYellowCrystals <= 0 then
        status.Value = "Won";
        roundActive = false;
        return;
    end;

    status.Value = "Playing";
    roundActive = true;

    print(
        "[Round] Cristales azules: "
            .. tostring(totalBlueCrystals)
                .. " | Tiempo inicial: "
                    .. tostring(totalTime)
                        .. " segundos"
    );

    -- Guardamos el instante exacto en que debe terminar
    -- la ronda. Esto evita acumular pequeños errores de
    -- tiempo producidos por task.wait().
    endTime = os.clock() + totalTime;

    task.spawn(function()
        while roundActive do
            local remaining = math.max(
                0,
                math.ceil(endTime - os.clock())
            );

            timeRemaining.Value = remaining;

            if remaining <= 0 then
                roundActive = false;
                status.Value = "Lost";

                print("[Round] El jugador perdió.");

                break;
            end;

            -- Actualizamos varias veces por segundo para que
            -- el valor mostrado sea más preciso.
            task.wait(0.1);
        end;
    end);
end;

-- =========================================================
-- CONSULTAR SI LA RONDA SIGUE ACTIVA
-- =========================================================
function RoundService.IsActive(): boolean
    return roundActive;
end;

-- =========================================================
-- Penalizar tiempo por recolección de cristales rojos
-- =========================================================
-- Reduce el tiempo real de la ronda, adelantando la fecha límite.
function RoundService.PenalizeTime(penalty: number)
    if not roundActive then
        return;
    end;

    if penalty <= 0 then
        warn("[Round] La penalización debe ser mayor que cero.");
        return;
    end;

    local now = os.clock();

    -- La fecha límite es la fuente de verdad del temporizador.
    endTime -= penalty;

    -- Actualizamos también el valor visible para el jugador.
    local remaining = math.max(
        0,
        math.ceil(endTime - now)
    );

    timeRemaining.Value = remaining;

    print(
        "[Round] Penalización: "
            .. tostring(penalty)
                .. " segundos. Tiempo restante: "
                    .. tostring(remaining)
    );

    -- Si la penalización consume todo el tiempo disponible,
    -- terminamos la ronda inmediatamente.
    if remaining <= 0 then
        timeRemaining.Value = 0;
        roundActive = false;
        status.Value = "Lost";

        print("[Round] El jugador perdió por una penalización.");
    end;
end;

-- =========================================================
-- REGISTRAR RECOLECCIÓN
-- =========================================================
function RoundService.RegisterCrystalCollected(
    crystalType: CrystalType
)
    if not roundActive then
        return;
    end;

    -- Los cristales rojos no forman parte del objetivo.
    if crystalType == "Red" then
        RoundService.PenalizeTime(Config.RedeemPenalty);
        return;
    end;

    if crystalType == "Blue" then
        blueRemaining.Value -= 1;
    end;

    if crystalType == "Yellow" then
        yellowRemaining.Value -= 1;
    end;

    print(
        "[Round] Cristales restantes: "
            .. tostring(blueRemaining.Value)
                .. " azules, "
                    .. tostring(yellowRemaining.Value)
                        .. " amarillos."
    );
    if blueRemaining.Value + yellowRemaining.Value <= 0 then
        blueRemaining.Value = 0;
        yellowRemaining.Value = 0;

        roundActive = false;
        status.Value = "Won";

        timeRemaining.Value = math.max(
            0,
            timeRemaining.Value
        );

        print("[Round] ¡El jugador ganó!");
    end;
end;

return RoundService;
