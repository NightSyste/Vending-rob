if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(1)

getgenv().AutoStartVending = true 

local OrionLib = loadstring(game:HttpGet('https://raw.githubusercontent.com/NightSyste/orion.lua/refs/heads/main/night.lua'))()

local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser         = game:GetService("VirtualUser")
local StarterGui          = game:GetService("StarterGui")
local Workspace           = game:GetService("Workspace")
local TeleportService     = game:GetService("TeleportService")
local HttpService         = game:GetService("HttpService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local RunService          = game:GetService("RunService")

local plr = Players.LocalPlayer

-- Anti-AFK
plr.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
end)

-- Auto-Execute nach Serverhop
local function SetupAutoExecute()
    local queueOnTeleport = (syn and syn.queue_on_teleport)
        or (fluxus and fluxus.queue_on_teleport)
        or (rconsoleinfo and queue_on_teleport)
        or (typeof(queue_on_teleport) == "function" and queue_on_teleport)
        or nil

    if queueOnTeleport then
        queueOnTeleport([[
            wait(8)
            local content = nil
            for i = 1, 5 do
                local ok = pcall(function()
                    content = game:HttpGet("https://raw.githubusercontent.com/NightSyste/Vending-rob/refs/heads/main/rob.lua")
                end)
                if ok and content and content ~= "" then break end
                content = nil
                wait(3)
            end

            if not content then
                game:GetService("Players").LocalPlayer:Kick("Script konnte nicht geladen werden. (Fehler 1)")
                return
            end

            local ok2 = pcall(function()
                loadstring(content)()
            end)
            if not ok2 then
                game:GetService("Players").LocalPlayer:Kick("Script konnte nicht geladen werden. (Fehler 2)")
            end
        ]])
    end
end

SetupAutoExecute()

game:GetService("Players").LocalPlayer.OnTeleport:Connect(function(state)
    if state == Enum.TeleportState.Started then
        SetupAutoExecute()
    end
end)

-- Remotes
local EJw = ReplicatedStorage:WaitForChild("EJw", 10)
local RemoteEvents = {
    RobEvent = EJw and EJw:FindFirstChild("a3126821-130a-4135-80e1-1d28cece4007"),
    SellItem = EJw and EJw:FindFirstChild("eb233e6a-acb9-4169-acb9-129fe8cb06bb"),
}

local VENDING_COLLECT_CODE   = "wRl"
local ProximityPromptTimeBet = 2.5

_G.vendingActive      = false
_G.flightSpeed        = 180 
_G.vendingPoliceRange = 65  
_G.safeFlightHeight   = 250 

local vendingLoopThread    = nil
local instantCollectThread = nil
local espThread            = nil

local teleportActive   = false
local currentTween     = nil
local currentTweenConn = nil

local SERVERHOP_POSITION = CFrame.new(-1292.9, -2, 3685.3)

local Window = OrionLib:MakeWindow({Name = "Vending Rob", SaveConfig = true, ConfigFolder = "VendingConfig"})
local MainTab = Window:MakeTab({Name = "Auto Farm", Icon = "rbxassetid://4483345998"})
local StatusLabel = MainTab:AddLabel("Status: Warte auf Start...")

local function UpdateStatus(text)
    StatusLabel:Set("Status: " .. text)
end

local function getChar()
    local char = plr.Character
    if not char then return nil, nil, nil end
    return char, char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title = title, Text = text, Time = 3})
    end)
end

local function stopCurrentTween()
    teleportActive = false
    if currentTween then pcall(function() currentTween:Cancel() end); currentTween = nil end
    if currentTweenConn then pcall(function() currentTweenConn:Disconnect() end); currentTweenConn = nil end
end

local function isPoliceNearby()
    local _, hum, root = getChar()
    if not root or not hum then return false end
    if hum.Health <= 25 then return true end 

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr and p.Team and (p.Team.Name == "Police" or p.Team.Name == "Sheriff") then
            local pChar = p.Character
            if pChar and pChar:FindFirstChild("HumanoidRootPart") then
                local dist = (pChar.HumanoidRootPart.Position - root.Position).Magnitude
                if dist <= _G.vendingPoliceRange then
                    return true
                end
            end
        end
    end
    return false
end

local function waitForDrops()
    local dropsFolder = Workspace:FindFirstChild("Drops")
    if not dropsFolder then return end
    
    UpdateStatus("Warte auf das Einsammeln...")
    
    local waitTime = 0
    local maxWaitTime = 10
    
    while waitTime < maxWaitTime do
        local hasDrops = false
        local _, _, root = getChar()
        
        if root then
            for _, obj in ipairs(dropsFolder:GetChildren()) do
                if obj:IsA("MeshPart") and obj.Name == plr.Name and obj.Transparency == 0 then
                    if (obj.Position - root.Position).Magnitude <= 35 then
                        hasDrops = true
                        break
                    end
                end
            end
        end
        
        if not hasDrops then break end
        
        task.wait(0.5)
        waitTime = waitTime + 0.5
    end
