--!strict
local Config = {
    -- Sistema de recolección
    BasePickupReward = 5,
    SecondsPerBlueCrystal = 5,
    SecondsPerYellowCrystal = 2,
    TotalPickups = 10,
    RedeemPenalty = 10,
    -- Mejora comprada con monedas
    UpgradeCost = 25,
    DoublePickupMultiplier = 2,
    -- Sonidos de los cristales
    PositivePickupSoundId = "rbxassetid://120891770644830",
    NegativePickupSoundId = "rbxassetid://116107826564721",
    PickupSoundVolume = 0.8,
    PickupSoundMaxDistance = 35,
    -- Física de los cristales
    CrystalDensity = 0.5,
    CrystalFriction = 0.2,
    CrystalElasticity = 0.8,
    CrystalBounceVelocity = 18,
    CrystalDestroyDelay = 0.35,
    -- Monetización: los IDs se configurarán más adelante.
    GamePassDoubleCoinsId = 0,
    CoinPackProductId = 0,
    CoinPackAmount = 100,
    -- Persistencia de datos
    DataStoreName = "CrystalQuest_PlayerData_v1",
    AutosaveSeconds = 60,
};

return Config;
