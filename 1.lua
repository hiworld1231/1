-- AutoHarvest v3.5 — TP к модели + расширенный поиск + DEBUG
-- Телепортируется к модели с ProximityPrompt и пытается нажать его.
-- Работает даже если SpawnedBamboo переcоздаётся / промпты появляются позже.

local ws = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PPS = game:GetService("ProximityPromptService")
local LP = Players.LocalPlayer

-- ====== КОНФИГ ======
local CFG = {
	DEBUG = true,            -- печать подробных логов в консоль (F9)
	Y_OFFSET = 3,            -- на сколько студов выше точки тп
	NEAR_DIST = 8,           -- считаем, что подошли
	TP_TIMEOUT = 1.5,        -- сколько ждём сближения
	NAME_FILTER = "HarvestPrompt",        -- точное имя промпта (nil, чтобы игнорировать)
	ACTION_MATCH = { "harvest", "собрать", "bamboo", "бамбук", "collect", "cut" }, -- match по ActionText (нижний регистр, частичное)
	RESCAN_INTERVAL = 2.5,   -- периодический глобальный рескан
}

-- ====== АНТИ-ДУБЛЬ ======
local env = (getgenv and getgenv()) or _G or shared
if env.__AutoHarvestV35_Running then
	if CFG.DEBUG then print("[AutoHarvest v3.5] Уже запущен") end
	return
end
env.__AutoHarvestV35_Running = true

-- ====== УТИЛИТЫ ======
local function dbg(...)
	if CFG.DEBUG then
		print("[AutoHarvest v3.5]", ...)
	end
end

local function canFire()
	local ok = (type(fireproximityprompt) == "function") or (PPS and PPS.TriggerPrompt)
	if ok then
		if type(fireproximityprompt) == "function" then
			dbg("Метод нажатия: fireproximityprompt")
		elseif PPS and PPS.TriggerPrompt then
			dbg("Метод нажатия: ProximityPromptService:TriggerPrompt")
		end
	else
		dbg("ВНИМАНИЕ: нет способов нажать промпт (ни fireproximityprompt, ни PPS:TriggerPrompt)")
	end
	return ok
end

local function firePrompt(p)
	for i = 1, 3 do
		if type(fireproximityprompt) == "function" then
			local ok, err = pcall(function() fireproximityprompt(p) end)
			dbg("Нажатие fireproximityprompt попытка", i, ok and "OK" or ("FAIL: "..tostring(err)))
		elseif PPS and PPS.TriggerPrompt then
			local ok, err = pcall(function() PPS:TriggerPrompt(p) end)
			dbg("Нажатие PPS:TriggerPrompt попытка", i, ok and "OK" or ("FAIL: "..tostring(err)))
		end
		task.wait(0.05)
		-- если промпт стал Disabled после нажатия — вероятно сработало
		if not p.Enabled then break end
	end
end

local function getChar()
	local char = LP.Character or LP.CharacterAdded:Wait()
	local hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return nil end
	return char, hrp, hum
end

-- модель, относящаяся к промпту
local function getModelFromPrompt(p)
	if not p then return nil end
	local model = p:FindFirstAncestorOfClass("Model")
	if model then return model end
	local parent = p.Parent
	if parent then
		model = parent:FindFirstAncestorOfClass("Model")
		if model then return model end
	end
	return nil
end

local function getModelPos(model)
	if not model then return nil end
	-- 1) Pivot
	if model.GetPivot then
		local ok, cf = pcall(function() return model:GetPivot() end)
		if ok and cf then return cf.Position end
	end
	-- 2) PrimaryPart
	if model.PrimaryPart then
		return model.PrimaryPart.Position
	end
	-- 3) Любой BasePart
	local part = model:FindFirstChildWhichIsA("BasePart", true)
	if part then return part.Position end
	return nil
end

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
	if pos then return pos, model end
	return getFallbackPosFromPrompt(p), model
end

local function teleportTo(pos)
	local char, hrp, hum = getChar()
	if not hrp or not pos then return false end

	pcall(function() if hum.Sit then hum.Sit = false end end)
	pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)

	local target = pos + Vector3.new(0, CFG.Y_OFFSET, 0)
	local cf = CFrame.new(target)

	if char and char.PrimaryPart then
		local ok = pcall(function() char:PivotTo(cf) end)
		dbg("PivotTo", ok and "OK" or "FAIL")
	else
		local ok = pcall(function() hrp.CFrame = cf end)
		dbg("hrp.CFrame assign", ok and "OK" or "FAIL")
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
	return false
