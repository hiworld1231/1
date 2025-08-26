--[[
Instant-активация всех ProximityPrompt'ов "PosterPrompt" внутри моделей "propogandaPoster",
если игрок находится в радиусе MaxActivationDistance каждого из них.
Работает одним скриптом: запускается сразу и повторно по клавише K.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local LOCAL_PLAYER = Players.LocalPlayer
local HOTKEY = Enum.KeyCode.K -- поменяй при желании

local function getHRP()
    local char = LOCAL_PLAYER.Character or LOCAL_PLAYER.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

-- Мгновенная активация: сначала нативным API (TriggerPrompt),
-- если игра/движок не даёт — фолбэк на fireproximityprompt (экзекьюторная функция).
local function activatePrompt(prompt: ProximityPrompt)
    -- Попытка нативного "настоящего" триггера (без удержания)
    local ok = pcall(function()
        ProximityPromptService:TriggerPrompt(prompt)
    end)
    if not ok and typeof(fireproximityprompt) == "function" then
        -- Фолбэк: большинство экзекьюторов активируют без зажатия просто так
        pcall(function()
            fireproximityprompt(prompt)
        end)
    end
end

local function triggerAllNearby()
    local hrp = getHRP()
    local hrpPos = hrp.Position
    local activated = 0

    -- Обходим ВСЕ объекты один раз
    for _, inst in ipairs(workspace:GetDescendants()) do
        if inst:IsA("Model") and inst.Name == "propogandaPoster" then
            -- Ищем MainPoster (Part) и внутри него PosterPrompt
            local main = inst:FindFirstChild("MainPoster", true)
            if main and main:IsA("BasePart") then
                local prompt = main:FindFirstChild("PosterPrompt", true)
                if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
                    local dist = (hrpPos - main.Position).Magnitude
                    local maxDist = prompt.MaxActivationDistance or 10
                    -- "Поблизости": уважаем радиус активации самого промпта (с небольшим запасом)
                    if dist <= (maxDist + 1) then
                        activatePrompt(prompt)
                        activated += 1
                    end
                end
            end
        end
    end

    -- Небольшой тостер-уведомлятор (не обязателен)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Posters";
            Text = "Активировано: " .. tostring(activated);
            Duration = 3;
        })
    end)
end

-- Запуск сразу
triggerAllNearby()

-- Хоткей для повторного прогона (K по умолчанию)
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == HOTKEY then
        triggerAllNearby()
    end
end)
