--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
)

local RoundService = {}

-- =========================================================
-- ESTADO REPLICADO AL CLIENTE
-- =========================================================

local gameState = Instance.new("Folder")
gameState.Name = "GameState"
gameState.Parent = ReplicatedStorage

local timeRemaining = Instance.new("IntValue")
timeRemaining.Name = "TimeRemaining"
timeRemaining.Value = 0
timeRemaining.Parent = gameState

local blueRemaining = Instance.new("IntValue")
blueRemaining.Name = "BlueRemaining"
blueRemaining.Value = 0
blueRemaining.Parent = gameState

local status = Instance.new("StringValue")
status.Name = "Status"
status.Value = "Waiting"
status.Parent = gameState

-- =========================================================
-- ESTADO INTERNO DEL SERVIDOR
-- =========================================================

local roundActive = false
local roundStarted = false

-- =========================================================
-- INICIAR RONDA
-- =========================================================

function RoundService.Start(totalBlueCrystals: number)
    if roundStarted then
        warn("La ronda ya fue iniciada.")
        return
    end

    roundStarted = true

    blueRemaining.Value = totalBlueCrystals

    local totalTime =
        totalBlueCrystals * Config.SecondsPerBlueCrystal

    timeRemaining.Value = totalTime

    -- Caso extremo: no se generó ningún cristal azul.
    if totalBlueCrystals <= 0 then
        status.Value = "Won"
        roundActive = false
        return
    end

    status.Value = "Playing"
    roundActive = true

    print(
        "[Round] Cristales azules: "
            .. tostring(totalBlueCrystals)
            .. " | Tiempo inicial: "
            .. tostring(totalTime)
            .. " segundos"
    )

    -- Guardamos el instante exacto en que debe terminar
    -- la ronda. Esto evita acumular pequeños errores de
    -- tiempo producidos por task.wait().
    local endTime = os.clock() + totalTime

    task.spawn(function()
        while roundActive do
            local remaining = math.max(
                0,
                math.ceil(endTime - os.clock())
            )

            timeRemaining.Value = remaining

            if remaining <= 0 then
                roundActive = false
                status.Value = "Lost"

                print("[Round] El jugador perdió.")

                break
            end

            -- Actualizamos varias veces por segundo para que
            -- el valor mostrado sea más preciso.
            task.wait(0.1)
        end
    end)
end

-- =========================================================
-- CONSULTAR SI LA RONDA SIGUE ACTIVA
-- =========================================================

function RoundService.IsActive(): boolean
    return roundActive
end

-- =========================================================
-- REGISTRAR RECOLECCIÓN
-- =========================================================

function RoundService.RegisterCrystalCollected(
    isPositive: boolean
)
    if not roundActive then
        return
    end

    -- Los cristales rojos no forman parte del objetivo.
    if not isPositive then
        return
    end

    blueRemaining.Value -= 1

    if blueRemaining.Value <= 0 then
        blueRemaining.Value = 0

        roundActive = false
        status.Value = "Won"

        timeRemaining.Value = math.max(
            0,
            timeRemaining.Value
        )

        print("[Round] ¡El jugador ganó!")
    end
end

return RoundService