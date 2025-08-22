-- AutoHarvest v3.1 — TP -> Fire (fixed typeof)
-- Телепортируется к каждому HarvestPrompt в workspace.BambooForest.SpawnedBamboo
-- и нажимает его. Живучий к пересозданиям/новым объектам.

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
	NEAR_DIST = 8,     -- расстояние, которое считаем «подошёл»
	TP_TIMEOUT = 1.5,  -- сколько секунд ждём сближения после телепорта
}

-- кэш "подписанных" промптов
local watched = setmetatable({}, { __mode = "k" })

-- проверка доступности «стрельбы» по промпту в любом окружении
local function canFire()
	return type(fireproximityprompt) == "function" or (PPS and PPS.TriggerPrompt)
end

local function firePrompt(p)
	-- несколько попыток на случай лагов/репликации
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
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return nil end
	return char, hrp, hum
end

local function getPromptPos(p)
	if not p then return nil end
	local adornee = p.Adornee or p.Parent
	if not adornee then return nil end

	if adornee:IsA("Attachment") then
		return adornee.WorldPosition
	end
	if adornee:IsA("BasePart") then
		return adornee.Position
	end

	local part = adornee:FindFirstAncestorOfClass("BasePart")
	if part then return part.Position end

	local model = adornee:FindFirstAncestorOfClass("Model")
	if model and model.PrimaryPart then
		return model.PrimaryPart.Position
	end
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

	-- ждём, пока реально окажемся рядом
	local ok = false
	local t0 = os.clock()
	while os.clock() - t0 < CFG.TP_TIMEOUT do
		if (hrp.Position - target).Magnitude < CFG.NEAR_DIST then
			ok = true
			break
		end
		RunService.Heartbeat:Wait()
	end
	return ok
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

				-- телепорт и нажатие
				local pos = getPromptPos(item)
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
		warn("[AutoHarvest v3.1] Не найден workspace.BambooForest")
		return
	end

	local spawned = bamboo:FindFirstChild("SpawnedBamboo")
	if spawned then hookSpawned(spawned) end

	bamboo.ChildAdded:Connect(function(child)
		if child.Name == "SpawnedBamboo" then
			hookSpawned(child)
		end
	end)

	-- страховочный рескан
	task.spawn(function()
		while env.__AutoHarvestV3_Running do
			local sb = bamboo:FindFirstChild("SpawnedBamboo")
			if sb then scan(sb) end
			task.wait(2.5)
		end
	end)
end)
