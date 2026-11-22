--[[
  Blackgg - Blox Fruits Script
  Sistema de Key (Discord Bot / ZVC Panel) + Auto Farm + ESP Frutas + Kaitun + Girar Frutas

  Loader:
  loadstring(game:HttpGet("https://raw.githubusercontent.com/SEU_USUARIO/SEU_REPO/main/blackgg_bloxfruits.lua"))()
]]

-- =========================
-- CONFIG
-- =========================
local CONFIG = {
    PANEL_URL = "https://zvc-blackgg-panel.ophl.link",
    APP = "script",
    KEY = "", -- opcional: fixe sua key aqui
    KEY_FILE = "blackgg_bloxfruits_key.txt",
    HEARTBEAT_SECONDS = 60,
    AUTO_SAVE_KEY = true,
    UI_NAME = "Blackgg",
}

-- =========================
-- SERVICES
-- =========================
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- =========================
-- STATE
-- =========================
local State = {
    AutoFarm = false,
    ESPFruits = false,
    ESPPlayers = false,
    Kaitun = false,
    AutoSpinFruit = false,
    FarmSpeed = 300,
    FarmDistance = 8,
    AttackDelay = 0.12,
    SpinDelay = 2.5,
    SelectedFruit = "Random",
}

local Connections = {}
local ESPObjects = {}
local UIRefs = {}

-- =========================
-- UTIL
-- =========================
local function log(msg, kind)
    kind = kind or "info"
    local prefix = "[Blackgg]"
    if kind == "ok" then print(prefix, "✅", msg)
    elseif kind == "warn" then warn(prefix, "⚠️", msg)
    elseif kind == "err" then warn(prefix, "❌", msg)
    else print(prefix, msg) end
end

local function notify(text)
    log(text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Blackgg",
            Text = tostring(text),
            Duration = 3
        })
    end)
end

local function safeReadFile(path)
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return nil end
    local ok, exists = pcall(isfile, path)
    if not ok or not exists then return nil end
    local ok2, data = pcall(readfile, path)
    if ok2 and type(data) == "string" and #data > 0 then return data end
    return nil
end

local function safeWriteFile(path, data)
    if type(writefile) ~= "function" then return false end
    return pcall(writefile, path, data)
end

local function getHWID()
    if type(gethwid) == "function" then
        local ok, v = pcall(gethwid)
        if ok and type(v) == "string" and #v > 0 then return v end
    end
    local ok, clientId = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
    if ok and type(clientId) == "string" and #clientId > 0 then return "RBLX-" .. clientId end
    return "FALLBACK-" .. tostring(LocalPlayer.UserId) .. "-" .. tostring(LocalPlayer.Name)
end

local function httpRequest(opts)
    local req = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
    if type(req) == "function" then
        local ok, res = pcall(req, opts)
        if ok and res then
            return { ok = true, status = res.StatusCode or res.Status or 0, body = res.Body or res.body or "" }
        end
        return { ok = false, status = 0, body = tostring(res) }
    end
    local ok, body = pcall(function()
        local method = (opts.Method or "GET"):upper()
        if method == "GET" then return HttpService:GetAsync(opts.Url) end
        return HttpService:PostAsync(opts.Url, opts.Body or "", Enum.HttpContentType.ApplicationJson)
    end)
    if ok then return { ok = true, status = 200, body = body } end
    return { ok = false, status = 0, body = tostring(body) }
end

local function jsonDecode(str)
    local ok, data = pcall(function() return HttpService:JSONDecode(str) end)
    return ok and data or nil
end

local function jsonEncode(tbl)
    local ok, data = pcall(function() return HttpService:JSONEncode(tbl) end)
    return ok and data or "{}"
end

-- =========================
-- KEY SYSTEM
-- =========================
local KeySystem = { Valid = false, Key = "", HWID = getHWID(), LastResponse = nil }

function KeySystem:SaveKey(key)
    if CONFIG.AUTO_SAVE_KEY then safeWriteFile(CONFIG.KEY_FILE, key) end
end

function KeySystem:GetSavedKey()
    local cached = safeReadFile(CONFIG.KEY_FILE)
    if cached then
        cached = cached:gsub("%s+", "")
        if #cached > 0 then return cached end
    end
    return nil
end

function KeySystem:Validate(key)
    self.Key = tostring(key or ""):gsub("%s+", "")
    if self.Key == "" then return false, "key_vazia" end
    local url = CONFIG.PANEL_URL:gsub("/+$", "") .. "/api/validate-key"
    local res = httpRequest({
        Url = url,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" },
        Body = jsonEncode({ key = self.Key, hwid = self.HWID, app = CONFIG.APP, protocol = "XYZ_KEYS_V2" }),
    })
    if not res.ok then return false, "http_falhou" end
    local data = jsonDecode(res.body)
    if type(data) ~= "table" then return false, "resposta_invalida" end
    self.LastResponse = data
    local valid = data.valid == true or data.result == "valid"
    if valid then
        self.Valid = true
        self:SaveKey(self.Key)
        log("Key validada: " .. tostring(data.remaining_text or "ok"), "ok")
        return true, data
    end
    return false, tostring(data.reason or "invalid")
end

function KeySystem:Heartbeat()
    if not self.Valid or self.Key == "" then return end
    local url = CONFIG.PANEL_URL:gsub("/+$", "") .. "/api/heartbeat"
    local res = httpRequest({
        Url = url,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" },
        Body = jsonEncode({ key = self.Key, hwid = self.HWID, app = CONFIG.APP }),
    })
    if res.ok then
        local data = jsonDecode(res.body)
        if type(data) == "table" and (data.ok == false or data.valid == false) then
            self.Valid = false
            State.AutoFarm = false
            State.Kaitun = false
            State.AutoSpinFruit = false
            notify("Key inválida/expirada: " .. tostring(data.reason))
        end
    end
end

