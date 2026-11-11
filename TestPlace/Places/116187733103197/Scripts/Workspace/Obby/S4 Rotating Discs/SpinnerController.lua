--[[
    SpinnerController — секция 4 (Rotating Discs)
    Вращает части с именем "Disc" вокруг Y.
    Скорость — атрибут модели SpeedDeg (град/сек).
]]

local RunService = game:GetService("RunService")

local model = script.Parent
local speedDeg = model:GetAttribute("SpeedDeg") or 45

local discs = {}
for _, d in ipairs(model:GetChildren()) do
    if d:IsA("Model") then
        local disc = d:FindFirstChild("Disc")
        if disc then
            table.insert(discs, { part = disc, angle = 0 })
        end
    end
end

RunService.Heartbeat:Connect(function(dt)
    for _, d in ipairs(discs) do
        d.angle += math.rad(speedDeg) * dt
        d.part.CFrame = CFrame.new(d.part.Position) * CFrame.Angles(0, d.angle, 0)
    end
end)
