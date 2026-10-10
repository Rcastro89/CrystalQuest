--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage");

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"));
local DataService = require(script.Parent:WaitForChild("DataService"));
local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"));

local EconomyService = {};

type CrystalType = Config.CrystalType;
type UpdateLeaderstatsCallback = (player: Player) -> ();

local initialized = false;

-- Referencia a la función que actualiza las estadísticas del jugador.
local updateLeaderstatsCallback: UpdateLeaderstatsCallback? = nil;

-- =========================================================
-- INICIALIZACIÓN
-- =========================================================
function EconomyService.Initialize(
    updateLeaderstats: UpdateLeaderstatsCallback
)
    if initialized then
        warn("[Economy] El servicio ya fue inicializado.");
        return;
    end;

    initialized = true;
    updateLeaderstatsCallback = updateLeaderstats;
end;

-- =========================================================
-- RECOMPENSA DE UN CRISTAL
-- =========================================================
function EconomyService.AwardCrystalReward(
    player: Player,
    crystalType: CrystalType
)
    local data = DataService.Get(player);

    if not data then
        warn(
            "[Economy] No hay datos cargados para "
                .. player.Name
        );
        return;
    end;

    -- El multiplicador combina la mejora comprada y el Game Pass.
    local multiplier = data.PickupMultiplier;

    if MonetizationService.HasDoubleCoins(player) then
        multiplier *= 2;
    end;

    -- Calculamos la cantidad correspondiente al tipo de cristal.
    local amount = Config.BluePickupReward * multiplier;

    if crystalType == "Yellow" then
        amount = Config.YellowPickupReward * multiplier;
    end;

    if crystalType == "Red" then
        -- El rojo penaliza monedas en vez de concederlas.
        -- Limitamos la pérdida al saldo disponible para no quedar
        -- con monedas negativas.
        local penalty = math.floor(amount);
        local actualPenalty = math.min(data.Coins, penalty);

        if actualPenalty <= 0 then
            print(
                "[Economy] "
                    .. player.Name
                        .. " recogió un cristal rojo sin monedas "
                            .. "disponibles para descontar."
            );
            return;
        end;

        if not DataService.SpendCoins(player, actualPenalty) then
            warn(
                "[Economy] No se pudo descontar el saldo de "
                    .. player.Name
            );
            return;
        end;

        amount = -actualPenalty;
    else
        amount = math.floor(amount);

        if amount <= 0 then
            warn("[Economy] La recompensa debe ser positiva.");
            return;
        end;

        if not DataService.AddCoins(player, amount) then
            warn(
                "[Economy] No se pudo agregar el saldo de "
                    .. player.Name
            );
            return;
        end;
    end;

    -- Solo actualizamos la UI después de modificar correctamente los datos.
    local updateStats = updateLeaderstatsCallback;

    if updateStats then
        updateStats(player);
    end;

    print(
        "[Economy] "
            .. player.Name
                .. " | Cristal: "
                    .. crystalType
                        .. " | Monedas: "
                            .. tostring(amount)
                                .. " | Multiplicador: "
                                    .. tostring(multiplier)
    );
end;

return EconomyService;
