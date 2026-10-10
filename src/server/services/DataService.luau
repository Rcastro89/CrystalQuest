--!strict
local DataStoreService = game:GetService("DataStoreService");
local ReplicatedStorage = game:GetService("ReplicatedStorage");

local Config = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
);

export type PlayerData = {
    SchemaVersion: number,
    Coins: number,
    PickupMultiplier: number,
    ProcessedReceipts: { [string]: boolean },
};

local DataService = {};

local store = DataStoreService:GetDataStore(Config.DataStoreName);

local sessions: { [Player]: PlayerData } = {};
local saving: { [Player]: boolean } = {};

local MAX_ATTEMPTS = 3;

local function keyFor(player: Player): string
    return "Player_" .. tostring(player.UserId);
end;

local function defaultData(): PlayerData
    return {
        SchemaVersion = 1,
        Coins = 0,
        PickupMultiplier = 1,
        ProcessedReceipts = {},
    };
end;

local function requestWithRetries(
    callback: () -> any
): (boolean, any)

    for attempt = 1, MAX_ATTEMPTS do
        local success, result = pcall(callback);

        if success then
            return true, result;
        end;

        warn(
            "Error de DataStore, intento "
                .. tostring(attempt)
                    .. ": "
                        .. tostring(result)
        );

        if attempt < MAX_ATTEMPTS then
            -- Backoff exponencial con variación para no repetir
            -- todas las peticiones al mismo tiempo.
            local delaySeconds = math.min(
                2 ^ (attempt - 1) + math.random(),
                8
            );

            task.wait(delaySeconds);
        end;
    end;

    return false, nil;
end;

local function sanitize(raw: any): PlayerData
    local data = defaultData();

    if type(raw) ~= "table" then
        return data;
    end;

    if type(raw.Coins) == "number"
        and raw.Coins >= 0 then

        data.Coins = math.floor(raw.Coins);
    end;

    if type(raw.PickupMultiplier) == "number"
        and raw.PickupMultiplier >= 1
        and raw.PickupMultiplier <= Config.DoublePickupMultiplier then

        data.PickupMultiplier = raw.PickupMultiplier;
    end;

    if type(raw.ProcessedReceipts) == "table" then
        for receiptId, processed in raw.ProcessedReceipts do
            if type(receiptId) == "string"
                and processed == true then

                data.ProcessedReceipts[receiptId] = true;
            end;
        end;
    end;

    return data;
end;

function DataService.Load(player: Player): boolean
    if sessions[player] then
        return true;
    end;

    local success, raw = requestWithRetries(function()
        return store:GetAsync(keyFor(player));
    end);

    if not success then
        return false;
    end;

    sessions[player] = sanitize(raw);

    return true;
end;

function DataService.Get(player: Player): PlayerData?
    return sessions[player];
end;

function DataService.AddCoins(
    player: Player,
    amount: number
): boolean

    local data = sessions[player];

    if not data then
        return false;
    end;

    data.Coins += math.floor(amount);

    return true;
end;

function DataService.SpendCoins(
    player: Player,
    amount: number
): boolean

    local data = sessions[player];

    if not data or amount <= 0 then
        return false;
    end;

    local cost = math.floor(amount);

    if data.Coins < cost then
        return false;
    end;

    data.Coins -= cost;

    return true;
end;

function DataService.SetMultiplier(
    player: Player,
    multiplier: number
)
    local data = sessions[player];

    if not data then
        return;
    end;

    if multiplier < 1
        or multiplier > Config.DoublePickupMultiplier then

        return;
    end;

    data.PickupMultiplier = multiplier;
end;

local function cloneData(data: PlayerData): PlayerData
    local snapshot: PlayerData = {
        SchemaVersion = data.SchemaVersion,
        Coins = data.Coins,
        PickupMultiplier = data.PickupMultiplier,
        ProcessedReceipts = {},
    };

    for receiptId, processed in data.ProcessedReceipts do
        snapshot.ProcessedReceipts[receiptId] = processed;
    end;

    return snapshot;
end;

function DataService.Save(player: Player): boolean
    -- Serializa los guardados de este jugador dentro del servidor.
    while saving[player] do
        task.wait(0.05);
    end;

    local data = sessions[player];

    if not data then
        return false;
    end;

    saving[player] = true;

    local snapshot = cloneData(data);

    local success = requestWithRetries(function()
        return store:SetAsync(keyFor(player), snapshot);
    end);

    saving[player] = nil;

    return success;
end;

function DataService.GrantProduct(
    player: Player,
    purchaseId: string,
    amount: number
): boolean

    local data = sessions[player];

    if not data or amount <= 0 then
        return false;
    end;

    -- No aplicar dos veces un recibo ya registrado en el perfil.
    if not data.ProcessedReceipts[purchaseId] then
        data.Coins += math.floor(amount);
        data.ProcessedReceipts[purchaseId] = true;
    end;

    -- Confirmar el recibo solamente después de guardar correctamente.
    return DataService.Save(player);
end;

function DataService.Release(player: Player)
    sessions[player] = nil;
    saving[player] = nil;
end;

return DataService;
