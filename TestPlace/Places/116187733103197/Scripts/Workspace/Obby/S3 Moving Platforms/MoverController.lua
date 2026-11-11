--[[
    MoverController — секция 3 (Moving Platforms)
    Двигает части с именем "Mover *" по оси X синусоидой.
    Амплитуда = SpanX/2 атрибута модели, частота = Speed.
]]

local RunService = game:GetService("RunService")

local model = script.Parent
local spanX = model:GetAttribute("SpanX") or 12
local speed = model:GetAttribute("Speed") or 0.35

local movers = {}
for _, child in ipairs(model:GetChildren()) do
    if child:IsA("BasePart") and child.Name:match("^Mover") then
        table.insert(movers, {
            part = child,
            base = child.Position,
            phase = #movers * 0.8,
        })
    end
end

RunService.Heartbeat:Connect(function()
    local t = os.clock() * speed * math.pi
    for _, m in ipairs(movers) do
        local offset = math.sin(t + m.phase) * spanX * 0.5
        m.part.CFrame = CFrame.new(m.base + Vector3.new(offset, 0, 0))
    end
end)
