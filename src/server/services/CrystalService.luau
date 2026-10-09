--!strict
local Players = game:GetService("Players");
local Workspace = game:GetService("Workspace");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local Debris = game:GetService("Debris");

local Config = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
);

local RoundService = require(
    script.Parent.Parent:WaitForChild("RoundService")
);

type CrystalType = Config.CrystalType;

type IsPlayerReady = (Player) -> boolean;

type OnCrystalCollected = (Player, CrystalType) -> ();

local CrystalService = {};

local roundSpawned = false;

-- =========================================================
-- IDENTIFICACIÓN DEL PERSONAJE
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

local function getPlayerFromHit(
    hit: BasePart
): (Player?, Humanoid?, BasePart?)

    local character = hit:FindFirstAncestorOfClass("Model");

    if not character then
        return nil, nil, nil;
    end;

    local player = Players:GetPlayerFromCharacter(character);

    if not player then
        return nil, nil, nil;
    end;

    local humanoid = character:FindFirstChildOfClass("Humanoid");
    local rootPart = character:FindFirstChild("HumanoidRootPart");

    if not humanoid or humanoid.Health <= 0 then
        return nil, nil, nil;
    end;

    if not rootPart or not rootPart:IsA("BasePart") then
        return nil, nil, nil;
    end;

    return player, humanoid, rootPart;
end;

-- =========================================================
-- SONIDO
-- =========================================================
local function playPickupSound(
    position: Vector3,
    crystalType: CrystalType
)
    local attachment = Instance.new("Attachment");
    attachment.Name = "PickupSoundAttachment";
    attachment.Position = position;
    attachment.Parent = Workspace.Terrain;

    local sound = Instance.new("Sound");
    sound.Name = "PickupSound";

    if crystalType == "Red" then
        sound.SoundId = Config.NegativePickupSoundId;
    else
        sound.SoundId = Config.PositivePickupSoundId;
    end;

    sound.Volume = Config.PickupSoundVolume;
    sound.RollOffMaxDistance = Config.PickupSoundMaxDistance;
    sound.Parent = attachment;

    -- El sonido normal se limpia al terminar; este plazo es
    -- una protección por si el asset no llega a reproducirse.
    sound.Ended:Connect(function()
        attachment:Destroy();
    end);

    Debris:AddItem(attachment, 10);

    sound:Play();
end;

-- =========================================================
-- GENERACIÓN DE POSICIONES
-- =========================================================
local function generatePositions(): { Vector3 }
    local positions: { Vector3 } = {};

    for index = 1, Config.TotalPickups do
        local acceptedPosition: Vector3? = nil;
        local attempts = 0;

        while attempts < Config.CrystalMaxPositionAttempts
            and acceptedPosition == nil do

            attempts += 1;

            local x = math.random(
                Config.CrystalMinX,
                Config.CrystalMaxX
            );

            local z = math.random(
                Config.CrystalMinZ,
                Config.CrystalMaxZ
            );

            local candidate = Vector3.new(
                x,
                Config.CrystalGroundY,
                z
            );

            local isValid = true;

            for _, existingPosition in positions do
                if (candidate - existingPosition).Magnitude < Config.CrystalMinDistance then

                    isValid = false;
                    break;
                end;
            end;

            if isValid then
                acceptedPosition = candidate;
            end;
        end;

        if acceptedPosition then
            table.insert(positions, acceptedPosition);
        else
            warn(
                "[CrystalService] No se encontró una posición "
                    .. "válida para el cristal "
                        .. tostring(index)
            );
        end;
    end;

    return positions;
end;

-- =========================================================
-- ASIGNACIÓN DE TIPOS
-- =========================================================
local function randomCrystalType(): CrystalType
    local roll = math.random(1, 3);

    if roll == 1 then
        return "Blue";
    elseif roll == 2 then
        return "Yellow";
    else
        return "Red";
    end;
end;

local function determineTypes(
    totalPositions: number
): ({ CrystalType }, number, number)

    local types: { CrystalType } = {};

    local totalBlue = 0;
    local totalYellow = 0;

    for index = 1, totalPositions do
        local crystalType: CrystalType;

        -- Garantizamos que exista al menos un objetivo azul.
        if index == totalPositions and totalBlue == 0 then
            crystalType = "Blue";
        else
            crystalType = randomCrystalType();
        end;

        table.insert(types, crystalType);

        if crystalType == "Blue" then
            totalBlue += 1;
        elseif crystalType == "Yellow" then
            totalYellow += 1;
        end;
    end;

    return types, totalBlue, totalYellow;
end;

