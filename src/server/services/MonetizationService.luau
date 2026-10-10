--!strict
local Players = game:GetService("Players");
local MarketplaceService = game:GetService("MarketplaceService");
local ReplicatedStorage = game:GetService("ReplicatedStorage");

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"));
local DataService = require(script.Parent.Parent:WaitForChild("DataService"));

local MonetizationService = {};

type PurchaseResult = {
    ok: boolean,
    message: string,
};

type UpdateLeaderstatsCallback = (player: Player) -> ();

-- Main proporciona esta función para mantener sincronizadas
-- las monedas que se muestran en la lista de jugadores.
local updateLeaderstatsCallback: UpdateLeaderstatsCallback? = nil;

local initialized = false;

local hasDoubleCoins: { [Player]: boolean } = {};
local lastUpgradeRequest: { [Player]: number } = {};
local gamePassCheckVersion: { [Player]: number } = {};

local function reject(message: string): PurchaseResult
    return {
        ok = false,
        message = message,
    };
end;

-- =========================================================
-- CREACIÓN DE REMOTOS
-- =========================================================
local function getRemoteFunction(
    parent: Instance,
    name: string
): RemoteFunction

    local existing = parent:FindFirstChild(name);

    if existing and existing:IsA("RemoteFunction") then
        return existing;
    end;

    if existing then
        existing:Destroy();
    end;

    local remote = Instance.new("RemoteFunction");
    remote.Name = name;
    remote.Parent = parent;

    return remote;
end;

local function getRemotesFolder(): Folder
    local existing = ReplicatedStorage:FindFirstChild("Remotes");

    if existing and existing:IsA("Folder") then
        return existing;
    end;

    if existing then
        existing:Destroy();
    end;

    local folder = Instance.new("Folder");
    folder.Name = "Remotes";
    folder.Parent = ReplicatedStorage;

    return folder;
end;

-- =========================================================
-- GAME PASS
-- =========================================================
local function refreshGamePassOwnership(player: Player)
    local passId = Config.GamePassDoubleCoinsId;

    if passId <= 0 then
        hasDoubleCoins[player] = false;
        return;
    end;

    local version = (gamePassCheckVersion[player] or 0) + 1;
    gamePassCheckVersion[player] = version;

    local success, ownsPass = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(
            player.UserId,
            passId
        );
    end);

    if success then
        -- Una consulta antigua no debe sobrescribir una compra reciente.
        if gamePassCheckVersion[player] == version then
            hasDoubleCoins[player] = ownsPass == true;
        end;
    else
        warn(
            "[Monetization] No se pudo comprobar el Game Pass de "
                .. player.Name
                    .. ": "
                        .. tostring(ownsPass)
        );
    end;
end;

-- =========================================================
-- COMPRA DE MEJORA CON MONEDAS
-- =========================================================
local function handleUpgradePurchase(
    player: Player,
    upgradeId: any
): PurchaseResult

    if typeof(upgradeId) ~= "string"
        or upgradeId ~= "DoublePickup" then

        return reject("Solicitud inválida.");
    end;

    -- Limita las solicitudes repetidas del cliente.
    local now = os.clock();
    local previous = lastUpgradeRequest[player] or 0;

    if now - previous < 0.75 then
        return reject("Espera antes de intentarlo otra vez.");
    end;

    lastUpgradeRequest[player] = now;

    local data = DataService.Get(player);

    if not data then
        return reject("Tus datos aún se están cargando.");
    end;

    if data.PickupMultiplier >= Config.DoublePickupMultiplier then
        return reject("Ya tienes esta mejora.");
    end;

    if data.Coins < Config.UpgradeCost then
        return reject("No tienes suficientes monedas.");
    end;

    if not DataService.SpendCoins(player, Config.UpgradeCost) then
        return reject("No se pudo completar la compra.");
    end;

    DataService.SetMultiplier(
        player,
        Config.DoublePickupMultiplier
    );

    local updateStats = updateLeaderstatsCallback;

    if updateStats then
        updateStats(player);
    end;

    -- Guardamos el cambio sin retrasar la respuesta de la interfaz.
    task.spawn(function()
        local saved = DataService.Save(player);

        if not saved then
            warn(
                "[Monetization] No se pudo guardar la mejora de "
                    .. player.Name
            );
        end;
    end);

    return {
        ok = true,
        message = "¡Mejora comprada! Ahora ganas el doble.",
    };
end;

-- =========================================================
-- DEVELOPER PRODUCTS
-- =========================================================
local function processReceipt(
    receiptInfo: any
): Enum.ProductPurchaseDecision

    local player = Players:GetPlayerByUserId(
        receiptInfo.PlayerId
    );

    if not player then
        return Enum.ProductPurchaseDecision.NotProcessedYet;
    end;

    if Config.CoinPackProductId <= 0
        or receiptInfo.ProductId ~= Config.CoinPackProductId then

        warn(
            "[Monetization] ID de Developer Product no reconocido: "
                .. tostring(receiptInfo.ProductId)
        );

        return Enum.ProductPurchaseDecision.NotProcessedYet;
    end;

    -- DataService registra el recibo y guarda la recompensa antes
    -- de permitir que Roblox marque la compra como completada.
    local granted = DataService.GrantProduct(
        player,
        tostring(receiptInfo.PurchaseId),
        Config.CoinPackAmount
    );

    if not granted then
        warn("[Monetization] No se pudo guardar el recibo.");

        return Enum.ProductPurchaseDecision.NotProcessedYet;
    end;

    local updateStats = updateLeaderstatsCallback;

    if updateStats then
        updateStats(player);
    end;

    return Enum.ProductPurchaseDecision.PurchaseGranted;
end;

-- =========================================================
-- INICIALIZACIÓN
-- =========================================================
function MonetizationService.Initialize(
    updateStats: UpdateLeaderstatsCallback
)
    if initialized then
        warn("[Monetization] El servicio ya fue inicializado.");
        return;
    end;

    initialized = true;
    updateLeaderstatsCallback = updateStats;

    local remotesFolder = getRemotesFolder();

    local purchaseUpgrade = getRemoteFunction(
        remotesFolder,
        "PurchaseUpgrade"
    );

    purchaseUpgrade.OnServerInvoke = handleUpgradePurchase;

    MarketplaceService.PromptGamePassPurchaseFinished:Connect(
        function(player, purchasedPassId, wasPurchased)
            if purchasedPassId ~= Config.GamePassDoubleCoinsId then
                return;
            end;

            if wasPurchased then
                -- Invalida consultas previas pendientes del mismo jugador.
                gamePassCheckVersion[player] =
                    (gamePassCheckVersion[player] or 0) + 1;

                hasDoubleCoins[player] = true;
            end;
        end
    );

    MarketplaceService.ProcessReceipt = processReceipt;
end;

-- Se llama cuando el jugador termina de cargar sus datos.
function MonetizationService.InitializePlayer(player: Player)
    hasDoubleCoins[player] = false;
    refreshGamePassOwnership(player);
end;

function MonetizationService.HasDoubleCoins(player: Player): boolean
    return hasDoubleCoins[player] == true;
end;

-- Limpia las referencias cuando el jugador abandona el servidor.
function MonetizationService.CleanupPlayer(player: Player)
    hasDoubleCoins[player] = nil;
    lastUpgradeRequest[player] = nil;
    gamePassCheckVersion[player] = nil;
end;

return MonetizationService;
