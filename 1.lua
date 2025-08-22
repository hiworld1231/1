-- AutoHarvest v4 — Bamboo-by-Bamboo
-- 1) Находит ВСЕ бамбуки (существующие и новые) в workspace.BambooForest.SpawnedBamboo
-- 2) ТП к КАЖДОМУ КОНКРЕТНОМУ БАМБУКУ (его модели)
-- 3) Активирует его ProximityPrompt "HarvestPrompt"
-- 4) Повторяет для всех, переживает пересоздание контейнера. НИЧЕГО НЕ УДАЛЯЕТ.

local ws = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PPS = game:GetService("ProximityPromptService")
local LP = Players.LocalPlayer

-- антидвойной запуск
local env = (getgenv and getgenv()) or _G or shared
if env.__AutoHarvestV4_Running then return end
env.__AutoHarvestV4_Running = true

-- ===== Настройки =====
local CFG = {
	PATH_ROOT_NAME   = "BambooForest",
	CONTAINER_NAME   = "SpawnedBamboo",
	PROMPT_NAME      = "HarvestPrompt",
	Y_OFFSET         = 3,     -- на сколько студов выше точки ТП
	NEAR_DIST        = 8,     -- считаем что подбежали
	TP_TIMEOUT       = 1.5,   -- сек ожидания после ТП
	LOYAL_PROMPT     = true,  -- мягко подправлять свойства промпта (Hold=0, и т.п.)
	RESCAN_INTERVAL  = 2.5,   -- периодический рескан
}

-- ===== Утилиты =====
local function canFire()
	return type(fireproximityprompt) == "function" or (PPS and PPS.TriggerPrompt)
end

local function pressPrompt(p)
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
	if hum and hum.Health <= 0 then return nil end
	return char, hrp, hum
end

-- вернуть МОДЕЛЬ конкретного бамбука по промпту
local function bambooModelFromPrompt(p)
	if not p then return nil end
	local m = p:FindFirstAncestorOfClass("Model")
	if m then return m end
	if p.Parent then
		m = p.Parent:FindFirstAncestorOfClass("Model")
		if m then return m end
	end
	return nil
end

-- позиция модели бамбука
local function getModelPos(model)
	if not model then return nil end
	-- GetPivot (Roblox API)
	if model.GetPivot then
		local ok, cf = pcall(function() return model:GetPivot() end)
		if ok and cf then return cf.Position end
	end
	-- PrimaryPart
	if model.PrimaryPart then return model.PrimaryPart.Position end
	-- Любой BasePart
	local part = model:FindFirstChildWhichIsA("BasePart", true)
	if part then return part.Position end
	return nil
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

	local t0 = os.clock()
	while os.clock() - t0 < CFG.TP_TIMEOUT do
		if (hrp.Position - target).Magnitude < CFG.NEAR_DIST then
			return true
		end
		RunService.Heartbeat:Wait()
	end
	return true -- даже если не уложились по таймауту, идём дальше
end

-- ===== учёт бамбуков и очередь =====
-- На каждом бамбуке может быть 1 промпт. Обрабатываем БАМБУК (модель), а не общий контейнер.
local seenBamboo = setmetatable({}, { __mode = "k" }) -- чтобы не дублировать в очереди
local queue, processing = {}, false

local function findPromptInBamboo(model)
	if not model then return nil end
	-- точное имя
	local p = model:FindFirstChild(CFG.PROMPT_NAME, true)
	if p and p:IsA("ProximityPrompt") then return p end
	-- или просто любой ProximityPrompt внутри
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ProximityPrompt") then return d end
	end
	return nil
end

local function enqueueBamboo(model)
	if not model or seenBamboo[model] then return end
	seenBamboo[model] = true
	table.insert(queue, model)

	if processing then return end
	processing = true
	task.spawn(function()
		while env.__AutoHarvestV4_Running do
			local m = table.remove(queue, 1)
			if not m then break end
			if m.Parent == nil then
				seenBamboo[m] = nil
			else
				-- ТП к КОНКРЕТНОЙ модели бамбука
				local pos = getModelPos(m)
				if pos then teleportTo(pos) end
				task.wait(0.05)

				-- найти и нажать его промпт
				local p = findPromptInBamboo(m)
				if p and p:IsA("ProximityPrompt") then
					if CFG.LOYAL_PROMPT then
						pcall(function()
							p.Enabled = true
							p.HoldDuration = 0
							p.RequiresLineOfSight = false
							-- расстояние оставим дефолтным: мы уже рядом
						end)
					end
					if canFire() then pressPrompt(p) end

					-- если промпт позже снова включится (регроу) — обработаем повторно
					pcall(function()
						p:GetPropertyChangedSignal("Enabled"):Connect(function()
							if p.Enabled then
								seenBamboo[m] = nil
								enqueueBamboo(m)
							end
						end)
					end)
				end
			end
			task.wait(0.05)
		end
		processing = false
	end)
end

-- скан контейнера на ВСЕ бамбуки: берём модели, в которых есть ProximityPrompt
local function scanContainer(container)
	if not container then return end
	for _, obj in ipairs(container:GetDescendants()) do
		if obj:IsA("ProximityPrompt") then
			local m = bambooModelFromPrompt(obj)
			if m then enqueueBamboo(m) end
		end
	end
end

local function hookContainer(container)
	if not container then return end
	scanContainer(container)
	container.DescendantAdded:Connect(function(obj)
		if obj:IsA("ProximityPrompt") then
			local m = bambooModelFromPrompt(obj)
			if m then enqueueBamboo(m) end
		end
	end)
end

-- ===== запуск =====
task.spawn(function()
	getChar()

	-- приоритетный путь: workspace.BambooForest.SpawnedBamboo
	local bambooRoot = ws:FindFirstChild(CFG.PATH_ROOT_NAME)
	if bambooRoot then
		local spawned = bambooRoot:FindFirstChild(CFG.CONTAINER_NAME)
		if spawned then hookContainer(spawned) end
		bambooRoot.ChildAdded:Connect(function(child)
			if child.Name == CFG.CONTAINER_NAME then
				hookContainer(child)
			end
		end)
	else
		-- если нет BambooForest — работаем по всему workspace (на случай другой структуры)
		hookContainer(ws)
	end

	-- периодический рескан, чтобы подхватывать всё (стриминг/потери событий)
	task.spawn(function()
		while env.__AutoHarvestV4_Running do
			local container = bambooRoot and bambooRoot:FindFirstChild(CFG.CONTAINER_NAME) or ws
			scanContainer(container)
			task.wait(CFG.RESCAN_INTERVAL)
		end
	end)
end)
