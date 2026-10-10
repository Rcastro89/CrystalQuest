--!strict
local Players = game:GetService("Players");
local Workspace = game:GetService("Workspace");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local InsertService = game:GetService("InsertService");

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"));

local StartLineService = {};

local initialized = false;
local startTriggered = false;

local START_LINE_ASSET_ID = 2037650641;

type OnPlayerCrossed = (Player) -> boolean;

local function configureStartLineModel(model: Model)
    model.Name = "StartLine";

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true;
            descendant.CanCollide = false;
            descendant.CanTouch = false;
            descendant.CanQuery = false;
        end;
    end;

    local modelSize = model:GetExtentsSize();
    local targetY = 0.1 + (modelSize.Y / 2);
    model:PivotTo(CFrame.new(0, targetY, Config.StartLineZ) * CFrame.Angles(0, math.rad(90), 0));
end;

local function getStartLineParts(model: Model): {BasePart}
    local parts: {BasePart} = {};
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            table.insert(parts, descendant);
        end;
    end;
    return parts;
end;

local function setStartLineColor(parts: {BasePart}, color: Color3)
    for _, part in ipairs(parts) do
        part.Color = color;
    end;
end;

function StartLineService.Initialize(onPlayerCrossed: OnPlayerCrossed)
    if initialized then
        warn("[StartLine] El servicio ya fue inicializado.");
        return;
    end;

    initialized = true;

    -- Agrupamos los objetos del recorrido para mantener Workspace organizado.
    local oldCourse = Workspace:FindFirstChild("CrystalQuestCourse");

    if oldCourse then
        oldCourse:Destroy();
    end;

    local course = Instance.new("Folder");
    course.Name = "CrystalQuestCourse";
    course.Parent = Workspace;

    -- =====================================================
    -- LÍNEA VISIBLE (MODELO 3D DE LA TOOLBOX)
    -- =====================================================
    local startLineParts: {BasePart} = {};
    local loadSuccess, assetModel = pcall(function()
        return InsertService:LoadAsset(START_LINE_ASSET_ID);
    end);

    local startLineModel: Model;

    if loadSuccess and assetModel then
        local firstChild = assetModel:FindFirstChildWhichIsA("Model");
        if firstChild then
            startLineModel = firstChild :: Model;
        else
            local anyChild = assetModel:GetChildren()[1];
            if anyChild and anyChild:IsA("Model") then
                startLineModel = anyChild :: Model;
            end;
        end;

        if startLineModel then
            configureStartLineModel(startLineModel);
            startLineModel.Parent = course;
            startLineParts = getStartLineParts(startLineModel);
        else
            warn("[StartLine] No se pudo extraer un Model del asset ID " .. START_LINE_ASSET_ID .. ". Usando fallback.");
        end;
    else
        warn("[StartLine] Error al cargar asset ID " .. START_LINE_ASSET_ID .. ": " .. tostring(assetModel) .. ". Usando fallback.");
    end;

    if not startLineModel then
        local fallback = Instance.new("Part");
        fallback.Name = "StartLine";
        fallback.Size = Vector3.new(Config.StartLineWidth, 0.15, 0.5);
        fallback.Position = Vector3.new(0, 0.1, Config.StartLineZ);
        fallback.Anchored = true;
        fallback.CanCollide = false;
        fallback.CanTouch = false;
        fallback.CanQuery = false;
        fallback.Material = Enum.Material.Neon;
        fallback.Color = Color3.fromRGB(255, 230, 70);
        fallback.Parent = course;
        startLineParts = {fallback};
    end;

    -- =====================================================
    -- SENSOR INVISIBLE DE LA LÍNEA
    -- =====================================================
    local trigger = Instance.new("Part");
    trigger.Name = "StartLineTrigger";

    trigger.Size = Vector3.new(
        Config.StartLineWidth,
        Config.StartLineTriggerHeight,
        Config.StartLineTriggerDepth
    );

    trigger.Position = Vector3.new(
        0,
        Config.StartLineTriggerHeight / 2,
        Config.StartLineZ
    );

    trigger.Anchored = true;
    trigger.CanCollide = false;
    trigger.CanTouch = true;
    trigger.CanQuery = false;
    trigger.Transparency = 1;

    trigger.Parent = course;

    -- =====================================================
    -- DETECCIÓN DEL CRUCE
    -- =====================================================
    trigger.Touched:Connect(function(hit: BasePart)
        if startTriggered then
            return;
        end;

        local character = hit:FindFirstAncestorOfClass("Model");

        if not character then
            return;
        end;

        local player = Players:GetPlayerFromCharacter(character);

        if not player then
            return;
        end;

        local humanoid = character:FindFirstChildOfClass("Humanoid");

        if not humanoid or humanoid.Health <= 0 then
            return;
        end;

        -- IMPORTANTE: Desactivamos el trigger y marcamos el
        -- estado ANTES de invocar el callback. Durante la
        -- carga de assets (modelo 3D, enemigos, etc.) pueden
        -- pasar ~300ms y Touched suele dispararse varias
        -- veces (varias partes del jugador o incluso nuevos
        -- Models entrando en Workspace). Cerrar la compuerta
        -- primero evita doble ejecución del onPlayerCrossed.
        startTriggered = true;
        trigger.CanTouch = false;

        -- El callback devuelve true solo si pudo iniciar la ronda.
        local accepted = onPlayerCrossed(player);

        if not accepted then
            -- Rollback: si el servidor rechazó el inicio,
            -- volvemos a habilitar la línea para otro intento.
            startTriggered = false;
            trigger.CanTouch = true;
            return;
        end;

        setStartLineColor(startLineParts, Color3.fromRGB(70, 255, 100));

        print(
            "[StartLine] Ronda iniciada por "
                .. player.Name
        );
    end);
end;

return StartLineService;
