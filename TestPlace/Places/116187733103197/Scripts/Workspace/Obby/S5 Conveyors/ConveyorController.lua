--[[
    ConveyorController — секция 5 (Conveyors)
    Ассинхронно применяет AssemblyLinearVelocity к игрокам, стоящим на Belt.
    Belt A и C гонят вперёд (+Z), Belt B — назад (против движения).
    Скорость — атрибут Speed.
]]

local model = script.Parent
local speed = model:GetAttribute("Speed") or 8

local belts = {}
for _, b in ipairs(model:GetChildren()) do
    if b:IsA("BasePart") and b.Name:match("^Belt") then
        local dir = (b.Name == "Belt B") and -1 or 1
        table.insert(belts, { part = b, dir = dir })
    end
end

local lastTouch = {}
for _, belt in ipairs(belts) do
    belt.part.Touched:Connect(function(hit)
        local humanoid = hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        local root = hit.Parent:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local key = root
        if lastTouch[key] and os.clock() - lastTouch[key] < 0.1 then return end
        lastTouch[key] = os.clock()
        root.AssemblyLinearVelocity += Vector3.new(0, 0, speed * belt.dir)
    end)
end
