if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(1) -- Kleiner Puffer für Charakter-Load

-- ============================================================
-- EINSTELLUNGEN
-- ============================================================
getgenv().AutoStartVending = true -- Setze auf false, wenn er nicht direkt nach dem Injecten starten soll

local OrionLib = loadstring(game:HttpGet('https://raw.githubusercontent.com/NightSyste/orion.lua/refs/heads/main/night.lua'))()

local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui          = game:GetService("StarterGui")
local Workspace           = game:GetService("Workspace")
local TeleportService     = game:GetService("TeleportService")
local HttpService         = game:GetService("HttpService")

local queue_on_teleport = syn and syn.queue_on_teleport or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)

local plr = Players.LocalPlayer

local EJw = game:GetService("ReplicatedStorage"):WaitForChild("EJw")
local RemoteEvents = {
    RobEvent = EJw:WaitForChild("a3126821-130a-4135-80e1-1d28cece4007"),
    SellItem = EJw:WaitForChild("eb233e6a-acb9-4169-acb9-129fe8cb06bb"),
}

local VENDING_COLLECT_CODE   = "wRl"
local ProximityPromptTimeBet = 2.5

_G.vendingActive      = false
_G.flightSpeed        = 160
_G.vendingPoliceRange = 55

local vendingLoopThread    = nil
local instantCollectThread = nil

local teleportActive   = false
local currentTween     = nil
local currentTweenConn = nil

local SERVERHOP_POSITION = Vector3.new(-1292.9005126953125, -2, 3685.330810546875)

-- ============================================================
-- HILFSFUNKTIONEN
-- ============================================================
local function getChar()
    local char = plr.Character
    if not char then return nil, nil, nil end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    return char, hum, root
end

local function notify(title, text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text  = text,
            Time  = 3
        })
    end)
end

local function stopCurrentTween()
    if currentTween then pcall(function() currentTween:Cancel() end); currentTween = nil end
    if currentTweenConn then pcall(function() currentTweenConn:Disconnect() end); currentTweenConn = nil end
    teleportActive = false
end

local function isPoliceNearby()
    local _, _, root = getChar()
    if not root then return false end
    local hum = root.Parent:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 25 then return true end -- Auto-Escape bei Low HP

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr and p.Team and p.Team.Name == "Police" then
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

-- ============================================================
-- SERVERHOP & ESCAPE LOGIK
-- ============================================================
local function doServerHop()
    notify("Server Hop", "Suche sicheren Server...")
    task.wait(0.5)

    -- Wenn du das Skript im Autoexec-Ordner deines Executors hast, startet es nach dem Hop von selbst.
    local success, servers = pcall(function()
        return HttpService:JSONDecode(
            game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
        ).data
    end)

    if success and servers then
        for _, server in ipairs(servers) do
            if type(server) == "table" and server.playing and server.maxPlayers and server.id then
                -- Sucht Server, die nicht voll sind und nicht der aktuelle Server
                if server.playing < (server.maxPlayers - 1) and server.id ~= game.JobId then
                    pcall(function()
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, plr)
                    end)
                    task.wait(2) -- Warte kurz, ob Teleport klappt
                end
            end
        end
    end

    -- Fallback, falls die API zickt
    TeleportService:Teleport(game.PlaceId, plr)
end

local function escapePolice()
    _G.vendingActive = false -- Stoppt vorerst alle anderen Aktionen
    notify("Polizei Entdeckt!", "Flucht wird eingeleitet...")
    stopCurrentTween()
    
    local _, _, root = getChar()
    if root then
        -- Teleportiert dich in den Himmel und friert dich ein, damit du nicht fällst
        root.CFrame = root.CFrame + Vector3.new(0, 800, 0)
        root.Anchored = true
    end
    
    task.wait(0.5)
    doServerHop()
end

-- ============================================================
-- AUTO COLLECT LOGIK (Hintergrund)
-- ============================================================
local function startAutoCollect()
    local myName = plr.Name
    local dropsFolder = Workspace:WaitForChild("Drops", 5)
    if not dropsFolder then return end
    
    local Collected = {}

    local function collectDrop(obj)
        if Collected[obj] or obj.Transparency ~= 0 then return end
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

    while _G.vendingActive do
        local _, _, root = getChar()
        if root then
            for _, obj in ipairs(dropsFolder:GetChildren()) do
                if obj:IsA("MeshPart") and obj.Name == myName and (obj.Position - root.Position).Magnitude <= 35 then
                    collectDrop(obj)
                end
            end
        end
        task.wait(0.2)
    end
end