function KeySystem:PromptKey()
    local gui = Instance.new("ScreenGui")
    gui.Name = "BlackggKeyPrompt"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    local frame = Instance.new("Frame", gui)
    frame.Size = UDim2.new(0, 430, 0, 230)
    frame.Position = UDim2.new(0.5, -215, 0.5, -115)
    frame.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
    frame.BorderSizePixel = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)
    local st = Instance.new("UIStroke", frame); st.Color = Color3.fromRGB(88,101,242); st.Transparency = 0.5

    local title = Instance.new("TextLabel", frame)
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 16, 0, 14)
    title.Size = UDim2.new(1, -32, 0, 30)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 22
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(255,255,255)
    title.Text = "Blackgg • Key"

    local sub = Instance.new("TextLabel", frame)
    sub.BackgroundTransparency = 1
    sub.Position = UDim2.new(0, 16, 0, 46)
    sub.Size = UDim2.new(1, -32, 0, 20)
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 14
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.TextColor3 = Color3.fromRGB(170,175,190)
    sub.Text = "Digite sua key para liberar o script"

    local box = Instance.new("TextBox", frame)
    box.Position = UDim2.new(0, 16, 0, 84)
    box.Size = UDim2.new(1, -32, 0, 42)
    box.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
    box.TextColor3 = Color3.fromRGB(255,255,255)
    box.PlaceholderText = "XXXX-XXXX-XXXX"
    box.Text = ""
    box.ClearTextOnFocus = false
    box.Font = Enum.Font.Gotham
    box.TextSize = 16
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)

    local status = Instance.new("TextLabel", frame)
    status.BackgroundTransparency = 1
    status.Position = UDim2.new(0, 16, 0, 132)
    status.Size = UDim2.new(1, -32, 0, 20)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextColor3 = Color3.fromRGB(140,145,160)
    status.Text = "HWID: " .. tostring(self.HWID):sub(1, 40)

    local btn = Instance.new("TextButton", frame)
    btn.Position = UDim2.new(0, 16, 0, 164)
    btn.Size = UDim2.new(1, -32, 0, 42)
    btn.BackgroundColor3 = Color3.fromRGB(88,101,242)
    btn.Text = "Validar Key"
    btn.TextColor3 = Color3.fromRGB(255,255,255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 16
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

    local done, result = false, nil
    btn.MouseButton1Click:Connect(function()
        local key = tostring(box.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if #key < 3 then status.Text = "Informe uma key válida."; status.TextColor3 = Color3.fromRGB(255,100,100); return end
        btn.Text = "Validando..."; btn.Active = false
        task.spawn(function()
            local ok, reason = self:Validate(key)
            if ok then
                status.Text = "Key válida! Carregando..."; status.TextColor3 = Color3.fromRGB(90,255,140)
                result = key; task.wait(0.4); done = true; gui:Destroy()
            else
                status.Text = "Falha: " .. tostring(reason); status.TextColor3 = Color3.fromRGB(255,100,100)
                btn.Text = "Validar Key"; btn.Active = true
            end
        end)
    end)

    while not done do task.wait(0.2) end
    return result
end

function KeySystem:Init()
    local key = CONFIG.KEY
    if not key or key == "" then key = self:GetSavedKey() or "" end
    if not key or key == "" then key = self:PromptKey() or "" end
    local ok, reason = self:Validate(key)
    if not ok then return false, reason end
    task.spawn(function()
        while task.wait(CONFIG.HEARTBEAT_SECONDS) do
            pcall(function() KeySystem:Heartbeat() end)
        end
    end)
    return true
end


-- =========================
-- CHAR / COMBAT / MOVE
-- =========================
local currentTween = nil

local function getChar()
    local c = LocalPlayer.Character
    if not c then return nil end
    local hrp = c:FindFirstChild("HumanoidRootPart")
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return nil end
    return c, hrp, hum
end

local function getLevel()
    local ok, lv = pcall(function() return LocalPlayer.Data.Level.Value end)
    return (ok and type(lv) == "number") and lv or 1
end

local function getWorld()
    local placeId = game.PlaceId
    -- Blox Fruits usa o mesmo placeId com seas diferentes por lógica do jogo; usa mapas/posições
    -- Fallback por checagem de NPCs/áreas: aqui usamos nível + presença de Sea 3 islands
    local level = getLevel()
    if level >= 1500 then return 3 end
    if level >= 700 then return 2 end
    return 1
end

local function equipWeapon()
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not char or not backpack then return nil end
    for _, t in ipairs(char:GetChildren()) do if t:IsA("Tool") then return t end end
    for _, t in ipairs(backpack:GetChildren()) do
        if t:IsA("Tool") then
            pcall(function() t.Parent = char end)
            return t
        end
    end
    return nil
end

local function autoAttack()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:Button1Down(Vector2.new(1280,672), Workspace.CurrentCamera.CFrame)
        task.wait(0.05)
        VirtualUser:Button1Up(Vector2.new(1280,672), Workspace.CurrentCamera.CFrame)
    end)
end

local function cancelTween()
    if currentTween then pcall(function() currentTween:Cancel() end); currentTween = nil end
end

local function noclipOn()
    if Connections.Noclip then return end
    Connections.Noclip = RunService.Stepped:Connect(function()
        local c = LocalPlayer.Character
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end)
end

local function noclipOff()
    if Connections.Noclip then Connections.Noclip:Disconnect(); Connections.Noclip = nil end
end

local function tweenTo(cf)
    local _, hrp = getChar()
    if not hrp then return false end
    cancelTween()
    noclipOn()
    local dist = (hrp.Position - cf.Position).Magnitude
    local speed = math.max(tonumber(State.FarmSpeed) or 300, 50)
    local t = math.max(dist / speed, 0.05)
    currentTween = TweenService:Create(hrp, TweenInfo.new(t, Enum.EasingStyle.Linear), {CFrame = cf})
    currentTween:Play()
    local ok = pcall(function() currentTween.Completed:Wait() end)
    return ok
end

-- =========================
-- QUESTS SEA 1 / 2 / 3
-- =========================
local Quests = {
    -- SEA 1
    {sea=1,min=1,max=9,quest="BanditQuest1",qn=1,mob="Bandit",pos=CFrame.new(1060,16,1547)},
    {sea=1,min=10,max=14,quest="JungleQuest",qn=1,mob="Monkey",pos=CFrame.new(-1601,36,153)},
    {sea=1,min=15,max=29,quest="JungleQuest",qn=2,mob="Gorilla",pos=CFrame.new(-1223,6,-486)},
    {sea=1,min=30,max=39,quest="BuggyQuest1",qn=1,mob="Pirate",pos=CFrame.new(-1140,4,3830)},
    {sea=1,min=40,max=59,quest="BuggyQuest1",qn=2,mob="Brute",pos=CFrame.new(-1155,14,4298)},
    {sea=1,min=60,max=74,quest="DesertQuest",qn=1,mob="Desert Bandit",pos=CFrame.new(896,6,4391)},
    {sea=1,min=75,max=89,quest="DesertQuest",qn=2,mob="Desert Officer",pos=CFrame.new(1586,10,4371)},
    {sea=1,min=90,max=99,quest="SnowQuest",qn=1,mob="Snow Bandit",pos=CFrame.new(1386,87,-1298)},
    {sea=1,min=100,max=119,quest="SnowQuest",qn=2,mob="Snowman",pos=CFrame.new(1210,105,-1475)},
    {sea=1,min=120,max=149,quest="MarineQuest2",qn=1,mob="Chief Petty Officer",pos=CFrame.new(-5034,28,4324)},
    {sea=1,min=150,max=174,quest="SkyQuest",qn=1,mob="Sky Bandit",pos=CFrame.new(-4952,295,-2893)},
    {sea=1,min=175,max=189,quest="SkyQuest",qn=2,mob="Dark Master",pos=CFrame.new(-5250,388,-2272)},
    {sea=1,min=190,max=209,quest="PrisonerQuest",qn=1,mob="Prisoner",pos=CFrame.new(5308,2,474)},
    {sea=1,min=210,max=249,quest="PrisonerQuest",qn=2,mob="Dangerous Prisoner",pos=CFrame.new(5192,2,692)},
    {sea=1,min=250,max=274,quest="ColosseumQuest",qn=1,mob="Toga Warrior",pos=CFrame.new(-1825,7,-2746)},
    {sea=1,min=275,max=299,quest="ColosseumQuest",qn=2,mob="Gladiator",pos=CFrame.new(-1275,7,-2997)},
    {sea=1,min=300,max=324,quest="MagmaQuest",qn=1,mob="Military Soldier",pos=CFrame.new(-5411,11,8453)},
    {sea=1,min=325,max=374,quest="MagmaQuest",qn=2,mob="Military Spy",pos=CFrame.new(-5808,86,8828)},
    {sea=1,min=375,max=399,quest="FishmanQuest",qn=1,mob="Fishman Warrior",pos=CFrame.new(61122,18,1567)},
    {sea=1,min=400,max=449,quest="FishmanQuest",qn=2,mob="Fishman Commando",pos=CFrame.new(61890,18,1470)},
    {sea=1,min=450,max=474,quest="SkyExp1Quest",qn=1,mob="God's Guard",pos=CFrame.new(-4720,845,-1950)},
    {sea=1,min=475,max=524,quest="SkyExp1Quest",qn=2,mob="Shanda",pos=CFrame.new(-7863,5545,-380)},
    {sea=1,min=525,max=549,quest="SkyExp2Quest",qn=1,mob="Royal Squad",pos=CFrame.new(-7620,5655,-1419)},
    {sea=1,min=550,max=624,quest="SkyExp2Quest",qn=2,mob="Royal Soldier",pos=CFrame.new(-7834,5622,-1793)},
    {sea=1,min=625,max=649,quest="FountainQuest",qn=1,mob="Galley Pirate",pos=CFrame.new(5587,38,3997)},
    {sea=1,min=650,max=699,quest="FountainQuest",qn=2,mob="Galley Captain",pos=CFrame.new(5649,38,4936)},
    -- SEA 2
    {sea=2,min=700,max=724,quest="Area1Quest",qn=1,mob="Raider",pos=CFrame.new(-424,73,1836)},
    {sea=2,min=725,max=774,quest="Area1Quest",qn=2,mob="Mercenary",pos=CFrame.new(-876,73,1618)},
    {sea=2,min=775,max=799,quest="Area2Quest",qn=1,mob="Swan Pirate",pos=CFrame.new(878,122,1233)},
    {sea=2,min=800,max=874,quest="Area2Quest",qn=2,mob="Factory Staff",pos=CFrame.new(292,73,-57)},
    {sea=2,min=875,max=899,quest="MarineQuest3",qn=1,mob="Marine Lieutenant",pos=CFrame.new(-2841,73,-2976)},
    {sea=2,min=900,max=949,quest="MarineQuest3",qn=2,mob="Marine Captain",pos=CFrame.new(-1861,73,-3275)},
    {sea=2,min=950,max=974,quest="ZombieQuest",qn=1,mob="Zombie",pos=CFrame.new(-5714,22,-793)},
    {sea=2,min=975,max=999,quest="ZombieQuest",qn=2,mob="Vampire",pos=CFrame.new(-6036,7,-1313)},
    {sea=2,min=1000,max=1049,quest="SnowMountainQuest",qn=1,mob="Snow Trooper",pos=CFrame.new(550,401,-5350)},
    {sea=2,min=1050,max=1099,quest="SnowMountainQuest",qn=2,mob="Winter Warrior",pos=CFrame.new(1188,430,-5185)},
    {sea=2,min=1100,max=1124,quest="IceSideQuest",qn=1,mob="Lab Subordinate",pos=CFrame.new(-6063,16,-4904)},
    {sea=2,min=1125,max=1174,quest="IceSideQuest",qn=2,mob="Horned Warrior",pos=CFrame.new(-6302,16,-5790)},
    {sea=2,min=1175,max=1199,quest="FireSideQuest",qn=1,mob="Magma Ninja",pos=CFrame.new(-5428,16,-5299)},
    {sea=2,min=1200,max=1249,quest="FireSideQuest",qn=2,mob="Lava Pirate",pos=CFrame.new(-5169,34,-4661)},
    {sea=2,min=1250,max=1274,quest="ShipQuest1",qn=1,mob="Ship Deckhand",pos=CFrame.new(1213,125,33055)},
    {sea=2,min=1275,max=1299,quest="ShipQuest1",qn=2,mob="Ship Engineer",pos=CFrame.new(919,44,32940)},
    {sea=2,min=1300,max=1324,quest="ShipQuest2",qn=1,mob="Ship Steward",pos=CFrame.new(919,129,33446)},
    {sea=2,min=1325,max=1349,quest="ShipQuest2",qn=2,mob="Ship Officer",pos=CFrame.new(1192,181,33325)},
    {sea=2,min=1350,max=1374,quest="FrostQuest",qn=1,mob="Arctic Warrior",pos=CFrame.new(5976,57,-6820)},
    {sea=2,min=1375,max=1424,quest="FrostQuest",qn=2,mob="Snow Lurker",pos=CFrame.new(5583,40,-6778)},
    {sea=2,min=1425,max=1449,quest="ForgottenQuest",qn=1,mob="Sea Soldier",pos=CFrame.new(-3053,237,-10147)},
    {sea=2,min=1450,max=1499,quest="ForgottenQuest",qn=2,mob="Water Fighter",pos=CFrame.new(-3355,239,-10544)},
    -- SEA 3
    {sea=3,min=1500,max=1524,quest="PiratePortQuest",qn=1,mob="Pirate Millionaire",pos=CFrame.new(-291,44,5580)},
    {sea=3,min=1525,max=1574,quest="PiratePortQuest",qn=2,mob="Pistol Billionaire",pos=CFrame.new(-187,74,6020)},
    {sea=3,min=1575,max=1599,quest="AmazonQuest",qn=1,mob="Dragon Crew Warrior",pos=CFrame.new(5833,51,-1101)},
    {sea=3,min=1600,max=1624,quest="AmazonQuest",qn=2,mob="Dragon Crew Archer",pos=CFrame.new(6610,110,-387)},
    {sea=3,min=1625,max=1649,quest="AmazonQuest2",qn=1,mob="Female Islander",pos=CFrame.new(4685,758,-1851)},
    {sea=3,min=1650,max=1699,quest="AmazonQuest2",qn=2,mob="Giant Islander",pos=CFrame.new(5315,93,-4998)},
    {sea=3,min=1700,max=1724,quest="MarineTreeIsland",qn=1,mob="Marine Commodore",pos=CFrame.new(2180,29,-6939)},
    {sea=3,min=1725,max=1774,quest="MarineTreeIsland",qn=2,mob="Marine Rear Admiral",pos=CFrame.new(3663,160,-7034)},
    {sea=3,min=1775,max=1799,quest="DeepForestIsland3",qn=1,mob="Fishman Raider",pos=CFrame.new(-10581,331,-8757)},
    {sea=3,min=1800,max=1824,quest="DeepForestIsland3",qn=2,mob="Fishman Captain",pos=CFrame.new(-11037,332,-9124)},
    {sea=3,min=1825,max=1849,quest="DeepForestIsland",qn=1,mob="Forest Pirate",pos=CFrame.new(-13234,332,-7626)},
    {sea=3,min=1850,max=1899,quest="DeepForestIsland",qn=2,mob="Mythological Pirate",pos=CFrame.new(-13509,470,-6941)},
    {sea=3,min=1900,max=1924,quest="DeepForestIsland2",qn=1,mob="Jungle Pirate",pos=CFrame.new(-12680,390,-9902)},
    {sea=3,min=1925,max=1974,quest="DeepForestIsland2",qn=2,mob="Musketeer Pirate",pos=CFrame.new(-13407,391,-9850)},
    {sea=3,min=1975,max=1999,quest="HauntedCastleQuest1",qn=1,mob="Reborn Skeleton",pos=CFrame.new(-8763,142,5963)},
    {sea=3,min=2000,max=2024,quest="HauntedCastleQuest1",qn=2,mob="Living Zombie",pos=CFrame.new(-10144,138,5834)},
    {sea=3,min=2025,max=2049,quest="HauntedCastleQuest2",qn=1,mob="Demonic Soul",pos=CFrame.new(-9507,172,6158)},
    {sea=3,min=2050,max=2074,quest="HauntedCastleQuest2",qn=2,mob="Posessed Mummy",pos=CFrame.new(-9577,6,6191)},
    {sea=3,min=2075,max=2099,quest="NutsIslandQuest",qn=1,mob="Peanut Scout",pos=CFrame.new(-2105,38,-10195)},
    {sea=3,min=2100,max=2124,quest="NutsIslandQuest",qn=2,mob="Peanut President",pos=CFrame.new(-1855,38,-10443)},
    {sea=3,min=2125,max=2149,quest="IceCreamIslandQuest",qn=1,mob="Ice Cream Chef",pos=CFrame.new(-820,65,-10965)},
    {sea=3,min=2150,max=2199,quest="IceCreamIslandQuest",qn=2,mob="Ice Cream Commander",pos=CFrame.new(-613,65,-11303)},
    {sea=3,min=2200,max=2224,quest="CakeQuest1",qn=1,mob="Cookie Crafter",pos=CFrame.new(-2023,38,-12028)},
    {sea=3,min=2225,max=2249,quest="CakeQuest1",qn=2,mob="Cake Guard",pos=CFrame.new(-1543,38,-12245)},
    {sea=3,min=2250,max=2274,quest="CakeQuest2",qn=1,mob="Baking Staff",pos=CFrame.new(-1927,38,-12840)},
    {sea=3,min=2275,max=2299,quest="CakeQuest2",qn=2,mob="Head Baker",pos=CFrame.new(-2122,38,-12832)},
    {sea=3,min=2300,max=2324,quest="ChocQuest1",qn=1,mob="Cocoa Warrior",pos=CFrame.new(233,25,-12202)},
    {sea=3,min=2325,max=2349,quest="ChocQuest1",qn=2,mob="Chocolate Bar Battler",pos=CFrame.new(592,25,-12389)},
    {sea=3,min=2350,max=2374,quest="ChocQuest2",qn=1,mob="Sweet Thief",pos=CFrame.new(73,25,-12440)},
    {sea=3,min=2375,max=2399,quest="ChocQuest2",qn=2,mob="Candy Rebel",pos=CFrame.new(132,25,-12755)},
    {sea=3,min=2400,max=2424,quest="CandyQuest1",qn=1,mob="Candy Pirate",pos=CFrame.new(-1153,14,-14445)},
    {sea=3,min=2425,max=2449,quest="CandyQuest1",qn=2,mob="Snow Demon",pos=CFrame.new(-826,14,-14420)},
    {sea=3,min=2450,max=2550,quest="CandyQuest1",qn=2,mob="Snow Demon",pos=CFrame.new(-826,14,-14420)},
}

local function getQuestForLevel(level)
    local best = nil
    for _, q in ipairs(Quests) do
        if level >= q.min and level <= q.max then
            best = q
            break
        end
    end
    if not best then best = Quests[#Quests] end
    return best
end


-- =========================
-- FARM CORE
-- =========================
local function hasQuest()
    local ok, visible = pcall(function() return LocalPlayer.PlayerGui.Main.Quest.Visible end)
    return ok and visible == true
end

local function startQuest(q)
    pcall(function() ReplicatedStorage.Remotes.CommF_:InvokeServer("StartQuest", q.quest, q.qn) end)
end

local function getMob(name)
    local enemies = Workspace:FindFirstChild("Enemies")
    local _, hrp = getChar()
    if not enemies or not hrp then return nil end
    local best, bd = nil, math.huge
    for _, m in ipairs(enemies:GetChildren()) do
        if m.Name == name then
            local hum = m:FindFirstChildOfClass("Humanoid")
            local mhrp = m:FindFirstChild("HumanoidRootPart")
            if hum and mhrp and hum.Health > 0 then
                local d = (mhrp.Position - hrp.Position).Magnitude
                if d < bd then bd, best = d, m end
            end
        end
    end
    return best
end

local function bringMobs(name, cf)
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return end
    for _, m in ipairs(enemies:GetChildren()) do
        if m.Name == name then
            local hum = m:FindFirstChildOfClass("Humanoid")
            local mhrp = m:FindFirstChild("HumanoidRootPart")
            if hum and mhrp and hum.Health > 0 then
                pcall(function()
                    mhrp.CFrame = cf
                    mhrp.CanCollide = false
                    hum.WalkSpeed = 0
                    hum.JumpPower = 0
                    hum.PlatformStand = false
                    local bv = mhrp:FindFirstChild("BodyVelocity")
                    if not bv then
                        bv = Instance.new("BodyVelocity")
                        bv.MaxForce = Vector3.new(1e5,1e5,1e5)
                        bv.Velocity = Vector3.new(0,0,0)
                        bv.Parent = mhrp
                    end
                end)
            end
        end
    end
end

local function farmTick()
    if not KeySystem.Valid then return end
    local char, hrp, hum = getChar()
    if not char then return end
    local level = getLevel()
    local q = getQuestForLevel(level)
    if not q then return end

    equipWeapon()

    if not hasQuest() then
        tweenTo(q.pos)
        task.wait(0.3)
        startQuest(q)
        task.wait(0.4)
        return
    end

    local mob = getMob(q.mob)
    if mob and mob:FindFirstChild("HumanoidRootPart") and mob:FindFirstChildOfClass("Humanoid") then
        local mh = mob:FindFirstChildOfClass("Humanoid")
        while State.AutoFarm and KeySystem.Valid and mob.Parent and mh.Health > 0 and hasQuest() do
            local c2, hrp2 = getChar()
            if not c2 or not hrp2 then break end
            equipWeapon()
            local mhrp = mob:FindFirstChild("HumanoidRootPart")
            if not mhrp then break end
            local above = mhrp.CFrame * CFrame.new(0, tonumber(State.FarmDistance) or 8, 0)
            pcall(function()
                hrp2.CFrame = above
                hrp2.Velocity = Vector3.new(0,0,0)
            end)
            bringMobs(q.mob, mhrp.CFrame)
            autoAttack()
            task.wait(tonumber(State.AttackDelay) or 0.12)
            mh = mob:FindFirstChildOfClass("Humanoid")
            if not mh then break end
        end
    else
        tweenTo(q.pos)
        task.wait(0.2)
    end
end

local function startAutoFarmLoop()
    if Connections.AutoFarmLoop then return end
    Connections.AutoFarmLoop = task.spawn(function()
        while task.wait(0.15) do
            if State.AutoFarm or State.Kaitun then
                local ok, err = pcall(farmTick)
                if not ok then log("Farm erro: " .. tostring(err), "warn"); task.wait(1) end
            end
        end
    end)
end

-- =========================
-- KAITUN (AUTO PROGRESSÃO)
-- =========================
-- Modo Kaitun: ativa progressão automática por nível (Sea 1 -> Sea 3),
-- usando a tabela de quests por faixa de nível e mantendo Auto Farm ativo.
local function setKaitun(on)
    State.Kaitun = on
    State.AutoFarm = on -- kaitun controla o farm
    if on then
        notify("Kaitun ligado: progressão automática por nível")
    else
        notify("Kaitun desligado")
        cancelTween()
    end
    if UIRefs.RefreshFarm then UIRefs.RefreshFarm() end
    if UIRefs.RefreshKaitun then UIRefs.RefreshKaitun() end
end

-- =========================
-- ESP FRUTAS
-- =========================
local function getFruitTarget(inst)
    if inst:IsA("Tool") then return inst:FindFirstChild("Handle") or inst:FindFirstChildWhichIsA("BasePart") end
    if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart") end
    if inst:IsA("BasePart") then return inst end
    return nil
end

local function isFruit(inst)
    if not inst then return false end
    local n = inst.Name:lower()
    if inst:IsA("Tool") and n:find("fruit") then return true end
    if inst:IsA("Model") and n:find("fruit") then return true end
    return false
end

local function removeFruitESP(inst)
    local d = ESPObjects[inst]
    if not d then return end
    pcall(function() if d.billboard then d.billboard:Destroy() end end)
    pcall(function() if d.highlight then d.highlight:Destroy() end end)
    ESPObjects[inst] = nil
end

local function clearFruitESP()
    for inst, _ in pairs(ESPObjects) do removeFruitESP(inst) end
end

local function addFruitESP(inst)
    if ESPObjects[inst] then return end
    local target = getFruitTarget(inst)
    if not target then return end
    local parentGui = pcall(function() return game:GetService("CoreGui") end) and game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "BlackggFruitESP"
    billboard.Adornee = target
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = parentGui

    local label = Instance.new("TextLabel", billboard)
    label.Size = UDim2.new(1,0,1,0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 120, 255)
    label.TextStrokeTransparency = 0.2
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.Text = inst.Name

    local hl = Instance.new("Highlight")
    hl.Name = "BlackggFruitHL"
    hl.Adornee = inst:IsA("BasePart") and inst.Parent or inst
    hl.FillColor = Color3.fromRGB(255, 120, 255)
    hl.OutlineColor = Color3.fromRGB(255,255,255)
    hl.FillTransparency = 0.45
    hl.Parent = parentGui

    ESPObjects[inst] = {billboard=billboard, highlight=hl, label=label}
end

local function scanFruits()
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if isFruit(inst) then addFruitESP(inst) end
    end
end

local function updateFruitESP()
    local _, hrp = getChar()
    for inst, d in pairs(ESPObjects) do
        if not inst or not inst.Parent then
            removeFruitESP(inst)
        else
            local target = getFruitTarget(inst)
            local dist = 0
            if hrp and target then dist = math.floor((target.Position - hrp.Position).Magnitude) end
            if d.label then d.label.Text = inst.Name .. " [" .. dist .. "m]" end
            if d.billboard then d.billboard.Adornee = target end
        end
    end
end

local function setESPFruits(on)
    State.ESPFruits = on
    if on then
        clearFruitESP()
        scanFruits()
        Connections.FruitAdded = Workspace.DescendantAdded:Connect(function(inst)
            if not State.ESPFruits then return end
            task.wait(0.2)
            if isFruit(inst) then addFruitESP(inst) end
        end)
        Connections.FruitRemoved = Workspace.DescendantRemoving:Connect(function(inst)
            if ESPObjects[inst] then removeFruitESP(inst) end
        end)
        Connections.FruitUpdate = RunService.RenderStepped:Connect(function()
            if State.ESPFruits then updateFruitESP() end
        end)
        notify("ESP Frutas ligado")
    else
        if Connections.FruitAdded then Connections.FruitAdded:Disconnect(); Connections.FruitAdded=nil end
        if Connections.FruitRemoved then Connections.FruitRemoved:Disconnect(); Connections.FruitRemoved=nil end
        if Connections.FruitUpdate then Connections.FruitUpdate:Disconnect(); Connections.FruitUpdate=nil end
        clearFruitESP()
        notify("ESP Frutas desligado")
    end
    if UIRefs.RefreshESP then UIRefs.RefreshESP() end
end

-- =========================
-- AUTO GIRAR FRUTAS
-- =========================
local function trySpinFruit()
    -- tenta remotes comuns do Blox Fruits para compra/giro de fruta
    local rem = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
    if not rem then return false end
    local tries = {
        function() return rem:InvokeServer("Cousin", "Buy") end,
        function() return rem:InvokeServer("Cousin", "BuyRandomFruit") end,
        function() return rem:InvokeServer("Cousin", "BuyFruit") end,
    }
    for _, fn in ipairs(tries) do
        local ok, res = pcall(fn)
        if ok then return true, res end
    end
    return false
end

local function startSpinLoop()
    if Connections.SpinLoop then return end
    Connections.SpinLoop = task.spawn(function()
        while task.wait(0.5) do
            if State.AutoSpinFruit and KeySystem.Valid then
                local ok, err = pcall(trySpinFruit)
                if not ok then log("Spin erro: " .. tostring(err), "warn") end
                task.wait(tonumber(State.SpinDelay) or 2.5)
            end
        end
    end)
end

local function setAutoSpin(on)
    State.AutoSpinFruit = on
    notify("Girar frutas: " .. (on and "ON" or "OFF"))
    if UIRefs.RefreshSpin then UIRefs.RefreshSpin() end
end


-- =========================
-- ESP PLAYERS
-- =========================
local PlayerESPObjects = {}

local function removePlayerESP(plr)
    local d = PlayerESPObjects[plr]
    if not d then return end
    pcall(function() if d.billboard then d.billboard:Destroy() end end)
    pcall(function() if d.highlight then d.highlight:Destroy() end end)
    PlayerESPObjects[plr] = nil
end

local function clearPlayerESP()
    for plr, _ in pairs(PlayerESPObjects) do removePlayerESP(plr) end
end

local function addPlayerESP(plr)
    if plr == LocalPlayer or PlayerESPObjects[plr] then return end
    local function attach(char)
        if not State.ESPPlayers then return end
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 5)
        if not hrp then return end
        removePlayerESP(plr)
        local parentGui = pcall(function() return game:GetService("CoreGui") end) and game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")

        local bb = Instance.new("BillboardGui")
        bb.Name = "BlackggPlayerESP"
        bb.Adornee = hrp
        bb.Size = UDim2.new(0, 180, 0, 56)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true
        bb.Parent = parentGui

        local nameLbl = Instance.new("TextLabel", bb)
        nameLbl.Size = UDim2.new(1,0,0,22)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Font = Enum.Font.GothamBold
        nameLbl.TextScaled = true
        nameLbl.TextColor3 = Color3.fromRGB(80, 200, 255)
        nameLbl.TextStrokeTransparency = 0.2
        nameLbl.Text = plr.Name

        local distLbl = Instance.new("TextLabel", bb)
        distLbl.Position = UDim2.new(0,0,0,24)
        distLbl.Size = UDim2.new(1,0,0,18)
        distLbl.BackgroundTransparency = 1
        distLbl.Font = Enum.Font.Gotham
        distLbl.TextScaled = true
        distLbl.TextColor3 = Color3.fromRGB(220,220,220)
        distLbl.TextStrokeTransparency = 0.3
        distLbl.Text = ""

        local hl = Instance.new("Highlight")
        hl.Name = "BlackggPlayerHL"
        hl.Adornee = char
        hl.FillColor = Color3.fromRGB(80, 200, 255)
        hl.OutlineColor = Color3.fromRGB(255,255,255)
        hl.FillTransparency = 0.6
        hl.OutlineTransparency = 0.2
        hl.Parent = parentGui

        PlayerESPObjects[plr] = {billboard=bb, highlight=hl, nameLbl=nameLbl, distLbl=distLbl}
    end

    if plr.Character then attach(plr.Character) end
    plr.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        if State.ESPPlayers then attach(char) end
    end)
