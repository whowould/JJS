local genv = (type(getgenv) == "function" and getgenv()) or _G or shared or {}
if type(genv.JJSCleanup) == "function" then
    pcall(function() genv.JJSCleanup() end)
end

local Running = true
local Connections = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local State = {
    NoStun = false,
    NoRagdoll = false,
    InfEvade = false,
    M1Unlock = false,
    Speed = false,
    SpeedVal = 32,
    DashDelay = 0,
    DashSpeed = 160,
}

local EVADE_MAX = 50
local Remotes = { Dash = nil, M1 = nil, Activated = nil }
local LastDash, LastM1, LastRemoteScan = 0, 0, 0
local Cache = { char = nil, hum = nil, hrp = nil, info = nil, at = 0 }

local function Dbg(...)
    local t = { ... }
    for i = 1, #t do t[i] = tostring(t[i]) end
    print("[JJS]", table.concat(t, " "))
end

local function RefreshCache()
    local char = LocalPlayer and LocalPlayer.Character
    if not char then
        local folder = workspace:FindFirstChild("Characters")
        local name = LocalPlayer and LocalPlayer.Name
        char = folder and name and folder:FindFirstChild(name)
    end
    Cache.char = char
    Cache.hum = char and char:FindFirstChild("Humanoid")
    Cache.hrp = char and char:FindFirstChild("HumanoidRootPart")
    Cache.info = char and char:FindFirstChild("Info")
    Cache.at = tick()
    return char
end

local function GetChar()
    if Cache.char and (tick() - Cache.at) < 0.5 then
        return Cache.char
    end
    return RefreshCache()
end

local function SetAttr(inst, name, val)
    if inst then
        pcall(function() inst:SetAttribute(name, val) end)
    end
end

local function Pressed(vk)
    local ok, v = pcall(iskeypressed, vk)
    return ok and v == true
end

local function ScanRemotes()
    if Remotes.Dash and Remotes.Activated and (tick() - LastRemoteScan) < 8 then
        return
    end
    LastRemoteScan = tick()
    pcall(function()
        local knit = game:GetService("ReplicatedStorage"):FindFirstChild("Knit")
        knit = knit and (knit:FindFirstChild("Knit") or knit)
        local sv = knit and knit:FindFirstChild("Services")
        if not sv then return end
        local re = sv.MovementService and sv.MovementService:FindFirstChild("RE")
        if re then Remotes.Dash = re:FindFirstChild("Dash") end
        local ire = sv.ItemService and sv.ItemService:FindFirstChild("RE")
        if ire then Remotes.M1 = ire:FindFirstChild("M1") end
        local setName = Cache.char and Cache.char:GetAttribute("Moveset")
        if type(setName) == "string" then
            local svc = sv:FindFirstChild(setName .. "Service")
            local sre = svc and svc:FindFirstChild("RE")
            if sre then
                Remotes.Activated = sre:FindFirstChild("Activated")
            end
        end
    end)
end

local function FireRE(re, a, b)
    if not re or not re.FireServer then return end
    pcall(function()
        if b ~= nil then
            re:FireServer(a, b)
        elseif a ~= nil then
            re:FireServer(a)
        else
            re:FireServer()
        end
    end)
end

local function ClosestTarget(hrp)
    local folder = workspace:FindFirstChild("Characters")
    if not folder or not hrp then return nil end
    local best, bestD = nil, 80
    local myName = LocalPlayer.Name
    local kids = folder:GetChildren()
    for i = 1, #kids do
        local other = kids[i]
        if other.Name ~= myName then
            local ohrp = other:FindFirstChild("HumanoidRootPart")
            if ohrp then
                local d = (ohrp.Position - hrp.Position).Magnitude
                if d < bestD then
                    bestD = d
                    best = other
                end
            end
        end
    end
    return best
end

local function CombatTick()
    local char = GetChar()
    if not char then return end
    ScanRemotes()

    if State.NoStun then
        SetAttr(char, "Stun", false)
        local stun = Cache.info and Cache.info:FindFirstChild("Stun")
        if stun and stun.ClassName == "BoolValue" then
            pcall(function() stun.Value = false end)
        end
    end

    if State.NoRagdoll then
        if char:GetAttribute("Ragdoll") ~= 0 then
            SetAttr(char, "Ragdoll", 0)
            local hum = Cache.hum
            if hum then
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                end)
            end
        end
    end

    if State.InfEvade then
        if char:GetAttribute("Evade") ~= EVADE_MAX then
            SetAttr(char, "Evade", EVADE_MAX)
        end
    end

    if State.M1Unlock then
        local now = tick()
        SetAttr(char, "LastM1", now - 10)
        SetAttr(char, "M2_CD", 0)
        local lmb = false
        pcall(function() lmb = ismouse1pressed() end)
        if lmb and (tick() - LastM1) >= 0.12 then
            LastM1 = tick()
            local hum = Cache.hum
            local dir = nil
            if hum then
                local air = false
                pcall(function() air = hum.FloorMaterial == Enum.Material.Air end)
                if air then dir = "Down" end
            end
            FireRE(Remotes.Activated, dir, ClosestTarget(Cache.hrp))
        end
    end
end

