--!strict
local Players = game:GetService("Players");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local MarketplaceService = game:GetService("MarketplaceService");
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"));
local DataService = require(script.Parent.DataService);
local RoundService = require(script.Parent.RoundService);
local services = script.Parent:WaitForChild("services");
local CrystalService = require(services:WaitForChild("CrystalService"));
local StartLineService = require(services:WaitForChild("StartLineService"));

type CrystalType = Config.CrystalType;

type PurchaseResult = {
    ok: boolean,
    message: string,
};

-- =========================================================
-- 1. CREACIÓN DE REMOTOS
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

local existingFolder = ReplicatedStorage:FindFirstChild("Remotes");
local remotesFolder: Folder;

if existingFolder and existingFolder:IsA("Folder") then
    remotesFolder = existingFolder;
else
    if existingFolder then
        existingFolder:Destroy();
    end;

    local folder = Instance.new("Folder");
    folder.Name = "Remotes";
    folder.Parent = ReplicatedStorage;

    remotesFolder = folder;
end;

local purchaseUpgrade = getRemoteFunction(
    remotesFolder,
    "PurchaseUpgrade"
);

-- =========================================================
-- 2. ESTADO DE SESIÓN
-- =========================================================
local setupStarted: { [Player]: boolean } = {};
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

-- =========================================================
-- 4. GAME PASS
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
        -- Evita que una consulta antigua sobrescriba una compra reciente.
        if gamePassCheckVersion[player] == version then
            hasDoubleCoins[player] = ownsPass;
        end;
    else
        warn(
            "No se pudo comprobar el Game Pass de "
                .. player.Name
                    .. ": "
                        .. tostring(ownsPass)
        );
    end;
end;

MarketplaceService.PromptGamePassPurchaseFinished:Connect(
    function(player, purchasedPassId, wasPurchased)
        if purchasedPassId ~= Config.GamePassDoubleCoinsId then
            return;
        end;

        if wasPurchased then
            gamePassCheckVersion[player] =
                (gamePassCheckVersion[player] or 0) + 1;

            hasDoubleCoins[player] = true;
        end;
    end
);

-- =========================================================
-- 5. RECOMPENSAS
-- =========================================================
local function awardCoins(player: Player, crystalType: CrystalType)
    local data = DataService.Get(player);

    if not data then
        return;
    end;

    local multiplier = data.PickupMultiplier;

    if hasDoubleCoins[player] then
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
-- 7. COMPRA DE MEJORA CON MONEDAS
-- =========================================================
purchaseUpgrade.OnServerInvoke = function(
    player: Player,
    upgradeId: any
): PurchaseResult

    if typeof(upgradeId) ~= "string"
        or upgradeId ~= "DoublePickup" then

        return reject("Solicitud inválida.");
    end;

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

    updateLeaderstats(player);

    -- Guardamos la compra sin bloquear la respuesta de la interfaz.
    task.spawn(function()
        local saved = DataService.Save(player);

        if not saved then
            warn("No se pudo guardar la mejora de " .. player.Name);
        end;
    end);

    return {
        ok = true,
        message = "¡Mejora comprada! Ahora ganas el doble.",
    };
end;

-- =========================================================
-- 8. DEVELOPER PRODUCTS
-- =========================================================
MarketplaceService.ProcessReceipt = function(
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

        warn("ID de Developer Product no reconocido.");

        return Enum.ProductPurchaseDecision.NotProcessedYet;
    end;

    local granted = DataService.GrantProduct(
        player,
        tostring(receiptInfo.PurchaseId),
        Config.CoinPackAmount
    );

    if not granted then
        warn("No se pudo guardar el recibo de compra.");

        return Enum.ProductPurchaseDecision.NotProcessedYet;
    end;

    updateLeaderstats(player);

    return Enum.ProductPurchaseDecision.PurchaseGranted;
end;

-- =========================================================
-- 9. CICLO DE VIDA DEL JUGADOR
-- =========================================================
local function onPlayerAdded(player: Player)
    if setupStarted[player] then
        return;
    end;

    setupStarted[player] = true;
    hasDoubleCoins[player] = false;

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

    refreshGamePassOwnership(player);
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
    hasDoubleCoins[player] = nil;
    lastUpgradeRequest[player] = nil;
    gamePassCheckVersion[player] = nil;
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
