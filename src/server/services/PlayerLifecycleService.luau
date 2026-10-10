--!strict
local Players = game:GetService("Players");
local ReplicatedStorage = game:GetService("ReplicatedStorage");

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"));
local DataService = require(script.Parent:WaitForChild("DataService"));
local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"));

local PlayerLifecycleService = {};

local initialized = false;
local setupStarted: { [Player]: boolean } = {};

-- =========================================================
-- LEADERSTATS
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

function PlayerLifecycleService.UpdateLeaderstats(player: Player)
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
-- ENTRADA DEL JUGADOR
-- =========================================================
local function onPlayerAdded(player: Player)
    if setupStarted[player] then
        return;
    end;

    setupStarted[player] = true;

    local loaded = DataService.Load(player);

    if not loaded then
        warn(
            "[PlayerLifecycle] No se pudieron cargar los datos de "
                .. player.Name
        );

        player:Kick(
            "No pudimos cargar tus datos. Vuelve a intentarlo."
        );

        return;
    end;

    -- El jugador pudo desconectarse mientras cargábamos sus datos.
    if player.Parent ~= Players then
        DataService.Release(player);
        setupStarted[player] = nil;
        return;
    end;

    createLeaderstats(player);

    -- Solo comprobamos el Game Pass después de cargar el perfil.
    MonetizationService.InitializePlayer(player);

    print(
        "[PlayerLifecycle] Jugador preparado: "
            .. player.Name
    );
end;

-- =========================================================
-- SALIDA DEL JUGADOR
-- =========================================================
local function onPlayerRemoving(player: Player)
    if DataService.Get(player) then
        local saved = DataService.Save(player);

        if not saved then
            warn(
                "[PlayerLifecycle] Fallo al guardar los datos de "
                    .. player.Name
            );
        end;

        DataService.Release(player);
    end;

    setupStarted[player] = nil;

    MonetizationService.CleanupPlayer(player);
end;

-- =========================================================
-- GUARDADO AUTOMÁTICO
-- =========================================================
local function startAutosave()
    task.spawn(function()
        while true do
            task.wait(Config.AutosaveSeconds);

            for _, player in Players:GetPlayers() do
                if DataService.Get(player) then
                    local saved = DataService.Save(player);

                    if not saved then
                        warn(
                            "[PlayerLifecycle] Fallo en autosave de "
                                .. player.Name
                        );
                    end;

                    -- Evita lanzar todas las escrituras consecutivamente.
                    task.wait(0.1);
                end;
            end;
        end;
    end);
end;

-- =========================================================
-- CIERRE DEL SERVIDOR
-- =========================================================
local function savePlayersOnShutdown()
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
                            "[PlayerLifecycle] Fallo al guardar "
                                .. "durante el cierre: "
                                    .. playerToSave.Name
                        );
                    end;

                    pending -= 1;
                end);
            end;
        end;

        -- Espera a que terminen las tareas de guardado.
        while pending > 0 do
            task.wait(0.1);
        end;
    end);
end;

-- =========================================================
-- INICIALIZACIÓN DEL SERVICIO
-- =========================================================
function PlayerLifecycleService.Initialize()
    if initialized then
        warn("[PlayerLifecycle] El servicio ya fue inicializado.");
        return;
    end;

    initialized = true;

    Players.PlayerAdded:Connect(function(player)
        task.spawn(onPlayerAdded, player);
    end);

    Players.PlayerRemoving:Connect(onPlayerRemoving);

    -- Si ya había jugadores al inicializar el servicio,
    -- también debemos procesarlos.
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayerAdded, player);
    end;

    startAutosave();
    savePlayersOnShutdown();

    print("[PlayerLifecycle] Servicio inicializado.");
end;

return PlayerLifecycleService;
