-- AutoHarvest v4.2 — только SpawnedBamboo, ТП к каждому бамбуку
-- 1) Находит ВСЕ модели внутри workspace.BambooForest.SpawnedBamboo (старые и новые)
-- 2) ТП к КАЖДОМУ конкретному бамбуку (модель = прямой ребёнок SpawnedBamboo)
-- 3) Нажимает его ProximityPrompt ("HarvestPrompt" или любой, если имя другое)
-- 4) Повторяет для всех. НИЧЕГО НЕ УДАЛЯЕТ.

local ws = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PPS = game:GetService("ProximityPromptService")
local LP = Players.LocalPlayer

-- антидвойной запуск
local env = (getgenv and getgenv()) or _G or shared
if env.__AutoHarvestV42_Running then return end
env.__AutoHarvestV42_Running = true

-- ===== Настройки =====
local CFG = {
	ROOT_NAME       = "BambooForest",   -- модель-плита, в ней нас интересует только папка SpawnedBamboo
	FOLDER_NAME     = "SpawnedBamboo",  -- папка с МОДЕЛЯМИ БАМБУКА (каждый бамбук — отдельная Model)
	PROMPT_NAME     = "HarvestPrompt",  -- целевое имя; если не найден, берём любой ProximityPrompt в модели
	Y_OFFSET        = 3,
	NEAR_DIST       = 8,
	TP_TIMEOUT      = 1.5,
	RESCAN_INTERVAL = 2.5,
	LOYAL_PROMPT    = true,             -- подправлять свойства промпта (HoldDuration=0 и т.д.)
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

local function modelWorldPos(model)
	if not model then return nil end
	if model.GetPivot then
		local ok, cf = pcall(function() return model:GetPivot() end)
		if ok and cf then return cf.Position end
	end
	if model.PrimaryPart then return model.PrimaryPart.Position end
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
	return true
end

-- ===== Работаем ТОЛЬКО с моделями — ПРЯМЫМИ детьми SpawnedBamboo =====
local processed = setmetatable({}, { __mode = "k" }) -- какие модели уже поставлены в очередь
local queue, processing = {}, false
local currentSpawned -- ссылка на актуальную папку SpawnedBamboo

local function findPromptIn(model)
	if not model then return nil end
	-- приоритет: точное имя
	local p = model:FindFirstChild(CFG.PROMPT_NAME, true)
	if p and p:IsA("ProximityPrompt") then return p end
	-- иначе — первый попавшийся ProximityPrompt
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ProximityPrompt") then return d end
	end
	return nil
end

local function enqueueModel(model)
	if not model or processed[model] then return end
	processed[model] = true
	table.insert(queue, model)

	if processing then return end
	processing = true
	task.spawn(function()
		while env.__AutoHarvestV42_Running do
			local m = table.remove(queue, 1)
			if not m then break end
			if m.Parent == nil then
				processed[m] = nil
			else
				-- ТП строго к этому бамбуку (модель — прямой ребёнок SpawnedBamboo)
				local pos = modelWorldPos(m)
				if pos then teleportTo(pos) end
				task.wait(0.05)

				local p = findPromptIn(m)
				if p and p:IsA("ProximityPrompt") then
					if CFG.LOYAL_PROMPT then
						pcall(function()
							p.Enabled = true
							p.HoldDuration = 0
							p.RequiresLineOfSight = false
						end)
					end
					if canFire() then pressPrompt(p) end

					-- если промпт снова включат (регроу) — обработать ещё раз
					pcall(function()
						p:GetPropertyChangedSignal("Enabled"):Connect(function()
							if p.Enabled then
								processed[m] = nil
								enqueueModel(m)
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

-- пройтись только по прямым детям SpawnedBamboo и поставить их в очередь
local function scanSpawned()
	if not currentSpawned then return end
	for _, child in ipairs(currentSpawned:GetChildren()) do
		if child:IsA("Model") then
			enqueueModel(child)
		end
	end
end

-- любые новые объекты под SpawnedBamboo: если это модель — сразу в очередь;
-- если это что-то внутри модели (например, сам ProximityPrompt) — берём верхнюю модель-ребёнка SpawnedBamboo.
local function hookSpawned(folder)
	currentSpawned = folder
	scanSpawned()

	folder.ChildAdded:Connect(function(obj)
		if obj:IsA("Model") then
			enqueueModel(obj)
		end
	end)

	-- на случай, если добавляют глубже, чем в корень папки:
	folder.DescendantAdded:Connect(function(obj)
		if obj:IsA("ProximityPrompt") then
			-- подняться до модели, которая является ПРЯМЫМ ребёнком SpawnedBamboo
			local m = obj:FindFirstAncestorOfClass("Model")
			while m and m.Parent ~= folder do
				m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model") or nil
			end
			if m and m.Parent == folder then
				enqueueModel(m)
			end
		end
	end)
end

-- ===== запуск =====
task.spawn(function()
	getChar()

	local forest = ws:WaitForChild(CFG.ROOT_NAME, 30)
	if not forest then
		warn("[AutoHarvest v4.2] Не найден workspace." .. CFG.ROOT_NAME)
		return
	end

	local spawned = forest:WaitForChild(CFG.FOLDER_NAME, 30)
	if not spawned then
		warn("[AutoHarvest v4.2] Не найдена папка " .. CFG.FOLDER_NAME .. " в " .. CFG.ROOT_NAME)
		return
	end

	hookSpawned(spawned)

	-- если папку пересоздают — пере-хукаемся
	forest.ChildAdded:Connect(function(child)
		if child.Name == CFG.FOLDER_NAME then
			hookSpawned(child)
		end
	end)

	-- периодический рескан только папки SpawnedBamboo
	task.spawn(function()
		while env.__AutoHarvestV42_Running do
			scanSpawned()
			task.wait(CFG.RESCAN_INTERVAL)
		end
	end)
end)
