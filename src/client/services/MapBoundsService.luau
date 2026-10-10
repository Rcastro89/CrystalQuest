--!strict
local Workspace = game:GetService("Workspace");
local ReplicatedStorage = game:GetService("ReplicatedStorage");

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"));

local MapBoundsService = {};

local initialized = false;
local southWallClosed = false;
local cachedBounds: ComputedBounds? = nil;
local cachedFolder: Folder? = nil;

type WallOrientation = "North" | "South" | "East" | "West";

type ComputedBounds = {
    minX: number,
    maxX: number,
    minZ: number,
    maxZ: number,
    centerX: number,
    centerZ: number,
    width: number,
    depth: number,
};

local function computeBounds(): ComputedBounds
    local margin = Config.MapBoundsMargin or 2;

    local minX = math.min(
        (Config.CrystalMinX or 0) - margin,
        -((Config.StartLineWidth or 0) / 2) - margin
    );

    local maxX = math.max(
        (Config.CrystalMaxX or 0) + margin,
        ((Config.StartLineWidth or 0) / 2) + margin
    );

    local minZ = math.min(
        (Config.CrystalMinZ or 0) - margin,
        (Config.StartLineZ or 0) - margin
    );

    local maxZ = math.max(
        (Config.CrystalMaxZ or 0) + margin,
        (Config.StartLineZ or 0) + margin
    );

    local width = maxX - minX;
    local depth = maxZ - minZ;
    local centerX = (minX + maxX) / 2;
    local centerZ = (minZ + maxZ) / 2;

    return {
        minX = minX,
        maxX = maxX,
        minZ = minZ,
        maxZ = maxZ,
        centerX = centerX,
        centerZ = centerZ,
        width = width,
        depth = depth,
    };
end;

local function validateBounds(bounds: ComputedBounds): (boolean, string?)
    if bounds.width <= 0 then
        return false, "Ancho calculado no válido (X max <= X min)";
    end;

    if bounds.depth <= 0 then
        return false, "Profundidad calculada no válida (Z max <= Z min)";
    end;

    if bounds.width < 10 or bounds.depth < 10 then
        return false, "Área calculada demasiado pequeña (mínimo 10x10 studs)";
    end;

    if (Config.MapBoundsWallThickness or 1) <= 0 then
        return false, "Grosor de pared no válido";
    end;

    if (Config.MapBoundsWallHeight or 0) <= 0 then
        return false, "Altura de pared no válida";
    end;

    return true, nil;
end;

local function makeWall(
    bounds: ComputedBounds,
    orientation: string
): Part
    local thickness = Config.MapBoundsWallThickness or 1;
    local height = Config.MapBoundsWallHeight or 15;
    local halfHeight = height / 2;
    local halfThick = thickness / 2;

    local size: Vector3;
    local position: Vector3;

    if orientation == "North" then
        size = Vector3.new(
            bounds.width + thickness * 2,
            height,
            thickness
        );
        position = Vector3.new(
            bounds.centerX,
            halfHeight,
            bounds.maxZ + halfThick
        );

    elseif orientation == "South" then
        size = Vector3.new(
            bounds.width + thickness * 2,
            height,
            thickness
        );
        position = Vector3.new(
            bounds.centerX,
            halfHeight,
            bounds.minZ - halfThick
        );

    elseif orientation == "East" then
        size = Vector3.new(
            thickness,
            height,
            bounds.depth
        );
        position = Vector3.new(
            bounds.maxX + halfThick,
            halfHeight,
            bounds.centerZ
        );

    else -- West
        size = Vector3.new(
            thickness,
            height,
            bounds.depth
        );
        position = Vector3.new(
            bounds.minX - halfThick,
            halfHeight,
            bounds.centerZ
        );
    end;

    local wall = Instance.new("Part");
    wall.Name = "MapBoundary_" .. orientation;
    wall.Size = size;
    wall.Position = position;
    wall.Anchored = true;
    wall.CanCollide = true;
    wall.CanTouch = false;
    wall.CanQuery = true;
    wall.Material = Config.MapBoundsWallMaterial or Enum.Material.Concrete;
    wall.Color = Config.MapBoundsWallColor or Color3.fromRGB(80, 90, 120);

    return wall;
end;

function MapBoundsService.Initialize(): boolean
    if initialized then
        warn("[MapBounds] El servicio ya fue inicializado.");
        return false;
    end;

    initialized = true;

    local oldFolder = Workspace:FindFirstChild("CrystalQuestBounds");
    if oldFolder then
        oldFolder:Destroy();
    end;

    local bounds = computeBounds();

    local ok, err = validateBounds(bounds);
    if not ok then
        warn("[MapBounds] Validación fallida: " .. tostring(err) .. ". Paredes no creadas.");
        return false;
    end;

    local folder = Instance.new("Folder");
    folder.Name = "CrystalQuestBounds";
    folder.Parent = Workspace;

    cachedBounds = bounds;
    cachedFolder = folder;
    southWallClosed = false;

    local orientations = {
        "North" :: WallOrientation,
        -- "South" :: WallOrientation,  -- Se cierra al iniciar la ronda
        "East" :: WallOrientation,
        "West" :: WallOrientation,
    };

    for _, orientation in ipairs(orientations) do
        local wall = makeWall(bounds, orientation);
        wall.Parent = folder;
    end;

    print(
        "[MapBounds] Paredes creadas (sur abierta). Área: "
        .. tostring(math.floor(bounds.width))
        .. " x "
        .. tostring(math.floor(bounds.depth))
        .. " studs  |  Centro: ("
        .. tostring(math.floor(bounds.centerX))
        .. ", "
        .. tostring(math.floor(bounds.centerZ))
        .. ")"
    );

    return true;
end;

function MapBoundsService.CloseSouthWall(): boolean
    if not initialized then
        warn("[MapBounds] CloseSouthWall requiere Initialize() primero.");
        return false;
    end;

    if southWallClosed then
        return false;
    end;

    local bounds = cachedBounds;
    local folder = cachedFolder;

    if not bounds or not folder or not folder.Parent then
        warn("[MapBounds] No se puede cerrar pared sur: bounds/carpeta no disponibles.");
        return false;
    end;

    southWallClosed = true;

    local wall = makeWall(bounds, "South");
    wall.Parent = folder;

    print("[MapBounds] Pared sur cerrada. Jugador encerrado en el mapa.");

    return true;
end;

return MapBoundsService;
