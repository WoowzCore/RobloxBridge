--[[
    HudController — клиентский HUD
    * Таймер прохождения
    * Отображение текущей секции
    * Окно результатов на финише
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = script.Parent
local timerLabel = gui:WaitForChild("Panel"):WaitForChild("Timer")
local sectionLabel = gui:WaitForChild("Panel"):WaitForChild("Section")

local remotes = ReplicatedStorage:WaitForChild("ObbyRemotes")
local checkpointChanged = remotes:WaitForChild("CheckpointChanged")
local finished = remotes:WaitForChild("Finished")

local startedAt = os.clock()
local finishedTime = nil
local totalSections = 9

local function formatTime(sec)
    local m = math.floor(sec / 60)
    local s = math.floor(sec % 60)
    local ms = math.floor((sec * 100) % 100)
    return string.format("%02d:%02d.%02d", m, s, ms)
end

-- Таймер: отдельный поток с корректным закрытием task.spawn(...)
task.spawn(function()
    while true do
        local elapsed = finishedTime or (os.clock() - startedAt)
        timerLabel.Text = formatTime(elapsed)
        task.wait(0.03)
    end
end)

checkpointChanged.OnClientEvent:Connect(function(index, total)
    totalSections = total or totalSections
    sectionLabel.Text = string.format("Секция %d / %d", index, totalSections)
end)

finished.OnClientEvent:Connect(function(elapsed, reward)
    finishedTime = elapsed

    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(0, 360, 0, 140)
    panel.Position = UDim2.new(0.5, -180, 0.3, 0)
    panel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    panel.BorderSizePixel = 0
    panel.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = panel

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(77, 107, 254)
    stroke.Thickness = 2
    stroke.Parent = panel

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.BackgroundTransparency = 1
    title.Text = "ФИНИШ!"
    title.TextColor3 = Color3.fromRGB(77, 107, 254)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 28
    title.Parent = panel

    local result = Instance.new("TextLabel")
    result.Size = UDim2.new(1, 0, 0, 60)
    result.Position = UDim2.new(0, 0, 0, 46)
    result.BackgroundTransparency = 1
    result.Text = string.format("Время: %s\nНаграда: %d", formatTime(elapsed), reward)
    result.TextColor3 = Color3.fromRGB(13, 13, 13)
    result.Font = Enum.Font.Gotham
    result.TextSize = 18
    result.TextWrapped = true

