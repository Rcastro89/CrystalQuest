--!strict
local Players = game:GetService("Players");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local MarketplaceService = game:GetService("MarketplaceService");
local Workspace = game:GetService("Workspace");

local Config = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
);

type CrystalType = Config.CrystalType;
local DataService = require(script.Parent.DataService);
local RoundService = require(script.Parent.RoundService);

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

-- =========================================================
-- SONIDO DE RECOLECCIÓN
-- =========================================================
local function playPickupSound(
    position: Vector3,
    isPositive: boolean
)
    local attachment = Instance.new("Attachment");
    attachment.Name = "PickupSoundAttachment";
    attachment.Position = position;
    attachment.Parent = Workspace.Terrain;

    local sound = Instance.new("Sound");
    sound.Name = "PickupSound";

    if isPositive then
        sound.SoundId = Config.PositivePickupSoundId;
    else
        sound.SoundId = Config.NegativePickupSoundId;
    end;

    sound.Volume = Config.PickupSoundVolume;
    sound.RollOffMaxDistance = Config.PickupSoundMaxDistance;
    sound.Parent = attachment;

    sound.Ended:Connect(function()
        attachment:Destroy();
    end);

    sound:Play();
end;

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
-- 6. GENERACIÓN Y RECOLECCIÓN DE CRISTALES
-- =========================================================
local function isFootPart(part: BasePart): boolean
    local name = part.Name;

    return name == "LeftFoot"
        or name == "RightFoot"
        or name == "LeftLowerLeg"
        or name == "RightLowerLeg"
        or name == "Left Leg"
        or name == "Right Leg";
end;

local pickupPositions: { Vector3 } = {};

local TOTAL_ITEMS: number = Config.TotalPickups; -- Número total de cristales a generar
local MIN_DISTANCE: number = 7; -- Distancia mínima entre monedas/objetos en studs
local MAX_ATTEMPTS: number = 100; -- Límite para evitar bucles infinitos si el área se llena
local totalBlueCrystals: number = 0;
local totalYellowCrystals: number = 0;

for i = 1, TOTAL_ITEMS do
    local newPos: Vector3;
    local isValid: boolean = false;
    local attempts: number = 0;

    repeat
        attempts += 1;
        local x = math.random(-30, 30);
        local z = math.random(-30, 30);
        newPos = Vector3.new(x, 2, z);

        -- Asumimos que es válida hasta que se demuestre lo contrario
        isValid = true;

        for _, existingPos in ipairs(pickupPositions) do
            -- (v1 - v2).Magnitude calcula la distancia en studs entre dos vectores
            if (newPos - existingPos).Magnitude < MIN_DISTANCE then
                isValid = false;
                break; -- Está muy cerca de una existente, descartar y reintentar
            end;
        end;
    until isValid or attempts >= MAX_ATTEMPTS;

    if isValid then
        table.insert(pickupPositions, newPos);
    else
        warn("No se encontró una posición libre tras " .. MAX_ATTEMPTS .. " intentos.");
    end;
end;

local function validRecolet(orb: Part, player: Player, crystalType: CrystalType)
    -- =================================================
    -- RECOLECCIÓN VÁLIDA
    -- =================================================
    RoundService.RegisterCrystalCollected(crystalType);
    -- Sonido y recompensa.
    playPickupSound(orb.Position, crystalType ~= "Red");
    awardCoins(player, crystalType);

    -- =================================================
    -- REBOTE DEL ORBE
    -- =================================================

    -- A partir de aquí el orbe deja de ser estático
    -- y pasa a formar parte de la simulación física.
    orb.Anchored = false;

    -- El servidor mantiene la autoridad física.
    orb:SetNetworkOwner(nil);

    -- Evitamos que el jugador pueda empujarlo lateralmente
    -- mientras dura la pequeña animación de rebote.
    orb.CanCollide = false;

    local desiredVelocity = Vector3.new(
        0,
        Config.CrystalBounceVelocity,
        0
    );

    local impulse = desiredVelocity * orb.AssemblyMass;

    orb:ApplyImpulse(impulse);

    -- =================================================
    -- ELIMINACIÓN Y RESPAWN
    -- =================================================
    task.delay(Config.CrystalDestroyDelay, function()
        if orb.Parent then
            orb:Destroy();
        end;
    end);
end;

local function canContinue(claimed: boolean, hit: BasePart): (boolean, Player?, Humanoid?, BasePart?)
    if claimed then
        return false;
    end;

    if not RoundService.IsActive() then
        return false;
    end;

    local character = hit:FindFirstAncestorOfClass("Model");

    if not character then
        return false;
    end;

    local player = Players:GetPlayerFromCharacter(character);

    if not player or not DataService.Get(player) then
        return false;
    end;

    local humanoid = character:FindFirstChildOfClass("Humanoid");
    local rootPart = character:FindFirstChild("HumanoidRootPart");

    if not humanoid or humanoid.Health <= 0 then
        return false;
    end;

    if not rootPart or not rootPart:IsA("BasePart") then
        return false;
    end;

    return true, player, humanoid, rootPart;