-- =========================================================
-- CREACIÓN DE UN CRISTAL
-- =========================================================
local function createCrystal(
    folder: Folder,
    position: Vector3,
    crystalType: CrystalType,
    isPlayerReady: IsPlayerReady,
    onCollected: OnCrystalCollected
)
    local model = Instance.new("Model");
    model.Name = "Crystal_" .. crystalType;

    local orb = Instance.new("Part");
    orb.Name = "Crystal";
    orb.Shape = Enum.PartType.Block;
    orb.Size = Vector3.new(4, 4, 4);
    orb.Position = position;

    -- Permanece fijo hasta que se recoge correctamente.
    orb.Anchored = true;
    orb.CanCollide = true;
    orb.CanTouch = true;
    orb.CanQuery = true;

    orb.Material = Enum.Material.Neon;

    if crystalType == "Blue" then
        orb.Color = Color3.fromRGB(70, 200, 255);
    elseif crystalType == "Yellow" then
        orb.Color = Color3.fromRGB(255, 220, 50);
    else
        orb.Color = Color3.fromRGB(255, 70, 70);
    end;

    orb.CustomPhysicalProperties = PhysicalProperties.new(
        Config.CrystalDensity,
        Config.CrystalFriction,
        Config.CrystalElasticity
    );

    orb.Parent = model;

    -- Solo los azules requieren aterrizar encima.
    local sensor: Part? = nil;

    if crystalType == "Blue" then
        local landingSensor = Instance.new("Part");
        landingSensor.Name = "CrystalLandingSensor";
        landingSensor.Size = Vector3.new(1.6, 0.25, 1.6);

        landingSensor.Position =
            position + Vector3.new(0, 2, 0);

        landingSensor.Anchored = true;
        landingSensor.CanCollide = false;
        landingSensor.CanTouch = true;
        landingSensor.CanQuery = false;
        landingSensor.Transparency = Config.CrystalSensorTransparency;

        landingSensor.Parent = model;
        sensor = landingSensor;
    end;

    model.Parent = folder;

    local claimed = false;

    local function collectCrystal(player: Player)
        if claimed or not RoundService.IsActive() then
            return;
        end;

        if not isPlayerReady(player) then
            return;
        end;

        claimed = true;

        if sensor and sensor.Parent then
            sensor:Destroy();
        end;

        playPickupSound(orb.Position, crystalType);

        -- Main conecta la recolección con la ronda y la economía.
        onCollected(player, crystalType);

        -- El orbe solo pasa a ser dinámico después de recogerlo.
        orb.Anchored = false;
        orb.CanCollide = false;
        orb:SetNetworkOwner(nil);

        local desiredVelocity = Vector3.new(
            0,
            Config.CrystalBounceVelocity,
            0
        );

        orb:ApplyImpulse(
            desiredVelocity * orb.AssemblyMass
        );

        -- No respawn: el cristal desaparece definitivamente
        -- durante esta ronda.
        task.delay(Config.CrystalDestroyDelay, function()
            if model.Parent then
                model:Destroy();
            end;
        end);
    end;

    if crystalType == "Blue" and sensor then
        sensor.Touched:Connect(function(hit: BasePart)
            if claimed or not RoundService.IsActive() then
                return;
            end;

            local player, humanoid, rootPart =
                getPlayerFromHit(hit);

            if not player or not humanoid or not rootPart then
                return;
            end;

            if not isFootPart(hit) then
                return;
            end;

            -- No recogerlo cuando el personaje todavía está subiendo.
            if rootPart.AssemblyLinearVelocity.Y > 0 then
                return;
            end;

            local horizontalOffset = Vector3.new(
                rootPart.Position.X - orb.Position.X,
                0,
                rootPart.Position.Z - orb.Position.Z
            );

            if horizontalOffset.Magnitude > 2 then
                return;
            end;

            collectCrystal(player);
        end);
    else
        -- Amarillos y rojos conservan la recolección por contacto.
        orb.Touched:Connect(function(hit: BasePart)
            if claimed or not RoundService.IsActive() then
                return;
            end;

            local player = getPlayerFromHit(hit);

            if not player then
                return;
            end;

            collectCrystal(player);
        end);
    end;
end;

-- =========================================================
-- INICIAR LA GENERACIÓN DE CRISTALES
-- =========================================================
function CrystalService.SpawnRound(
    isPlayerReady: IsPlayerReady,
    onCollected: OnCrystalCollected
): (number, number)

    if roundSpawned then
        warn("[CrystalService] Los cristales ya fueron generados.");
        return 0, 0;
    end;

    roundSpawned = true;

    local oldFolder = Workspace:FindFirstChild(
        "CrystalQuestCollectibles"
    );

    if oldFolder then
        oldFolder:Destroy();
    end;

    local folder = Instance.new("Folder");
    folder.Name = "CrystalQuestCollectibles";
    folder.Parent = Workspace;

    local positions = generatePositions();

    local types, totalBlue, totalYellow =
        determineTypes(#positions);

    for index, position in positions do
        createCrystal(
            folder,
            position,
            types[index],
            isPlayerReady,
            onCollected
        );
    end;

    print(
        "[CrystalService] Cristales creados: "
            .. tostring(#positions)
                .. " | Azules: "
                    .. tostring(totalBlue)
                        .. " | Amarillos: "
                            .. tostring(totalYellow)
    );

    return totalBlue, totalYellow;
end;

return CrystalService;
