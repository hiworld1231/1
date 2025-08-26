-- Локальный скрипт
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local radius = 90

while true do
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if root then
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
    end
    task.wait()
end
