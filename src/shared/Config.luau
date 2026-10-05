--!strict

local Config = {
    -- Sistema de recolección
    BasePickupReward = 5,
    PickupRespawnSeconds = 4,

    -- Mejora comprada con monedas
    UpgradeCost = 25,
    DoublePickupMultiplier = 2,

    -- Monetización: los IDs se configurarán más adelante.
    GamePassDoubleCoinsId = 0,
    CoinPackProductId = 0,
    CoinPackAmount = 100,

    -- Persistencia de datos
    DataStoreName = "CrystalQuest_PlayerData_v1",
    AutosaveSeconds = 60,
}

return Config