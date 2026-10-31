local toolbar = plugin:CreateToolbar("RobloxBridge")
local button = toolbar:CreateButton("Test", "Тест", "")

button.Click:Connect(function()
    print("Работает!")
end)