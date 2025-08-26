--[[
Авто-активация ВСЕХ ближайших ProximityPrompt'ов "PosterPrompt" внутри моделей "propogandaPoster".
Работает НОН-СТОП (без кнопок/зажатий/телепортов), максимально быстро, в один скрипт.

Логика:
1) Находит все нужные постеры (Model "propogandaPoster" -> BasePart "MainPoster" -> ProximityPrompt "PosterPrompt").
2) Следит за новыми постерами в реальном времени.
3) На каждом кадре активирует все промпты в радиусе их MaxActivationDistance (мгновенно).
4) Не спамит один и тот же промпт чаще, чем раз в CD сек.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LOCAL_PLAYER = Players.LocalPlayer

-- Настройки (при желании меняй)
local TARGET_MODEL_NAME = "propogandaPoster"
local MAIN_PART_NAME    = "MainPoster"
local PROMPT_NAME       = "PosterPrompt"
local DIST_FUDGE        = 15        -- небольшой запас к дистанции
local COOLDOWN_SEC      = 0.10     -- чтобы не долбить один и тот же промпт слишком часто

-- Хранилище отслеживаемых промптов: [prompt] = { part = BasePart, last = number }
local tracked = {}

local function getHRP()
    local char = LOCAL_PLAYER.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function cleanPrompt(prompt)
    tracked[prompt] = nil
end

local function safeConnect(inst, signalName, fn)
    local ok, conn = pcall(function() return inst[signalName]:Connect(fn) end)
    return ok and conn or nil
end

local function activatePrompt(prompt: ProximityPrompt)
    -- Сначала нативный способ — реальное "АКТИВИРОВАТЬ", без удержания
    local ok = pcall(function()
        ProximityPromptService:TriggerPrompt(prompt)
    end)
    if not ok and typeof(fireproximityprompt) == "function" then
        -- Фолбэк большинства экзекьюторов — тоже мгновенно
        pcall(function()
            fireproximityprompt(prompt)
        end)
    end
end

local function addPrompt(prompt: Instance, mainPart: Instance)
    if not (prompt and prompt:IsA("ProximityPrompt")) then return end
    if not (mainPart and mainPart:IsA("BasePart")) then return end
    if tracked[prompt] then return end

    tracked[prompt] = { part = mainPart, last = 0 }

    -- Удаляем из трекинга, если пропало из мира
    safeConnect(prompt, "AncestryChanged", function()
        if not prompt:IsDescendantOf(workspace) then
            cleanPrompt(prompt)
        end
    end)
    safeConnect(mainPart, "AncestryChanged", function()
        if not mainPart:IsDescendantOf(workspace) then
            cleanPrompt(prompt)
        end
    end)
end

local function tryRegisterFromModel(model: Instance)
    if not (model and model:IsA("Model") and model.Name == TARGET_MODEL_NAME) then return end
    -- Ищем MainPoster и внутри него PosterPrompt (может быть вложено глубже)
    local main = model:FindFirstChild(MAIN_PART_NAME, true)
    if not (main and main:IsA("BasePart")) then return end
    local prompt = main:FindFirstChild(PROMPT_NAME, true)
    if prompt and prompt:IsA("ProximityPrompt") then
        addPrompt(prompt, main)
    end
end

-- Стартовая индексация
for _, inst in ipairs(workspace:GetDescendants()) do
    if inst:IsA("Model") and inst.Name == TARGET_MODEL_NAME then
        tryRegisterFromModel(inst)
    end
end

-- Отслеживаем появление новых моделей/промптов на лету
workspace.DescendantAdded:Connect(function(inst)
    -- Если добавили целую модель постера
    if inst:IsA("Model") and inst.Name == TARGET_MODEL_NAME then
        tryRegisterFromModel(inst)
        -- На случай, если PosterPrompt вольётся позже:
        inst.DescendantAdded:Connect(function(sub)
            if sub:IsA("ProximityPrompt") and sub.Name == PROMPT_NAME then
                -- Убедимся, что есть MainPoster вверх/вниз по иерархии
                local main = inst:FindFirstChild(MAIN_PART_NAME, true)
                if main and main:IsA("BasePart") then
                    addPrompt(sub, main)
                end
            end
        end)
    elseif inst:IsA("ProximityPrompt") and inst.Name == PROMPT_NAME then
        -- Промпт появился отдельно — проверим предка-модель и MainPoster
        local model = inst:FindFirstAncestorOfClass("Model")
        while model and model.Name ~= TARGET_MODEL_NAME do
            model = model:FindFirstAncestorOfClass("Model")
        end
        if model then
            local main = model:FindFirstChild(MAIN_PART_NAME, true)
            if main and main:IsA("BasePart") then
                addPrompt(inst, main)
            end
        end
    end
end)

-- Главный бесконечный цикл: НОН-СТОП активация ближайших
RunService.Heartbeat:Connect(function()
    local hrp = getHRP()
    if not hrp then return end
    local hrpPos = hrp.Position
    local now = time()

    for prompt, info in pairs(tracked) do
        local valid = prompt
            and info
            and info.part
            and prompt.Parent
            and info.part.Parent
            and prompt:IsDescendantOf(workspace)
            and info.part:IsDescendantOf(workspace)

        if not valid then
            cleanPrompt(prompt)
        else
            if prompt.Enabled then
                local maxDist = (prompt.MaxActivationDistance or 10) + DIST_FUDGE
                local dist = (hrpPos - info.part.Position).Magnitude
                if dist <= maxDist then
                    if (now - (info.last or 0)) >= COOLDOWN_SEC then
                        activatePrompt(prompt)
                        info.last = now
                    end
                end
            end
        end
    end
end)

-- На случай респавна персонажа — всё продолжит работать автоматически
Players.LocalPlayer.CharacterAdded:Connect(function()
    -- ничего делать не нужно: цикл сам подхватит новый HRP
end)