end

local function updatePlayerESP()
    local _, myHrp = getChar()
    for plr, d in pairs(PlayerESPObjects) do
        if not plr or not plr.Parent then
            removePlayerESP(plr)
        else
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum or hum.Health <= 0 then
                if d.billboard then d.billboard.Enabled = false end
                if d.highlight then d.highlight.Enabled = false end
            else
                if d.billboard then d.billboard.Enabled = true; d.billboard.Adornee = hrp end
                if d.highlight then d.highlight.Enabled = true; d.highlight.Adornee = char end
                local dist = 0
                if myHrp then dist = math.floor((hrp.Position - myHrp.Position).Magnitude) end
                local hp = math.floor(hum.Health)
                if d.distLbl then d.distLbl.Text = hp .. " HP | " .. dist .. "m" end
                if d.nameLbl then d.nameLbl.Text = plr.DisplayName or plr.Name end
            end
        end
    end
end

local function setESPPlayers(on)
    State.ESPPlayers = on
    if on then
        clearPlayerESP()
        for _, plr in ipairs(Players:GetPlayers()) do addPlayerESP(plr) end
        Connections.PlayerAdded = Players.PlayerAdded:Connect(function(plr)
            if State.ESPPlayers then addPlayerESP(plr) end
        end)
        Connections.PlayerRemoving = Players.PlayerRemoving:Connect(function(plr)
            removePlayerESP(plr)
        end)
        Connections.PlayerESPUpdate = RunService.RenderStepped:Connect(function()
            if State.ESPPlayers then updatePlayerESP() end
        end)
        notify("ESP Jogadores ligado")
    else
        if Connections.PlayerAdded then Connections.PlayerAdded:Disconnect(); Connections.PlayerAdded=nil end
        if Connections.PlayerRemoving then Connections.PlayerRemoving:Disconnect(); Connections.PlayerRemoving=nil end
        if Connections.PlayerESPUpdate then Connections.PlayerESPUpdate:Disconnect(); Connections.PlayerESPUpdate=nil end
        clearPlayerESP()
        notify("ESP Jogadores desligado")
    end
    if UIRefs.RefreshESPPlayers then UIRefs.RefreshESPPlayers() end
