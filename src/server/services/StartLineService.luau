--!strict
local Players = game:GetService("Players");
local Workspace = game:GetService("Workspace");
local ReplicatedStorage = game:GetService("ReplicatedStorage");

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"));

local StartLineService = {};

local initialized = false;
local startTriggered = false;

type OnPlayerCrossed = (Player) -> boolean;

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
    -- LÍNEA VISIBLE
    -- =====================================================
    local startLine = Instance.new("Part");
    startLine.Name = "StartLine";
    startLine.Size = Vector3.new(
        Config.StartLineWidth,
        0.15,
        0.5
    );

    startLine.Position = Vector3.new(
        0,
        0.1,
        Config.StartLineZ
    );

    startLine.Anchored = true;
    startLine.CanCollide = false;
    startLine.CanTouch = false;
    startLine.CanQuery = false;

    startLine.Material = Enum.Material.Neon;
    startLine.Color = Color3.fromRGB(255, 230, 70);

    startLine.Parent = course;

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

        -- El callback devuelve true solo si pudo iniciar la ronda.
        local accepted = onPlayerCrossed(player);

        if not accepted then
            return;
        end;

        -- Un solo cruce válido inicia la ronda compartida.
        startTriggered = true;
        trigger.CanTouch = false;

        startLine.Color = Color3.fromRGB(70, 255, 100);

        print(
            "[StartLine] Ronda iniciada por "
                .. player.Name
        );
    end);
end;

return StartLineService;