end

local function doServerHop()
    UpdateStatus("Suche neuen Server...")
    notify("Server Hop", "Suche sicheren Server...")
    task.wait(0.5)

    local success, servers = pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        return HttpService:JSONDecode(game:HttpGet(url)).data
    end)

    if success and servers then
        for _, server in ipairs(servers) do
            if type(server) == "table" and server.playing and server.maxPlayers and server.id then
                if server.playing < (server.maxPlayers - 2) and server.id ~= game.JobId then
                    pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, plr) end)
                    task.wait(2)
                end
            end
        end
    end
    TeleportService:Teleport(game.PlaceId, plr)
end

local function escapePolice()
    _G.vendingActive = false
    UpdateStatus("POLIZEI ENTDECKT! Flucht...")
    stopCurrentTween()
    
    local _, _, root = getChar()
    if root then
        root.CFrame = root.CFrame + Vector3.new(0, 1500, 0)
        root.Anchored = true
    end
    
    task.wait(0.5)
    doServerHop()
end

local function startBackgroundTasks()
    local dropsFolder = Workspace:WaitForChild("Drops", 5)
    local Collected = {}

    while _G.vendingActive do
        local _, _, root = getChar()
        if root and dropsFolder and RemoteEvents.RobEvent then
            for _, obj in ipairs(dropsFolder:GetChildren()) do
                if obj:IsA("MeshPart") and obj.Name == plr.Name and obj.Transparency == 0 and not Collected[obj] then
                    if (obj.Position - root.Position).Magnitude <= 35 then
                        Collected[obj] = true
                        task.spawn(function()
                            pcall(function()
                                RemoteEvents.RobEvent:FireServer(obj, VENDING_COLLECT_CODE, true)
                                task.wait(ProximityPromptTimeBet)
                                RemoteEvents.RobEvent:FireServer(obj, VENDING_COLLECT_CODE, false)
                            end)
                            task.wait(0.3)
                            Collected[obj] = nil
                        end)
                    end
                end
            end
        end

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= plr and p.Team and (p.Team.Name == "Police" or p.Team.Name == "Sheriff") then
                if p.Character then
                    local hl = p.Character:FindFirstChild("CopESP") or Instance.new("Highlight", p.Character)
                    hl.Name = "CopESP"
                    hl.FillColor = Color3.fromRGB(255, 0, 0)
                    hl.FillTransparency = 0.5
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                end
            end
        end

        task.wait(0.2)
    end
end

local function doTween(targetCF, speedModifier)
    local vehicle = Workspace.Vehicles:FindFirstChild(plr.Name)
    if not vehicle or not vehicle.PrimaryPart then return false end

    local distance = (vehicle:GetPivot().Position - targetCF.Position).Magnitude
    local duration = distance / (_G.flightSpeed * (speedModifier or 1))

    local val = Instance.new("CFrameValue")
    val.Value = vehicle:GetPivot()
    
    currentTweenConn = val.Changed:Connect(function(newCF) 
        if vehicle and vehicle.PrimaryPart then vehicle:PivotTo(newCF) else stopCurrentTween() end
    end)
    
    currentTween = TweenService:Create(val, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Value = targetCF})
    currentTween:Play()
    currentTween.Completed:Wait()

    if currentTweenConn then currentTweenConn:Disconnect() end
    val:Destroy()
    return true
end

local function safeTweenTo(targetCF)
    if teleportActive then stopCurrentTween() end
    teleportActive = true

    local _, hum, hrp = getChar()
    local vehicle = Workspace.Vehicles:FindFirstChild(plr.Name)
    if not vehicle then teleportActive = false return false end

    local driveSeat = vehicle:FindFirstChild("DriveSeat", true) or vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
    if not driveSeat then teleportActive = false return false end
    vehicle.PrimaryPart = driveSeat

    if hum and hum.SeatPart ~= driveSeat then
        if hrp then hrp.CFrame = driveSeat.CFrame end
        task.wait(0.1)
        driveSeat:Sit(hum)
        task.wait(0.2)
    end

    UpdateStatus("Hebe ab...")
    local startPos = vehicle:GetPivot().Position
    local skyStartCF = CFrame.new(startPos.X, _G.safeFlightHeight, startPos.Z)
    if not doTween(skyStartCF, 1.5) then teleportActive = false return false end

    UpdateStatus("Fliege über Gebäude...")
    local skyEndCF = CFrame.new(targetCF.Position.X, _G.safeFlightHeight, targetCF.Position.Z)
    if not doTween(skyEndCF, 1) then teleportActive = false return false end

    UpdateStatus("Lande am Ziel...")
    if not doTween(targetCF, 1.5) then teleportActive = false return false end

    teleportActive = false
    return true
