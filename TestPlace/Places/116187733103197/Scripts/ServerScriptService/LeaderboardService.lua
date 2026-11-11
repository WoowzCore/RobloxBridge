--[[
    LeaderboardService
    ------------------
    DataStore + OrderedDataStore для лучшего времени прохождения.

    Хранит:
      * PersonalBest_v1 (DataStore) — лучшее время игрока
      * GlobalTimes_v1 (OrderedDataStore) — глобальный топ

    Требует Studio Access to API Services. Вне Studio работает по умолчанию.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PersonalBest = DataStoreService:GetDataStore("PersonalBest_v1")
local GlobalTimes = DataStoreService:GetOrderedDataStore("GlobalTimes_v1")

-- === Remotes ===
local remotes = Instance.new("Folder")
remotes.Name = "ObbyRemotes"
remotes.Parent = ReplicatedStorage

local finished = Instance.new("RemoteEvent")
finished.Name = "Finished"
finished.Parent = remotes

local checkpointChanged = Instance.new("RemoteEvent")
checkpointChanged.Name = "CheckpointChanged"
checkpointChanged.Parent = remotes

local requestTop = Instance.new("RemoteFunction")
requestTop.Name = "RequestTop"
requestTop.Parent = remotes

-- === Сохранение времени ===
finished.OnServerEvent:Connect(function(player, elapsed)
    if type(elapsed) ~= "number" or elapsed <= 0 then return end

    -- личный рекорд
    local key = "p_" .. player.UserId
    local ok, best = pcall(function() return PersonalBest:GetAsync(key) end)
    if not ok then
        warn("[Leaderboard] Не удалось прочитать личный рекорд: " .. tostring(best))
    elseif best == nil or elapsed < best then
        pcall(function() PersonalBest:SetAsync(key, elapsed) end)
    end

    -- глобальный топ (ключ = userId, значение = миллисекунды, чтобы хранить целое)
    pcall(function()
        GlobalTimes:SetAsync(tostring(player.UserId), math.floor(elapsed * 1000))
    end)
end)

-- === Запрос топа с клиента ===
requestTop.OnServerInvoke = function(player, count)
    count = math.clamp(tonumber(count) or 10, 1, 50)

    local ok, pages = pcall(function()
        return GlobalTimes:GetSortedAsync(false, count) -- false = по возрастанию (лучшие сверху)
    end)
    if not ok or not pages then return {} end

    local results = {}
    for _, entry in ipairs(pages:GetCurrentPage()) do
        local uid = tonumber(entry.key)
        local name = uid and (pcall(function() return Players:GetNameFromUserIdAsync(uid) end) and
            Players:GetNameFromUserIdAsync(uid)) or "?"
        table.insert(results, {
            name = name,
            time = entry.value / 1000,
        })
    end
    return results
end
