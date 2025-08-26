-- ultra-fast auto-activator for "propogandaPoster" nearby the local player
-- Place as a LocalScript in StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- === config (меняй при необходимости) ==========================
local POSTER_MODEL_NAME = "propogandaPoster"
local MAIN_PART_NAME    = "MainPoster"
local PROMPT_NAME       = "PosterPrompt"

-- Если нужно прямо одновременное срабатывание множества подсказок на одной кнопке,
-- можно разрешить отображение всех сразу (обычно и без этого ок):
local FORCE_ALWAYS_SHOW = false
-- ===============================================================

local localPlayer = Players.LocalPlayer
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local rootPart = character:WaitForChild("HumanoidRootPart")

-- следим за респавнами
localPlayer.CharacterAdded:Connect(function(char)
	character = char
	rootPart = char:WaitForChild("HumanoidRootPart")
end)

-- храним все найденные промпты: [prompt] = { part = MainPoster, holding = false, t0 = 0 }
local tracked = {}

local function safeConnectPromptCleanup(prompt)
	prompt.AncestryChanged:Connect(function(_, parent)
		if not parent then
			tracked[prompt] = nil
		end
	end)
	prompt.Destroying:Connect(function()
		tracked[prompt] = nil
	end)
end

local function tryRegisterFromModel(model: Model)
	if model.Name ~= POSTER_MODEL_NAME then return end

	-- ищем MainPoster (Part) и внутри него PosterPrompt
	local main = model:FindFirstChild(MAIN_PART_NAME, true)
	if not (main and main:IsA("BasePart")) then return end

	local prompt = main:FindFirstChild(PROMPT_NAME)
	if not (prompt and prompt:IsA("ProximityPrompt")) then return end

	if FORCE_ALWAYS_SHOW then
		pcall(function()
			prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
		end)
	end

	if not tracked[prompt] then
		tracked[prompt] = { part = main, holding = false, t0 = 0 }
		safeConnectPromptCleanup(prompt)
	end
end

-- начальный скан
for _, inst in ipairs(Workspace:GetDescendants()) do
	if inst:IsA("Model") and inst.Name == POSTER_MODEL_NAME then
		tryRegisterFromModel(inst)
	end
end

-- новые постеры на лету
Workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") and inst.Name == POSTER_MODEL_NAME then
		tryRegisterFromModel(inst)
	elseif inst:IsA("ProximityPrompt") and inst.Name == PROMPT_NAME then
		-- Если вдруг подсказка добавилась позже — поднимемся до Model и проверим
		local model = inst:FindFirstAncestorOfClass("Model")
		if model and model.Name == POSTER_MODEL_NAME then
			tryRegisterFromModel(model)
		end
	end
end)

-- как можно быстрее: каждую "физическую" итерацию (Heartbeat) без искусственных задержек
RunService.Heartbeat:Connect(function()
	if not (rootPart and rootPart.Parent) then return end

	local now = os.clock()

	for prompt, data in pairs(tracked) do
		-- проверка валидности
		if not (prompt and prompt.Parent and prompt.Enabled) then
			tracked[prompt] = nil
			continue
		end
		local main = data.part
		if not (main and main.Parent) then
			tracked[prompt] = nil
			continue
		end

		-- дистанция до игрока; используем MaxActivationDistance самого промпта
		local dist = (rootPart.Position - main.Position).Magnitude
		local maxd = prompt.MaxActivationDistance or 10

		if dist <= maxd + 1e-3 then
			-- Если требуется удержание — "жмём" и держим столько, сколько задано
			local hold = prompt.HoldDuration or 0
			if hold > 0 then
				if not data.holding then
					pcall(function() prompt:InputHoldBegin() end)
					data.holding = true
					data.t0 = now
				elseif now - data.t0 >= hold then
					pcall(function() prompt:InputHoldEnd() end)
					data.holding = false
					data.t0 = 0
				end
			else
				-- мгновенные промпты: нажать и отпустить в тот же кадр
				pcall(function()
					prompt:InputHoldBegin()
					prompt:InputHoldEnd()
				end)
			end
		else
			-- вышли из радиуса — отпускаем, если держали
			if data.holding then
				pcall(function() prompt:InputHoldEnd() end)
				data.holding = false
				data.t0 = 0
			end
		end
	end
end)