local function TryDash()
    if not State.InfEvade then return end
    if not (Pressed(0x51) or Pressed(0x45)) then return end
    local delay = State.DashDelay
    if delay < 0 then delay = 0 end
    local bursts = 1
    if delay <= 0 then
        bursts = 3
    elseif delay < 0.02 then
        bursts = 2
    end
    if tick() - LastDash < delay then return end
    LastDash = tick()
    if not Cache.hrp then RefreshCache() end
    local name = "Front"
    if Pressed(0x53) then
        name = "Back"
    elseif Pressed(0x41) then
        name = "Left"
    elseif Pressed(0x44) then
        name = "Right"
    end
    local hrp = Cache.hrp
    local cam = workspace.CurrentCamera
    local look = cam and cam.CFrame and cam.CFrame.LookVector
    local dir = look and Vector3.new(look.X, 0, look.Z)
    if dir and dir.Magnitude > 0.05 then
        dir = dir.Unit
        if name == "Back" then dir = -dir end
    else
        dir = nil
    end
    local push = State.DashSpeed
    for _ = 1, bursts do
        FireRE(Remotes.Dash, name)
        if hrp and dir then
            local vel = hrp.AssemblyLinearVelocity
            hrp.AssemblyLinearVelocity = Vector3.new(dir.X * push, vel.Y, dir.Z * push)
        end
    end
end

local SpeedAcc = 0
local function SpeedFrame(dt)
    TryDash()
    if not State.Speed then return end
    SpeedAcc = SpeedAcc + dt
    if SpeedAcc < 0.05 then return end
    SpeedAcc = 0
    local hrp = Cache.hrp
    if not hrp then
        RefreshCache()
        hrp = Cache.hrp
        if not hrp then return end
    end
    local vel = hrp.AssemblyLinearVelocity
    local hx, hz = vel.X, vel.Z
    local mag = math.sqrt(hx * hx + hz * hz)
    if mag < 2 then return end
    local spd = State.SpeedVal
    if mag >= spd then return end
    local s = spd / mag
    hrp.AssemblyLinearVelocity = Vector3.new(hx * s, vel.Y, hz * s)
end

local function SyncUi()
    if not (UI and UI.GetValue) then return end
    local function b(id, cur)
        local v = UI.GetValue(id)
        if v == nil then return cur end
        return v and true or false
    end
    State.NoStun = b("jjs_nostun", State.NoStun)
    State.NoRagdoll = b("jjs_noragdoll", State.NoRagdoll)
    State.InfEvade = b("jjs_infevade", State.InfEvade)
    State.M1Unlock = b("jjs_m1", State.M1Unlock)
    State.Speed = b("jjs_speed", State.Speed)
    local sv = UI.GetValue("jjs_speedval")
    if type(sv) == "number" then State.SpeedVal = sv end
    local dd = UI.GetValue("jjs_dashdelay")
    if type(dd) == "number" then
        State.DashDelay = dd / 1000
    end
    local ds = UI.GetValue("jjs_dashspd")
    if type(ds) == "number" then
        State.DashSpeed = ds
    end
end

genv.JJSCleanup = function()
    Running = false
    State.NoStun = false
    State.NoRagdoll = false
    State.InfEvade = false
    State.M1Unlock = false
    State.Speed = false
    for i = 1, #Connections do
        pcall(function() Connections[i]:Disconnect() end)
    end
    Connections = {}
    pcall(function()
        if UI and UI.RemoveTab then UI.RemoveTab("JJS") end
    end)
    Dbg("cleaned")
end

pcall(function()
    Connections[#Connections + 1] = RunService.Heartbeat:Connect(function(dt)
        if Running then SpeedFrame(dt) end
    end)
end)

task.spawn(function()
    while Running do
        CombatTick()
        task.wait(0.1)
    end
end)

task.spawn(function()
    while Running do
        pcall(SyncUi)
        task.wait(0.25)
    end
end)

pcall(function()
    if UI and UI.RemoveTab then UI.RemoveTab("JJS") end
end)

if UI and UI.AddTab then
    UI.AddTab("JJS", function(tab)
        local combat = tab:Section("Combat", "Left")
        combat:Toggle("jjs_nostun", "NoStun", false, function(v)
            State.NoStun = v and true or false
        end)
        combat:Toggle("jjs_noragdoll", "No Ragdoll", false, function(v)
            State.NoRagdoll = v and true or false
        end)
        combat:Toggle("jjs_infevade", "Inf Evade / Dash", false, function(v)
            State.InfEvade = v and true or false
        end)
        combat:Tip("Hold Q or E")
        combat:SliderInt("jjs_dashdelay", "Dash Delay ms", 0, 120, 0, function(val)
            State.DashDelay = val / 1000
        end)
        combat:SliderInt("jjs_dashspd", "Dash Speed", 80, 250, 160, function(val)
            State.DashSpeed = val
        end)
        combat:Toggle("jjs_m1", "M1 Chain Unlock", false, function(v)
            State.M1Unlock = v and true or false
        end)
        combat:Tip("Hold LMB")

        local move = tab:Section("Movement", "Right")
        move:Toggle("jjs_speed", "Speed", false, function(v)
            State.Speed = v and true or false
        end)
        move:SliderInt("jjs_speedval", "Speed Value", 20, 80, 32, function(val)
            State.SpeedVal = val
        end)
    end)
    pcall(function()
        UI.SetValue("jjs_nostun", false)
        UI.SetValue("jjs_noragdoll", false)
        UI.SetValue("jjs_infevade", false)
        UI.SetValue("jjs_m1", false)
        UI.SetValue("jjs_speed", false)
        UI.SetValue("jjs_speedval", 32)
        UI.SetValue("jjs_dashdelay", 0)
        UI.SetValue("jjs_dashspd", 160)
    end)
    Dbg("ready JJS v4")
else
    Dbg("ready v4 (no UI)")
end