end

-- ====== ФИЛЬТР ПРОМПТОВ ======
local function matchesPrompt(p)
	if not p or not p:IsA("ProximityPrompt") then return false end

	if CFG.NAME_FILTER and p.Name == CFG.NAME_FILTER then
		return true
	end

	if CFG.ACTION_MATCH and p.ActionText and #p.ActionText > 0 then
		local act = string.lower(p.ActionText)
		for _, needle in ipairs(CFG.ACTION_MATCH) do
			if string.find(act, needle, 1, true) then
				return true
			end
		end
	end

	-- если нужен только точный матч имени — вернём false
	return (CFG.NAME_FILTER == nil) and false or false
end

-- ====== ОЧЕРЕДЬ ======
local queue, processing = {}, false
local watched = setmetatable({}, { __mode = "k" })

local function enqueue(p)
	table.insert(queue, p)
	dbg("Добавлен в очередь:", p:GetFullName())
	if processing then return end
	processing = true
	task.spawn(function()
		while env.__AutoHarvestV35_Running do
			local item = table.remove(queue, 1)
			if not item then break end
			if item.Parent and item:IsA("ProximityPrompt") then
				-- сделать условия промпта максимально лояльными
				pcall(function()
					item.Enabled = true
					item.HoldDuration = 0
					item.RequiresLineOfSight = false
					item.MaxActivationDistance = 1000
				end)

				local pos, model = getTargetPosFromPrompt(item)
				if pos then
					dbg(("ТП к %s | модель: %s"):format(tostring(pos), model and model:GetFullName() or "нет"))
					local ok = teleportTo(pos)
					dbg("Результат ТП:", ok and "рядом" or "далеко")
				else
					dbg("Не удалось вычислить позицию для промпта", item:GetFullName())
				end

				task.wait(0.05)
				if canFire() then firePrompt(item) else dbg("Нет метода нажатия") end
			end
			task.wait(0.05)
		end
		processing = false
	end)
end

local function watchPrompt(p)
	if watched[p] then return end
	watched[p] = true

	dbg("Нашёл промпт:", p:GetFullName(), "ActionText=", p.ActionText)

	enqueue(p)

	-- если промпт снова включат — обработать
	pcall(function()
		p:GetPropertyChangedSignal("Enabled"):Connect(function()
			if p.Enabled then
				dbg("Промпт снова Enabled:", p:GetFullName())
				enqueue(p)
			end
		end)
	end)

	-- чистка кэша
	p.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			watched[p] = nil
			dbg("Промпт удалён:", p)
		end
	end)
end

-- ====== СКАН ======
local function scan(root)
	if not root then return 0 end
	local n = 0
	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("ProximityPrompt") and matchesPrompt(obj) then
			n += 1
			watchPrompt(obj)
		end
	end
	return n
end

local function hookContainer(container)
	if not container then return end
	local count = scan(container)
	dbg("Скан контейнера:", container:GetFullName(), "найдено промптов:", count)
	container.DescendantAdded:Connect(function(obj)
		if obj:IsA("ProximityPrompt") and matchesPrompt(obj) then
			watchPrompt(obj)
		end
	end)
end

-- ====== ЗАПУСК ======
task.spawn(function()
	dbg("Старт")
	getChar()

	-- 1) Если есть BambooForest — приоритетно там
	local bamboo = ws:FindFirstChild("BambooForest")
	if bamboo then
		dbg("Найден BambooForest")
		local spawned = bamboo:FindFirstChild("SpawnedBamboo")
		if spawned then hookContainer(spawned) end
		bamboo.ChildAdded:Connect(function(child)
			if child.Name == "SpawnedBamboo" then
				dbg("Появился SpawnedBamboo")
				hookContainer(child)
			end
		end)
	else
		dbg("BambooForest не найден — ищу глобально по workspace")
	end

	-- 2) Глобальный хук и рескан по всему workspace (на случай других путей/стриминга)
	hookContainer(ws)

	task.spawn(function()
		while env.__AutoHarvestV35_Running do
			local total = scan(ws)
			dbg("Периодический рескан: найдено промптов за проход:", total)
			task.wait(CFG.RESCAN_INTERVAL)
		end
	end)
end)
