-- Локальный скрипт
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local radius = 90

RunService.RenderStepped:Connect(function()
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    for _, poster in ipairs(workspace:GetDescendants()) do
        if poster.Name == "PosterPrompt" and poster:IsA("ProximityPrompt") then
            local part = poster.Parent
            if part and part:IsA("BasePart") and part.Parent and part.Parent.Name == "propogandaPoster" then
                if (part.Position - root.Position).Magnitude <= radius then
                    fireproximityprompt(poster, math.huge)
                end
            end
        end
    end
end)
