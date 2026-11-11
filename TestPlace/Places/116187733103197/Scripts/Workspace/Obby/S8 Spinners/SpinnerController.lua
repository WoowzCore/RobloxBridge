--[[
    SpinnerController — секция 8 (Spinners)
    Вращает балки "Beam *" вокруг Hub.
    Скорость — атрибут модели SpeedDeg (град/сек).
]]

local RunService = game:GetService("RunService")

local model = script.Parent
local speedDeg = model:GetAttribute("SpeedDeg") or 90

local hub = model:FindFirstChild("Spinner Hub")
if not hub then return end

local beams = {}
for _, b in ipairs(model:GetChildren()) do
    if b:IsA("BasePart") and b.Name:match("^Beam") then
        table.insert(beams, {
            part = b,
            offset = b.Position - hub.Position,
            angle = 0,
        })
    end
end

RunService.Heartbeat:Connect(function(dt)
    for _, b in ipairs(beams) do
        b.angle += math.rad(speedDeg) * dt
        local rotated = CFrame.Angles(0, b.angle, 0):VectorToWorldSpace(b.offset)
        b.part.CFrame = CFrame.new(hub.Position + rotated) * CFrame.Angles(0, b.angle, 0)
    end
end)
