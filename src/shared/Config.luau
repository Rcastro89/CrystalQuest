--!strict
export type CrystalType = "Blue" | "Yellow" | "Red";

local Config = {
    -- Sistema de recolección
    BluePickupReward = 5,
    YellowPickupReward = 2,
    SecondsPerBlueCrystal = 5,
    SecondsPerYellowCrystal = 2,
    TotalPickups = 10,
    RedeemPenalty = 2,
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
    -- Línea de salida
    StartLineZ = -35,
    StartLineWidth = 70,
    StartLineTriggerHeight = 10,
    StartLineTriggerDepth = 2,
    -- Área donde se generan los cristales
    CrystalMinX = -30,
    CrystalMaxX = 30,
    CrystalMinZ = -28,
    CrystalMaxZ = 30,
    CrystalGroundY = 2,
    -- Separación entre cristales
    CrystalMinDistance = 7,
    CrystalMaxPositionAttempts = 100,
    -- Sensor visible durante las pruebas.
    -- En la versión final podemos establecerlo en 1.
    CrystalSensorTransparency = 0.5,
    -- Monstruo decorativo junto a los cristales
    MonsterAssetId = 11545181738,
    MonsterSizeScale = 1.0,
    MonsterMinDistanceFromOthers = 7,
    -- Límites del mapa (paredes cerradas del corral)
    MapBoundsMargin = 2,
    MapBoundsWallThickness = 1,
    MapBoundsWallHeight = 15,
    MapBoundsWallColor = Color3.fromRGB(80, 90, 120),
    MapBoundsWallMaterial = Enum.Material.Concrete,
};

return Config;