end

local function interactWithPrompt(targetPart)
    local prompt = targetPart:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and fireproximityprompt then
        for i = 1, 10 do
             if isPoliceNearby() then escapePolice(); return false end
             fireproximityprompt(prompt, 1)
             task.wait(0.2)
        end
        return true
    end
    
    for i = 1, 10 do
        if isPoliceNearby() then escapePolice(); return false end
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
            task.wait(0.1)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        end)
        task.wait(0.2)
    end
    return false
end

local function VendingRob(targetVending)
    local glass = targetVending:FindFirstChild("Glass")
    if not glass then return false end

    if isPoliceNearby() then escapePolice(); return false end

    local targetPos = glass.Position - glass.CFrame.LookVector * 1.5
    local success = safeTweenTo(CFrame.lookAt(targetPos, glass.Position))
    if not success then return false end

    task.wait(0.3)
    local _, hum, hrp = getChar()
    if hum then hum.Sit = false end
    task.wait(0.2)

    if hrp then
        local tw = TweenService:Create(hrp, TweenInfo.new(0.4, Enum.EasingStyle.Linear), {CFrame = CFrame.lookAt(targetPos, glass.Position)})
        tw:Play()
        tw.Completed:Wait()
    end
    
    task.wait(0.2)
    if isPoliceNearby() then escapePolice(); return false end
    
    UpdateStatus("Knacke Automaten...")
    interactWithPrompt(targetVending)
    waitForDrops()
    
    return true
end

local function findNearestVending()
    local folder = Workspace:FindFirstChild("Robberies") and Workspace.Robberies:FindFirstChild("VendingMachines")
    if not folder then return nil end
    local _, _, root = getChar()
    if not root then return nil end

    local nearest, minDist = nil, math.huge
    for _, model in ipairs(folder:GetChildren()) do
        local light = model:FindFirstChild("Light")
        if light and math.abs(light.Color.R - 73/255) < 0.1 then 
            local dist = (light.Position - root.Position).Magnitude
            if dist < minDist then
                minDist = dist
                nearest = model
            end
        end
    end
    return nearest
end

local function vendingMainLoop()
    while _G.vendingActive do
        if isPoliceNearby() then
            escapePolice()
            break
        end

        local vehicle = Workspace.Vehicles:FindFirstChild(plr.Name)
        if not vehicle then
            UpdateStatus("Kein Auto! Bitte spawne eins.")
            task.wait(3)
            continue
        end

        local target = findNearestVending()
        if not target then
            UpdateStatus("Keine Automaten mehr bereit! ServerHop...")
            safeTweenTo(SERVERHOP_POSITION)
            doServerHop()
            break
        end

        VendingRob(target)
        task.wait(1)
    end
end

local RobToggle = MainTab:AddToggle({
    Name = "Start",
    Default = false,
    Callback = function(Value)
        _G.vendingActive = Value
        if Value then
            if vendingLoopThread then task.cancel(vendingLoopThread) end
            if instantCollectThread then task.cancel(instantCollectThread) end
            
            vendingLoopThread = task.spawn(vendingMainLoop)
            instantCollectThread = task.spawn(startBackgroundTasks)
            notify("Rob", "rob start")
        else
            UpdateStatus("Pausiert.")
            if vendingLoopThread then task.cancel(vendingLoopThread); vendingLoopThread = nil end
            if instantCollectThread then task.cancel(instantCollectThread); instantCollectThread = nil end
            stopCurrentTween()
            notify("Rob", "rob gestoppt")
        end
    end
})

MainTab:AddSlider({
    Name = "geschwindigkeit",
    Min = 150, Max = 200, Default = 180,
    Callback = function(Value) _G.flightSpeed = Value end
})

MainTab:AddSlider({
    Name = "Flughöhe",
    Min = 0, Max = 50, Default = 0,
    Callback = function(Value) _G.safeFlightHeight = Value end
})

MainTab:AddSlider({
    Name = "Polizei Radius",
    Min = 20, Max = 300, Default = 70,
    Callback = function(Value) _G.vendingPoliceRange = Value end
})

OrionLib:Init()

if getgenv().AutoStartVending then
    task.wait(2)
    RobToggle:Set(true)
end
