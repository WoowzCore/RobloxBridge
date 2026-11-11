--[[
    TileController — секция 7 (Disappearing)
    Плитки с именем "Tile *" исчезают и появляются по таймеру.
    OnTime / OffTime / Offset — атрибуты модели.
    CanCollide выключается, прозрачность плавная.
]]

local TweenService = game:GetService("TweenService")

local model = script.Parent
local onTime = model:GetAttribute("OnTime") or 1.2
local offTime = model:GetAttribute("OffTime") or 0.8
local offset = model:GetAttribute("Offset") or 0.4

local tiles = {}
for _, t in ipairs(model:GetChildren()) do
    if t:IsA("BasePart") and t.Name:match("^Tile") then
        table.insert(tiles, t)
    end
end

local function setTile(tile, visible)
    tile.CanCollide = visible
    TweenService:Create(tile, TweenInfo.new(0.15), {
        Transparency = visible and 0 or 0.85,
    }):Play()
end

task.spawn(function()
    while true do
        for i, tile in ipairs(tiles) do
            local delay = (i - 1) * offset
            task.delay(delay, function()
                setTile(tile, false)
                task.wait(offTime)
                setTile(tile, true)
            end)
        end
        task.wait(onTime + offTime + #tiles * offset)
    end
end)
