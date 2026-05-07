-- Universal Roblox Script Decompiler
-- Works with most executors: Solara, Fluxus, Delta, etc.
-- Dumps all LocalScripts and ModuleScripts to readable Lua
-- Includes real-time GUI progress tracking

local success, result = pcall(function()
    print("[MYSTRY Decompiler] Starting...")

    -- ========================================
    -- GUI SETUP
    -- ========================================
    local player = game.Players.LocalPlayer
    local pGui = player:WaitForChild("PlayerGui")
    
    -- Cleanup existing
    if pGui:FindFirstChild("MYSTRY_Decompiler") then
        pGui.MYSTRY_Decompiler:Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MYSTRY_Decompiler"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = pGui
    if protectgui then protectgui(screenGui) end

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 350, 0, 200)
    mainFrame.Position = UDim2.new(0.5, -175, 0.5, -100)
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = mainFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 180, 255)
    stroke.Thickness = 2
    stroke.Parent = mainFrame

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 0, 35)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "MYSTRY Decompiler"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 18
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Parent = mainFrame

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "Status"
    statusLabel.Size = UDim2.new(1, -20, 0, 25)
    statusLabel.Position = UDim2.new(0, 10, 0, 45)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Scanning game scripts..."
    statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    statusLabel.TextSize = 14
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = mainFrame

    local progressBarBg = Instance.new("Frame")
    progressBarBg.Name = "ProgressBarBg"
    progressBarBg.Size = UDim2.new(1, -20, 0, 12)
    progressBarBg.Position = UDim2.new(0, 10, 0, 80)
    progressBarBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    progressBarBg.BorderSizePixel = 0
    progressBarBg.Parent = mainFrame
    Instance.new("UICorner").Parent = progressBarBg

    local progressBarFill = Instance.new("Frame")
    progressBarFill.Name = "ProgressBarFill"
    progressBarFill.Size = UDim2.new(0, 0, 1, 0)
    progressBarFill.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
    progressBarFill.BorderSizePixel = 0
    progressBarFill.Parent = progressBarBg
    Instance.new("UICorner").Parent = progressBarFill

    local scriptCounter = Instance.new("TextLabel")
    scriptCounter.Name = "Counter"
    scriptCounter.Size = UDim2.new(1, -20, 0, 25)
    scriptCounter.Position = UDim2.new(0, 10, 0, 100)
    scriptCounter.BackgroundTransparency = 1
    scriptCounter.Text = "Scripts: 0 / 0 (0%)"
    scriptCounter.TextColor3 = Color3.fromRGB(150, 150, 150)
    scriptCounter.TextSize = 13
    scriptCounter.Font = Enum.Font.Gotham
    scriptCounter.TextXAlignment = Enum.TextXAlignment.Left
    scriptCounter.Parent = mainFrame

    local outputText = Instance.new("TextBox")
    outputText.Name = "OutputLog"
    outputText.Size = UDim2.new(1, -20, 0, 50)
    outputText.Position = UDim2.new(0, 10, 0, 130)
    outputText.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    outputText.BorderSizePixel = 0
    outputText.Text = ""
    outputText.TextColor3 = Color3.fromRGB(180, 180, 180)
    outputText.TextSize = 11
    outputText.Font = Enum.Font.GothamMono
    outputText.TextWrapped = true
    outputText.ClearTextOnFocus = false
    outputText.TextEditable = false
    outputText.Parent = mainFrame
    Instance.new("UICorner").Parent = outputText

    local function log(msg, color)
        statusLabel.Text = msg
        if color then statusLabel.TextColor3 = color end
        outputText.Text = msg .. "\n" .. outputText.Text
        wait()
    end

    local function updateProgress(current, total)
        local pct = total > 0 and (current / total * 100) or 0
        progressBarFill.Size = UDim2.new(pct / 100, 0, 1, 0)
        scriptCounter.Text = string.format("Scripts: %d / %d (%.1f%%)", current, total, pct)
    end

    -- ========================================
    -- DECOMPILER LOGIC
    -- ========================================
    local function getDecompiler()
        if decompile then
            return decompile
        elseif dump_scripts or dumpscript then
            return dump_scripts or dumpscript
        elseif getsenv then
            return function(script)
                local env = getsenv(script)
                return env and tostring(env) or "-- No source available"
            end
        end
        return nil
    end

    local decompiler = getDecompiler()
    if not decompiler then
        log("No decompiler API found! (Use Solara/Fluxus)", Color3.fromRGB(255, 80, 80))
        wait(5)
        screenGui:Destroy()
        return
    end

    log("Scanning game scripts...", Color3.fromRGB(255, 255, 255))
    
    local scripts = {}
    for _, obj in ipairs(game:GetDescendants()) do
        if obj:IsA("LocalScript") or obj:IsA("ModuleScript") then
            table.insert(scripts, obj)
        end
    end

    log(string.format("Found %d scripts. Starting decompile...", #scripts), Color3.fromRGB(255, 200, 0))
    updateProgress(0, #scripts)

    local output = "-- Decompiled by MYSTRY | Join discord.gg/Mppf6wXe\n-- Game: " .. game.Name .. "\n-- PlaceId: " .. game.PlaceId .. "\n-- Date: " .. tostring(os.date()) .. "\n\n"
    local count = 0
    local failed = 0

    for i, script in ipairs(scripts) do
        local name = script:GetFullName()
        output = output .. "-- ========================================\n"
        output = output .. "-- Script: " .. name .. "\n"
        output = output .. "-- Type: " .. script.ClassName .. "\n"
        output = output .. "-- ========================================\n"

        local ok, source = pcall(function()
            return decompiler(script)
        end)

        if ok and source and source ~= "" then
            output = output .. tostring(source) .. "\n\n"
            count = count + 1
            log(string.format("[OK] %s", name), Color3.fromRGB(100, 255, 100))
        else
            output = output .. "-- Failed to decompile (protected/empty)\n\n"
            failed = failed + 1
            log(string.format("[FAIL] %s", name), Color3.fromRGB(255, 100, 100))
        end
        updateProgress(i, #scripts)
    end

    output = output .. string.format("\n-- Total: %d scripts | Success: %d | Failed: %d\n", #scripts, count, failed)

    log("Writing file...", Color3.fromRGB(0, 200, 255))
    
    if writefile then
        local filename = string.format("decompiled_%s_%s.lua", game.PlaceId, game.Name:gsub("[^%w%s]", ""))
        writefile(filename, output)
        log(string.format("Saved! %s (%d success, %d failed)", filename, count, failed), Color3.fromRGB(100, 255, 100))
    elseif setclipboard then
        setclipboard(output)
        log("Copied to clipboard!", Color3.fromRGB(100, 255, 100))
    else
        log("No save method available!", Color3.fromRGB(255, 80, 80))
    end

    -- Auto-close after 5 seconds
    wait(5)
    screenGui:Destroy()
end)

if not success then
    print("[MYSTRY Decompiler] Error: " .. tostring(result))
end
