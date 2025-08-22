-- AutoHarvest v3.2 — TP к модели -> активация промпта
-- Телепорт к модели, содержащей ProximityPrompt "HarvestPrompt", затем нажатие.
-- Живучий к пересозданиям/новым объектам, с очередью, ресканом и анти-дублем.

local ws = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PPS = game:GetService("ProximityPromptService")
local LP = Players.LocalPlayer

-- защита от двойного запуска
local env = (getgenv and getgenv()) or _G or shared
if env.__AutoHarvestV3_Running then return end
env.__AutoHarvestV3_Running = true

-- настройки телепорта
local CFG = {
	Y_OFFSET = 3,      -- на сколько студов выше целевой точки появляться
	NEAR_DIST = 8,     -- считаем, что "подошли", если ближе этой дистанции
	TP_TIMEOUT = 1.5,  -- сколько секунд ждать сближения после телепорта
}

-- кэш "подписанных" промптов (слабые ссылки)
local watched = setmetatable({}, { __mode = "k" })

-- проверка возможности «нажатия» промпта
local function canFire()
	return type(fireproximityprompt) == "function" or (PPS and PPS.TriggerPrompt)
end

local function firePrompt(p)
	for i = 1, 3 do
		if type(fireproximityprompt) == "function" then
			pcall(function() fireproximityprompt(p) end)
		elseif PPS and PPS.TriggerPrompt then
			pcall(function() PPS:TriggerPrompt(p) end)
		end
		task.wait(0.05)
	end
end

local function getChar()
	local char = LP.Character or LP.CharacterAdded:Wait()
	local hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return nil end
	return char, hrp, hum
end

-- найти модель, к которой относится промпт
local function getModelFromPrompt(p)
	if not p then return nil end
	-- сам промпт может лежать на Attachment/BasePart — поднимаемся к ближайшей модели
	local model = p:FindFirstAncestorOfClass("Model")
	if model then return model end
	local parent = p.Parent
	if parent then
		model = parent:FindFirstAncestorOfClass("Model")
		if model then return model end
	end
	return nil
end

-- получить мировую позицию модели (pivot/primary/любой BasePart)
local function getModelPos(model)
	if not model then return nil end

	if model.GetPivot then
		local ok, cf = pcall(function() return model:GetPivot() end)
		if ok and cf then
			local pos = cf.Position
			if pos then return pos end
		end
	end

	if model.PrimaryPart then
		return model.PrimaryPart.Position
	end

	local part = model:FindFirstChildWhichIsA("BasePart", true)
	if part then return part.Position end

	return nil
end

-- запасной способ: если модель не нашлась, телепорт к носителю промпта
local function getFallbackPosFromPrompt(p)
	local parent = p and p.Parent
	if not parent then return nil end
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	if parent:IsA("BasePart") then
		return parent.Position
	end
	local part = parent:FindFirstAncestorOfClass("BasePart")
	if part then return part.Position end
	return nil
end

local function getTargetPosFromPrompt(p)
	local model = getModelFromPrompt(p)
	local pos = getModelPos(model)
	if pos then return pos end
	return getFallbackPosFromPrompt(p)
end

local function teleportTo(pos)
	local char, hrp, hum = getChar()
	if not hrp or not pos then return false end

	pcall(function() if hum.Sit then hum.Sit = false end end)
	pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)

	local target = pos + Vector3.new(0, CFG.Y_OFFSET, 0)
	local cf = CFrame.new(target)

	if char and char.PrimaryPart then
		pcall(function() char:PivotTo(cf) end)
	else
		pcall(function() hrp.CFrame = cf end)
		if char and not char.PrimaryPart then
			pcall(function() char.PrimaryPart = hrp end)
		end
	end

	-- ждём фактического сближения
	local t0 = os.clock()
	while os.clock() - t0 < CFG.TP_TIMEOUT do
		if (hrp.Position - target).Magnitude < CFG.NEAR_DIST then
			return true
		end
		RunService.Heartbeat:Wait()
	end
	return false
end

-- очередь, чтобы не телепортироваться параллельно
local queue, processing = {}, false
local function enqueue(p)
	table.insert(queue, p)
	if processing then return end
	processing = true
	task.spawn(function()
		while env.__AutoHarvestV3_Running do
			local item = table.remove(queue, 1)
			if not item then break end
			if item.Parent and item:IsA("ProximityPrompt") then
				-- делаем промпт максимально «лояльным»
				pcall(function()
					item.Enabled = true
					item.HoldDuration = 0
					item.RequiresLineOfSight = false
					item.MaxActivationDistance = 1000
				end)

				-- телепорт к МОДЕЛИ и нажатие
				local pos = getTargetPosFromPrompt(item)
				if pos then teleportTo(pos) end
				task.wait(0.05)
				if canFire() then firePrompt(item) end
			end
			task.wait(0.05)
		end
		processing = false
	end)
end

local function watchPrompt(p)
	if watched[p] then return end
	watched[p] = true

	enqueue(p)

	-- если промпт заново включили — снова обработать
	pcall(function()
		p:GetPropertyChangedSignal("Enabled"):Connect(function()
			if p.Enabled then enqueue(p) end
		end)
	end)

	-- чистка при удалении
	p.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			watched[p] = nil
		end
	end)
end

local function scan(root)
	if not root then return end
	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("ProximityPrompt") and obj.Name == "HarvestPrompt" then
			watchPrompt(obj)
		end
	end
end

local function hookSpawned(spawned)
	if not spawned then return end
	scan(spawned)
	spawned.DescendantAdded:Connect(function(obj)
		if obj:IsA("ProximityPrompt") and obj.Name == "HarvestPrompt" then
			watchPrompt(obj)
		end
	end)
end

-- основной запуск
task.spawn(function()
	getChar()

	local bamboo = ws:WaitForChild("BambooForest", 30)
	if not bamboo then
		warn("[AutoHarvest v3.2] Не найден workspace.BambooForest")
		return
	end

	local spawned = bamboo:FindFirstChild("SpawnedBamboo")
	if spawned then hookSpawned(spawned) end

	bamboo.ChildAdded:Connect(function(child)
		if child.Name == "SpawnedBamboo" then
			hookSpawned(child)
		end
	end)

	-- страховочный рескан (стрим/потери ивентов)
	task.spawn(function()
		while env.__AutoHarvestV3_Running do
			local sb = bamboo:FindFirstChild("SpawnedBamboo")
			if sb then scan(sb) end
			task.wait(2.5)
		end
	end)
end)