-- ============================================================
-- TWEEN & MOVEMENT
-- ============================================================
local function tweenTo(destination)
    if teleportActive then stopCurrentTween() end
    teleportActive = true

    local char, hum, hrp = getChar()
    local vehicle = Workspace.Vehicles:FindFirstChild(plr.Name)
    if not vehicle then teleportActive = false return false end

    local driveSeat = vehicle:FindFirstChild("DriveSeat", true) or vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
    if not driveSeat then teleportActive = false return false end
    vehicle.PrimaryPart = driveSeat

    -- Sicherstellen, dass man sitzt
    if hum and hum.SeatPart ~= driveSeat then
        if hrp then hrp.CFrame = driveSeat.CFrame end
        task.wait(0.1)
        driveSeat:Sit(hum)
        task.wait(0.1)
    end

    local targetCF = (typeof(destination) == "CFrame") and destination or CFrame.new(destination)
    local duration = (vehicle:GetPivot().Position - targetCF.Position).Magnitude / _G.flightSpeed

    local val = Instance.new("CFrameValue")
    val.Value = vehicle:GetPivot()
    
    currentTweenConn = val.Changed:Connect(function(newCF) 
        if vehicle and vehicle.PrimaryPart then
            vehicle:PivotTo(newCF) 
        else
            stopCurrentTween() -- Abbruch, falls Auto despawnt
        end
    end)
    
    currentTween = TweenService:Create(val, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Value = targetCF})
    currentTween:Play()
    currentTween.Completed:Wait()

    if currentTweenConn then currentTweenConn:Disconnect() end
    val:Destroy()
    teleportActive = false
    return true
end

local function plrTween(targetCFrame)
    local _, _, root = getChar()
    if not root then return end
    local tw = TweenService:Create(root, TweenInfo.new(0.4, Enum.EasingStyle.Linear), {CFrame = targetCFrame})
    tw:Play()
    tw.Completed:Wait()
end

-- ============================================================
-- VENDING RAUB LOGIK
-- ============================================================
local function VendingRob(targetVending)
    local glass = targetVending:FindFirstChild("Glass")
    if not glass then return false end

    if isPoliceNearby() then escapePolice(); return false end

    local targetPos = glass.Position - glass.CFrame.LookVector * 1.5
    local success = tweenTo(CFrame.lookAt(targetPos, glass.Position))
    if not success then return false end

    task.wait(0.3)
    local _, hum = getChar()
    if hum then hum.Sit = false end
    task.wait(0.5)

    plrTween(CFrame.lookAt(glass.Position - glass.CFrame.LookVector * 1.5, glass.Position))
    task.wait(0.3)

    for i = 1, 10 do
        if isPoliceNearby() then 
            escapePolice() 
            return false 
        end
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
            task.wait(0.1)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        end)
        task.wait(0.3)
    end

    task.wait(0.5)
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

-- ============================================================
-- MAIN LOOP
-- ============================================================
local function vendingMainLoop()
    while _G.vendingActive do
        if isPoliceNearby() then
            escapePolice()
            break
        end

        local vehicle = Workspace.Vehicles:FindFirstChild(plr.Name)
        if not vehicle then
            notify("Vehicle", "Bitte spawne ein Auto! Warte...")
            task.wait(3)
            continue
        end

        local target = findNearestVending()
        if not target then
            tweenTo(CFrame.new(SERVERHOP_POSITION))
            doServerHop()
            break
        end

        VendingRob(target)
        task.wait(1)
    end
end

-- ============================================================
-- UI SETUP (Orion)
-- ============================================================
local Window = OrionLib:MakeWindow({Name = "Vending Rob Pro", SaveConfig = true, ConfigFolder = "VendingConfig"})
local MainTab = Window:MakeTab({Name = "Main"})

local RobToggle = MainTab:AddToggle({
    Name = "Activate Vending Rob",
    Default = false,
    Callback = function(Value)
        _G.vendingActive = Value
        if Value then
            -- Verhindert, dass die Schleife mehrfach gestartet wird
            if vendingLoopThread then task.cancel(vendingLoopThread) end
            if instantCollectThread then task.cancel(instantCollectThread) end
            
            vendingLoopThread = task.spawn(vendingMainLoop)
            instantCollectThread = task.spawn(startAutoCollect)
            notify("System", "Bot gestartet!")
        else
            if vendingLoopThread then task.cancel(vendingLoopThread); vendingLoopThread = nil end
            if instantCollectThread then task.cancel(instantCollectThread); instantCollectThread = nil end
            stopCurrentTween()
            notify("System", "Bot gestoppt!")
        end
    end
})

MainTab:AddSlider({
    Name = "Flight Speed",
    Min = 50, Max = 300, Default = 160,
    Callback = function(Value) _G.flightSpeed = Value end
})

MainTab:AddSlider({
    Name = "Police Detection Range",
    Min = 20, Max = 200, Default = 55,
    Callback = function(Value) _G.vendingPoliceRange = Value end
})

OrionLib:Init()

-- AUTO EXECUTE LOGIK
if getgenv().AutoStartVending then
    task.wait(2) -- Wartet kurz, bis das UI geladen ist
    RobToggle:Set(true) -- Schaltet den Toggle automatisch im UI an
end