end;

local createPickup: (Vector3, boolean?) -> ();

createPickup = function(
    position: Vector3,
    forceBlue: boolean?
)
    local crystalType: CrystalType

    if forceBlue == true then
        crystalType = "Blue"
    else
        local availableTypes: {CrystalType} = {
            "Blue",
            "Yellow",
            "Red",
        }

        local randomIndex = math.random(1, #availableTypes)
        crystalType = availableTypes[randomIndex]
    end

    if crystalType == "Blue" then
        totalBlueCrystals += 1
    elseif crystalType == "Yellow" then
        totalYellowCrystals += 1
    end

    -- =====================================================
    -- ORBE FÍSICO
    -- =====================================================
    local orb = Instance.new("Part");
    orb.Name = "Crystal";
    orb.Shape = Enum.PartType.Block;
    orb.Size = Vector3.new(4, 4, 4);
    orb.Position = position;

    -- El orbe es sólido, pero permanece fijo hasta que
    -- un jugador lo recoge correctamente.
    orb.Anchored = true;
    orb.CanCollide = true;
    orb.CanTouch = true;
    orb.CanQuery = true;

    orb.Material = Enum.Material.Neon;

    orb.Color =
        if crystalType == "Blue" then
            Color3.fromRGB(70, 200, 255)
        elseif crystalType == "Yellow" then
            Color3.fromRGB(255, 220, 50)
        else
            Color3.fromRGB(255, 70, 70);

    orb.CustomPhysicalProperties = PhysicalProperties.new(
        Config.CrystalDensity,
        Config.CrystalFriction,
        Config.CrystalElasticity
    );

    orb.Parent = Workspace;

    local claimed = false;

    if crystalType == "Blue" then
        -- =====================================================
        -- SENSOR INVISIBLE
        -- =====================================================
        local sensor = Instance.new("Part");
        sensor.Name = "CrystalLandingSensor";

        -- Un poco más pequeño que el cristal para exigir
        -- que el jugador caiga aproximadamente sobre su centro.
        sensor.Size = Vector3.new(1.6, 0.25, 1.6);

        -- El sensor queda justo encima del cristal.
        sensor.Position = position + Vector3.new(0, 2, 0);

        sensor.Anchored = true;
        sensor.CanCollide = false;
        sensor.CanTouch = true;
        sensor.CanQuery = false;

        -- El jugador no debe poder ver este objeto.
        --sensor.Transparency = 1;
        sensor.Parent = Workspace;

        -- =====================================================
        -- DETECCIÓN DEL ATERRIZAJE
        -- =====================================================
        sensor.Touched:Connect(function(hit: BasePart)
            local success, player, humanoid, rootPart = canContinue(claimed, hit);

            if success and player and humanoid and rootPart then

                local foot = isFootPart(hit);
                print(foot and "Tocó un pie" or "Tocó otra parte del cuerpo");
                if not foot then
                    return;
                end;

                -- El sensor no tiene colisión física, así que aquí
                -- podemos comprobar la velocidad sin que el contacto
                -- con el sensor haya alterado la física del jugador.
                local verticalVelocity = rootPart.AssemblyLinearVelocity.Y;

                if verticalVelocity > 0 then
                    return;
                end;

                -- Comprobamos que el jugador esté horizontalmente
                -- encima del cristal.
                local horizontalOffset = Vector3.new(
                    rootPart.Position.X - orb.Position.X,
                    0,
                    rootPart.Position.Z - orb.Position.Z
                );

                if horizontalOffset.Magnitude > 2 then
                    return;
                end;

                claimed = true;
                sensor:Destroy();
                validRecolet(orb, player, crystalType);
            end;
        end);
    else
        orb.Touched:Connect(function(hit: BasePart)
            local success, player, humanoid, rootPart = canContinue(claimed, hit);

            if success and player and humanoid and rootPart then
                claimed = true;
                validRecolet(orb, player, crystalType);
            end;
        end);
    end;
end;

for index, position in pickupPositions do
    -- Si llegamos al último cristal y todavía no existe
    -- ningún azul, forzamos ese último cristal a ser azul.
    local forceBlue  = index == #pickupPositions and totalBlueCrystals == 0;

    createPickup(position, forceBlue );
end;

RoundService.Start(totalBlueCrystals, totalYellowCrystals);

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
