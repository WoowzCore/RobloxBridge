--[[
    ObbyManager
    ----------------
    Серверная логика обби:
      * регистрация чекпоинтов по тегу "Checkpoint" в Workspace/Obby/*
      * сохранение прогресса игрока (последний чекпоинт)
      * таймер прохождения
      * финиш с наградой и записью в DataStore
      * защита от падения (FallenPartsDestroyHeight -> респавн на чекпоинте)

    Все чекпоинты имеют тег "Checkpoint" в .bridge и лежат внутри моделей секций.
    Порядок чекпоинтов определяется сортировкой по Z (меньше Z = дальше).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")

local ProgressStore = DataStoreService:GetDataStore("ObbyProgress_v1")

local OBBY = Workspace:WaitForChild("Obby")
local SPAWN = Workspace:WaitForChild("SpawnLocation")

-- Собираем чекпоинты в порядке прохождения (по Z от старта к финишу).
local checkpoints = CollectionService:GetTagged("Checkpoint")
table.sort(checkpoints, function(a, b)
    return a.Position.Z > b.Position.Z
end)

if #checkpoints == 0 then
    warn("[ObbyManager] Не найдено ни одного чекпоинта с тегом Checkpoint")
    return
end

local CHECKPOINT_TOUCH_RADIUS = 6

local playerState = {} -- [player] = { sectionIndex = number, startTime = number|nil, finished = boolean }

-- === Прогресс (DataStore) ===
local function loadProgress(player)
    local ok, result = pcall(function()
        return ProgressStore:GetAsync("p_" .. player.UserId)
    end)
    if ok and type(result) == "number" then
        return math.clamp(result, 1, #checkpoints)
    end
    return 1
end

local function saveProgress(player, index)
    pcall(function()
        ProgressStore:SetAsync("p_" .. player.UserId, index)
    end)
end

local function teleportToCheckpoint(character, index)
    local cp = checkpoints[index]
    local root = character:FindFirstChild("HumanoidRootPart")
    if not (cp and root) then return end
    root.CFrame = CFrame.new(cp.Position + Vector3.new(0, 5, 0))
end

-- === Таймер ===
local function getElapsed(state)
    if not state.startTime then return 0 end
    if state.finished then return state.finishTime - state.startTime end
    return os.clock() - state.startTime
end

-- === Финиш ===
local finishPad = OBBY:FindFirstChild("S9 Finish")
local finishTrigger = finishPad and finishPad:FindFirstChild("Finish Pad")

local function onFinish(player)
    local state = playerState[player]
    if not state or state.finished then return end
    state.finished = true
    state.finishTime = os.clock()

    local elapsed = state.finishTime - (state.startTime or state.finishTime)
    local reward = finishPad and finishPad:GetAttribute("Reward") or 500

    -- Здесь можно начислить валюту: player.leaderstats.Coins.Value += reward
    print(string.format("[Obby] %s финишировал за %.2f c (награда %d)", player.Name, elapsed, reward))

    player:SetAttribute("ObbyTime", elapsed)
    player:SetAttribute("ObbyFinished", true)

    -- отправляем клиенту событие для показа результата
    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("ObbyRemotes")
    if remotes then
        local done = remotes:FindFirstChild("Finished")
        if done then
            done:FireClient(player, elapsed, reward)
        end
    end
end

if finishTrigger then
    finishTrigger.Touched:Connect(function(hit)
        local character = hit:FindFirstAncestorOfClass("Model")
        local player = character and Players:GetPlayerFromCharacter(character)
        if player then onFinish(player) end
    end)
end

-- === Регистрация игрока ===
local function onCharacterAdded(player, character)
    local state = playerState[player]
    local index = state and state.sectionIndex or 1
    teleportToCheckpoint(character, index)

    character:WaitForChild("Humanoid").Died:Connect(function()
        -- при смерти возвращаем на последний чекпоинт
        task.wait(0.1)
        local s = playerState[player]
        if s and not s.finished then
            teleportToCheckpoint(character, s.sectionIndex)
        end
    end)
end

Players.PlayerAdded:Connect(function(player)
    local index = loadProgress(player)
    playerState[player] = { sectionIndex = index, startTime = os.clock(), finished = false }

    player.CharacterAdded:Connect(function(character)
        onCharacterAdded(player, character)
    end)
    if player.Character then
        onCharacterAdded(player, player.Character)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    local state = playerState[player]
    if state and not state.finished and state.sectionIndex > 1 then
        saveProgress(player, state.sectionIndex)
    end
    playerState[player] = nil
end)

-- === Триггеры чекпоинтов ===
for i, cp in ipairs(checkpoints) do
    cp.Touched:Connect(function(hit)
        local character = hit:FindFirstAncestorOfClass("Model")
        local player = character and Players:GetPlayerFromCharacter(character)
        if not player then return end
        local state = playerState[player]
        if not state or state.finished then return end
        if i <= state.sectionIndex then return end

        state.sectionIndex = i
        saveProgress(player, i)

        -- оповещаем клиент для HUD
        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("ObbyRemotes")
        if remotes then
            local changed = remotes:FindFirstChild("CheckpointChanged")
            if changed then
                changed:FireClient(player, i, #checkpoints)
            end
        end
    end)
end