end

-- =========================
-- UI OVERLAY (Blackgg) - Modern Black
-- =========================
local function createUI()
    local parentGui = pcall(function() return game:GetService("CoreGui") end) and game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")
    local old = parentGui:FindFirstChild("BlackggOverlay")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "BlackggOverlay"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.IgnoreGuiInset = true
    gui.Parent = parentGui

    local floatBtn = Instance.new("TextButton", gui)
    floatBtn.Size = UDim2.new(0, 46, 0, 46)
    floatBtn.Position = UDim2.new(0, 16, 0.5, -23)
    floatBtn.BackgroundColor3 = Color3.fromRGB(10,10,10)
    floatBtn.Text = "B"
    floatBtn.TextColor3 = Color3.fromRGB(255,255,255)
    floatBtn.Font = Enum.Font.GothamBold
    floatBtn.TextSize = 20
    floatBtn.Visible = false
    floatBtn.AutoButtonColor = false
    Instance.new("UICorner", floatBtn).CornerRadius = UDim.new(1,0)
    local fSt = Instance.new("UIStroke", floatBtn); fSt.Color = Color3.fromRGB(55,55,55); fSt.Thickness = 1

    local main = Instance.new("Frame", gui)
    main.Size = UDim2.new(0, 560, 0, 360)
    main.Position = UDim2.new(0.5, -280, 0.5, -180)
    main.BackgroundColor3 = Color3.fromRGB(8,8,10)
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
    local mSt = Instance.new("UIStroke", main); mSt.Color = Color3.fromRGB(35,35,40); mSt.Thickness = 1

    -- topbar
    local top = Instance.new("Frame", main)
    top.Size = UDim2.new(1,0,0,48)
    top.BackgroundColor3 = Color3.fromRGB(12,12,14)
    top.BorderSizePixel = 0
    Instance.new("UICorner", top).CornerRadius = UDim.new(0,12)
    local topFix = Instance.new("Frame", top)
    topFix.Size = UDim2.new(1,0,0,12); topFix.Position = UDim2.new(0,0,1,-12)
    topFix.BackgroundColor3 = Color3.fromRGB(12,12,14); topFix.BorderSizePixel = 0

    local title = Instance.new("TextLabel", top)
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0,16,0,0)
    title.Size = UDim2.new(0,200,1,0)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 20
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(245,245,245)
    title.Text = "BLACKGG"

    local sub = Instance.new("TextLabel", top)
    sub.BackgroundTransparency = 1
    sub.Position = UDim2.new(0,120,0,0)
    sub.Size = UDim2.new(0,200,1,0)
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 12
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.TextColor3 = Color3.fromRGB(110,110,120)
    sub.Text = "blox fruits"

    local close = Instance.new("TextButton", top)
    close.Size = UDim2.new(0,34,0,28)
    close.Position = UDim2.new(1,-44,0.5,-14)
    close.BackgroundColor3 = Color3.fromRGB(20,20,24)
    close.Text = "—"
    close.Font = Enum.Font.GothamBold
    close.TextSize = 16
    close.TextColor3 = Color3.fromRGB(220,220,220)
    close.AutoButtonColor = false
    Instance.new("UICorner", close).CornerRadius = UDim.new(0,8)
    local cSt = Instance.new("UIStroke", close); cSt.Color = Color3.fromRGB(45,45,50); cSt.Thickness = 1

    local function setVisible(v)
        main.Visible = v
        floatBtn.Visible = not v
    end
    close.MouseButton1Click:Connect(function() setVisible(false) end)
    floatBtn.MouseButton1Click:Connect(function() setVisible(true) end)
    UserInputService.InputBegan:Connect(function(input,gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.RightControl then setVisible(not main.Visible) end
    end)

    -- sidebar
    local side = Instance.new("Frame", main)
    side.Position = UDim2.new(0,10,0,58)
    side.Size = UDim2.new(0,150,1,-68)
    side.BackgroundColor3 = Color3.fromRGB(12,12,14)
    side.BorderSizePixel = 0
    Instance.new("UICorner", side).CornerRadius = UDim.new(0,10)
    local sideSt = Instance.new("UIStroke", side); sideSt.Color = Color3.fromRGB(30,30,34); sideSt.Thickness = 1

    local sideList = Instance.new("UIListLayout", side)
    sideList.Padding = UDim.new(0,6)
    sideList.SortOrder = Enum.SortOrder.LayoutOrder
    local sidePad = Instance.new("UIPadding", side)
    sidePad.PaddingTop = UDim.new(0,8); sidePad.PaddingLeft = UDim.new(0,8); sidePad.PaddingRight = UDim.new(0,8)

    -- content
    local content = Instance.new("Frame", main)
    content.Position = UDim2.new(0,170,0,58)
    content.Size = UDim2.new(1,-180,1,-68)
    content.BackgroundColor3 = Color3.fromRGB(12,12,14)
    content.BorderSizePixel = 0
    Instance.new("UICorner", content).CornerRadius = UDim.new(0,10)
    local contSt = Instance.new("UIStroke", content); contSt.Color = Color3.fromRGB(30,30,34); contSt.Thickness = 1

    local pages = {}
    local tabBtns = {}

    local function showPage(name)
        for k,v in pairs(pages) do v.Visible = (k == name) end
        for k,b in pairs(tabBtns) do
            local on = (k == name)
            b.BackgroundColor3 = on and Color3.fromRGB(24,24,28) or Color3.fromRGB(12,12,14)
            b.TextColor3 = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(150,150,160)
        end
    end

    local function makeTab(name, order)
        local b = Instance.new("TextButton", side)
        b.LayoutOrder = order
        b.Size = UDim2.new(1,0,0,36)
        b.BackgroundColor3 = Color3.fromRGB(12,12,14)
        b.Text = name
        b.Font = Enum.Font.GothamSemibold
        b.TextSize = 14
        b.TextColor3 = Color3.fromRGB(150,150,160)
        b.AutoButtonColor = false
        Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
        local st = Instance.new("UIStroke", b); st.Color = Color3.fromRGB(35,35,40); st.Thickness = 1
        tabBtns[name] = b
        b.MouseButton1Click:Connect(function() showPage(name) end)

        local page = Instance.new("ScrollingFrame", content)
        page.Name = name
        page.Visible = false
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.Position = UDim2.new(0,10,0,10)
        page.Size = UDim2.new(1,-20,1,-20)
        page.ScrollBarThickness = 2
        page.ScrollBarImageColor3 = Color3.fromRGB(70,70,80)
        page.CanvasSize = UDim2.new(0,0,0,0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        local pl = Instance.new("UIListLayout", page)
        pl.Padding = UDim.new(0,8)
        pl.SortOrder = Enum.SortOrder.LayoutOrder
        pages[name] = page
        return page
    end

    local pageKaitun = makeTab("Kaitun", 1)
    local pageFarm = makeTab("Farm", 2)
    local pageESP = makeTab("ESP", 3)
    local pageFrutas = makeTab("Girar Fruta", 4)

    local function makeToggle(parent, text, desc, order, getter, setter)
        local row = Instance.new("Frame", parent)
        row.LayoutOrder = order
        row.Size = UDim2.new(1,0,0,58)
        row.BackgroundColor3 = Color3.fromRGB(18,18,22)
        row.BorderSizePixel = 0
        Instance.new("UICorner", row).CornerRadius = UDim.new(0,10)
        local st = Instance.new("UIStroke", row); st.Color = Color3.fromRGB(38,38,44); st.Thickness = 1

        local lbl = Instance.new("TextLabel", row)
        lbl.BackgroundTransparency = 1
        lbl.Position = UDim2.new(0,14,0,8)
        lbl.Size = UDim2.new(1,-90,0,20)
        lbl.Font = Enum.Font.GothamSemibold
        lbl.TextSize = 14
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextColor3 = Color3.fromRGB(235,235,235)
        lbl.Text = text

        local d = Instance.new("TextLabel", row)
        d.BackgroundTransparency = 1
        d.Position = UDim2.new(0,14,0,30)
        d.Size = UDim2.new(1,-90,0,18)
        d.Font = Enum.Font.Gotham
        d.TextSize = 12
        d.TextXAlignment = Enum.TextXAlignment.Left
        d.TextColor3 = Color3.fromRGB(120,120,130)
        d.Text = desc or ""

        local btn = Instance.new("TextButton", row)
        btn.Size = UDim2.new(0,54,0,28)
        btn.Position = UDim2.new(1,-66,0.5,-14)
        btn.BackgroundColor3 = Color3.fromRGB(40,40,46)
        btn.Text = "OFF"
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.TextColor3 = Color3.fromRGB(255,255,255)
        btn.AutoButtonColor = false
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)

        local function refresh()
            local on = getter()
            btn.Text = on and "ON" or "OFF"
            btn.BackgroundColor3 = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(40,40,46)
            btn.TextColor3 = on and Color3.fromRGB(0,0,0) or Color3.fromRGB(255,255,255)
        end
        btn.MouseButton1Click:Connect(function() setter(not getter()); refresh() end)
        refresh()
        return refresh
    end

    local function makeSlider(parent, text, order, minV, maxV, step, getter, setter)
        local row = Instance.new("Frame", parent)
        row.LayoutOrder = order
        row.Size = UDim2.new(1,0,0,66)
        row.BackgroundColor3 = Color3.fromRGB(18,18,22)
        row.BorderSizePixel = 0
        Instance.new("UICorner", row).CornerRadius = UDim.new(0,10)
        local st = Instance.new("UIStroke", row); st.Color = Color3.fromRGB(38,38,44); st.Thickness = 1

        local lbl = Instance.new("TextLabel", row)
        lbl.BackgroundTransparency = 1
        lbl.Position = UDim2.new(0,14,0,8)
        lbl.Size = UDim2.new(1,-80,0,20)
        lbl.Font = Enum.Font.GothamSemibold
        lbl.TextSize = 14
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextColor3 = Color3.fromRGB(235,235,235)
        lbl.Text = text

        local val = Instance.new("TextLabel", row)
        val.BackgroundTransparency = 1
        val.Position = UDim2.new(1,-74,0,8)
        val.Size = UDim2.new(0,60,0,20)
        val.Font = Enum.Font.GothamBold
        val.TextSize = 13
        val.TextXAlignment = Enum.TextXAlignment.Right
        val.TextColor3 = Color3.fromRGB(200,200,200)

        local minus = Instance.new("TextButton", row)
        minus.Size = UDim2.new(0,32,0,24)
        minus.Position = UDim2.new(0,14,0,34)
        minus.BackgroundColor3 = Color3.fromRGB(32,32,38)
        minus.Text = "-"
        minus.Font = Enum.Font.GothamBold
        minus.TextSize = 16
        minus.TextColor3 = Color3.fromRGB(255,255,255)
        minus.AutoButtonColor = false
        Instance.new("UICorner", minus).CornerRadius = UDim.new(0,6)

        local plus = Instance.new("TextButton", row)
        plus.Size = UDim2.new(0,32,0,24)
        plus.Position = UDim2.new(1,-46,0,34)
        plus.BackgroundColor3 = Color3.fromRGB(32,32,38)
        plus.Text = "+"
        plus.Font = Enum.Font.GothamBold
        plus.TextSize = 16
        plus.TextColor3 = Color3.fromRGB(255,255,255)
        plus.AutoButtonColor = false
        Instance.new("UICorner", plus).CornerRadius = UDim.new(0,6)

        local barBg = Instance.new("Frame", row)
        barBg.Position = UDim2.new(0,54,0,44)
        barBg.Size = UDim2.new(1,-108,0,4)
        barBg.BackgroundColor3 = Color3.fromRGB(40,40,46)
        barBg.BorderSizePixel = 0
        Instance.new("UICorner", barBg).CornerRadius = UDim.new(1,0)
        local bar = Instance.new("Frame", barBg)
        bar.BackgroundColor3 = Color3.fromRGB(255,255,255)
        bar.BorderSizePixel = 0
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1,0)

        local function refresh()
            local v = tonumber(getter()) or minV
            v = math.clamp(v, minV, maxV)
            val.Text = tostring(v)
            local pct = (v-minV)/math.max(maxV-minV,1)
            bar.Size = UDim2.new(pct,0,1,0)
        end
        minus.MouseButton1Click:Connect(function() setter(math.clamp((tonumber(getter()) or minV)-step, minV, maxV)); refresh() end)
        plus.MouseButton1Click:Connect(function() setter(math.clamp((tonumber(getter()) or minV)+step, minV, maxV)); refresh() end)
        refresh()
        return refresh
    end

    -- Kaitun page
    UIRefs.RefreshKaitun = makeToggle(pageKaitun, "Kaitun (Auto Progressão)", "Progressão automática por nível Sea 1–3", 1,
        function() return State.Kaitun end,
        function(v) setKaitun(v) end)

    local kaitunInfo = Instance.new("TextLabel", pageKaitun)
    kaitunInfo.LayoutOrder = 2
    kaitunInfo.Size = UDim2.new(1,0,0,64)
    kaitunInfo.BackgroundColor3 = Color3.fromRGB(18,18,22)
    kaitunInfo.TextWrapped = true
    kaitunInfo.Font = Enum.Font.Gotham
    kaitunInfo.TextSize = 12
    kaitunInfo.TextXAlignment = Enum.TextXAlignment.Left
    kaitunInfo.TextYAlignment = Enum.TextYAlignment.Top
    kaitunInfo.TextColor3 = Color3.fromRGB(150,150,160)
    kaitunInfo.Text = "  Faz farm por nível seguindo quests do Sea 1 ao Sea 3.\n  Ativar Kaitun também ativa o Auto Farm.\n  Mantenha uma arma equipada para melhor resultado."
    Instance.new("UICorner", kaitunInfo).CornerRadius = UDim.new(0,10)
    local kiPad = Instance.new("UIPadding", kaitunInfo); kiPad.PaddingTop=UDim.new(0,10); kiPad.PaddingLeft=UDim.new(0,10); kiPad.PaddingRight=UDim.new(0,10)

    -- Farm page
    UIRefs.RefreshFarm = makeToggle(pageFarm, "Auto Farm", "Farma mobs/quests conforme seu nível", 1,
        function() return State.AutoFarm end,
        function(v)
            State.AutoFarm = v
            if not v and not State.Kaitun then cancelTween(); noclipOff() end
            notify("Auto Farm: " .. (v and "ON" or "OFF"))
        end)

    UIRefs.RefreshSpeed = makeSlider(pageFarm, "Velocidade do Farm", 2, 50, 1000, 25,
        function() return State.FarmSpeed end,
        function(v) State.FarmSpeed = v end)

    -- ESP page
    UIRefs.RefreshESPPlayers = makeToggle(pageESP, "ESP Jogadores", "Mostra jogadores, HP e distância", 1,
        function() return State.ESPPlayers end,
        function(v) setESPPlayers(v) end)

    UIRefs.RefreshESP = makeToggle(pageESP, "ESP Frutas", "Destaca frutas spawnadas no mapa", 2,
        function() return State.ESPFruits end,
        function(v) setESPFruits(v) end)

    -- Girar Fruta page
    UIRefs.RefreshSpin = makeToggle(pageFrutas, "Girar Frutas", "Tenta girar/comprar fruta automaticamente", 1,
        function() return State.AutoSpinFruit end,
        function(v) setAutoSpin(v) end)

    local spinInfo = Instance.new("TextLabel", pageFrutas)
    spinInfo.LayoutOrder = 2
    spinInfo.Size = UDim2.new(1,0,0,54)
    spinInfo.BackgroundColor3 = Color3.fromRGB(18,18,22)
    spinInfo.TextWrapped = true
    spinInfo.Font = Enum.Font.Gotham
    spinInfo.TextSize = 12
    spinInfo.TextXAlignment = Enum.TextXAlignment.Left
    spinInfo.TextYAlignment = Enum.TextYAlignment.Top
    spinInfo.TextColor3 = Color3.fromRGB(150,150,160)
    spinInfo.Text = "  Usa remotes comuns do Cousin (Buy/BuyRandomFruit).\n  Pode falhar se o servidor/remoto mudar."
    Instance.new("UICorner", spinInfo).CornerRadius = UDim.new(0,10)
    local spPad = Instance.new("UIPadding", spinInfo); spPad.PaddingTop=UDim.new(0,10); spPad.PaddingLeft=UDim.new(0,10); spPad.PaddingRight=UDim.new(0,10)

    local footer = Instance.new("TextLabel", main)
    footer.BackgroundTransparency = 1
    footer.Position = UDim2.new(0,170,1,-22)
    footer.Size = UDim2.new(1,-180,0,18)
    footer.Font = Enum.Font.Gotham
    footer.TextSize = 11
    footer.TextXAlignment = Enum.TextXAlignment.Left
    footer.TextColor3 = Color3.fromRGB(90,90,100)
    footer.Text = "Key: " .. (KeySystem.Key:sub(1,4) .. "****") .. "  |  App: " .. CONFIG.APP .. "  |  RightCtrl: abrir/fechar"

    showPage("Kaitun")
    return gui
end

-- =========================
-- BOOT
-- =========================
local function boot()
    log("Iniciando Blackgg...")
    local ok, reason = KeySystem:Init()
    if not ok then
        notify("Acesso negado: " .. tostring(reason))
        return
    end

    pcall(function()
        LocalPlayer.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)

    createUI()
    startAutoFarmLoop()
    startSpinLoop()
    notify("Blackgg carregado! RightControl abre/fecha.")
    log("Carregado com sucesso.", "ok")
end

boot()
