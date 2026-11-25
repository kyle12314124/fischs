-- fisch suite v1.0 — cast, bite, minigame, sell, movement, bobber ESP
-- Luau / executor context. One file, no external UI library.
-- Place 16732694052.
-- Input simulation only: nothing here names a RemoteEvent, so a game-side
-- rename cannot break the loop. Names that are read (bobber, minigame,
-- merchant) are discovered at runtime and overridable in CONFIG below.

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local VirtualInput     = game:GetService("VirtualInputManager")
local StarterGui       = game:GetService("StarterGui")
local Workspace        = game:GetService("Workspace")

local PLACE_ID = 16732694052
local VERSION  = "v1.0"

if game.PlaceId ~= PLACE_ID then
    warn(("[fisch] wrong place: %d (expected %d) — join the game first, then execute")
        :format(game.PlaceId, PLACE_ID))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "fisch",
            Text = ("wrong place (%d) — join Fisch, then execute"):format(game.PlaceId),
            Duration = 6,
        })
    end)
    return
end

local localPlayer = Players.LocalPlayer
if not localPlayer then
    repeat task.wait(0.1) until Players.LocalPlayer
    localPlayer = Players.LocalPlayer
end

-- per-instance liveness: a second execution must not kill the first one's loops
local alive = true

local CONFIG = {
    -- fishing
    AutoFish          = false,      -- safe boot: nothing runs until you arm it
    AutoEquipRod      = true,       -- equip the first Tool whose name reads like a rod
    RodPattern        = "rod",
    CastDelayMin      = 0.65,       -- seconds of jitter between casts
    CastDelayMax      = 1.55,
    CastTimeout       = 30,         -- give up if no bobber appears
    BiteTimeout       = 28,         -- give up waiting for a bite
    BiteDrop          = 0.35,       -- studs the bobber must fall to count as a bite
    BitePoll          = 0.03,
    MinigameTimeout   = 45,         -- hard ceiling on one minigame
    MinigamePoll      = 0.05,
    Deadband          = 0.045,      -- fraction of bar height; no steering inside
    LeadTime          = 0.09,       -- seconds of marker travel to aim ahead by
    ToggleFloor       = 0.05,       -- minimum seconds between press/release flips
    PulseHold         = 0.34,       -- fallback rhythm when the minigame cannot be read
    PulseRest         = 0.16,
    ReelClickDelay    = 0.12,

    -- selling
    AutoSell          = false,
    SellKey           = "E",        -- interact key; the merchant opens its own dialog
    SellRadius        = 6,          -- studs in front of the merchant to stand
    SellCycles        = 40,         -- click attempts before giving up
    SellInterval      = 0.45,

    -- movement
    SpeedEnabled      = false,
    WalkSpeed         = 48,
    JumpPower         = 50,
    TeleportOffset    = 6,

    -- visuals
    BobberESP         = false,
    ESPColor          = { 90, 200, 255 },
    ESPShowDistance   = true,

    -- keys
    MenuKeyName       = "RightShift",
    FishKeyName       = "F",
    PanicKeyName      = "End",
    HideKeyName       = "F2",
    HideOnFocusLost   = true,

    -- stability
    Telemetry         = true,       -- heartbeat print; the last line is the culprit
    RequirePlace      = true,

    -- name discovery overrides: leave empty and the probe file finds them,
    -- or paste exact names here after running probe.lua
    BobberNames       = { "bobber", "float", "fishingbobber", "bait" },
    MinigameNames     = { "fishingminigame", "minigame", "fishgame", "fishinggui", "reel" },
    MerchantNames     = { "merchant", "fishmerchant", "salesman", "vendor" },
    SellButtonWords   = { "sell all", "sellall", "sell" },
}

local DEFAULTS = {}
for key, value in pairs(CONFIG) do
    if type(value) == "table" then
        local copy = {}
        for index, inner in ipairs(value) do copy[index] = inner end
        DEFAULTS[key] = copy
    else
        DEFAULTS[key] = value
    end
end

local state = {
    stage          = "idle",        -- idle | casting | waiting | reeling | minigame | error
    casts          = 0,
    catches        = 0,
    startedAt      = os.clock(),
    running        = false,
    mouseDown      = false,
    mouseX         = 0,
    mouseY         = 0,
    lastFlip       = 0,
    bobber         = nil,
    bobberNext     = 0,
    espHighlight   = nil,
    espLabel       = nil,
    espOwner       = nil,
    minigameNext   = 0,
    minigameFrame  = nil,
    lastError      = "",
    telemetryNext  = 0,
    dragStart      = nil,
    dragOrigin     = nil,
    hidden         = false,
    savedPoint     = nil,
    conns          = {},
    statusLabel    = nil,
    statsLabel     = nil,
    stageLabel     = nil,
    chips          = {},
    gui            = nil,
}

-- ======================================================================
-- utilities
-- ======================================================================

local function log(message)
    print("[fisch] " .. message)
end

local function notify(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = "fisch", Text = text, Duration = 3 })
    end)
end

local function rgb(triple)
    return Color3.fromRGB(triple[1], triple[2], triple[3])
end

local function contains(haystack, needle)
    return string.find(string.lower(haystack), string.lower(needle), 1, true) ~= nil
end

local function matchesAny(name, patterns)
    for _, pattern in ipairs(patterns) do
        if contains(name, pattern) then return true end
    end
    return false
end

local function humanoid()
    local character = localPlayer.Character
    return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function rootPart()
    local character = localPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function camera()
    return Workspace.CurrentCamera
end

local function viewportCentre()
    local view = camera()
    if not view then return 256, 256 end
    local size = view.ViewportSize
    return math.floor(size.X * 0.5), math.floor(size.Y * 0.5)
end

local function elapsed()
    return os.clock() - state.startedAt
end

local function track(connection)
    table.insert(state.conns, connection)
    return connection
end

-- ======================================================================
-- input: VirtualInputManager first, executor mouse helpers second.
-- Both are wrapped: a missing destroyer must not throw inside the cast loop.
-- ======================================================================

local function mouseRelease()
    if not state.mouseDown then return end
    state.mouseDown = false
    local x, y = state.mouseX, state.mouseY
    local ok = pcall(function() VirtualInput:SendMouseButtonEvent(x, y, 0, false, game, 1) end)
    if not ok and type(mouse1release) == "function" then
        pcall(mouse1release)
    end
end

local function mousePress(x, y)
    if state.mouseDown then
        if state.mouseX == x and state.mouseY == y then return end
        mouseRelease()
    end
    local ok = pcall(function() VirtualInput:SendMouseButtonEvent(x, y, 0, true, game, 1) end)
    if not ok then
        if type(mouse1press) == "function" then
            pcall(mouse1press)
        else
            state.lastError = "no mouse injection"
            return
        end
    end
    state.mouseDown, state.mouseX, state.mouseY = true, x, y
    state.lastFlip = os.clock()
end

local function mouseClick(x, y)
    if not x or not y then
        x, y = viewportCentre()
    end
    mousePress(x, y)
    task.wait(0.045)
    mouseRelease()
end

local function clickCentre()
    mouseClick(viewportCentre())
end

local function sendKey(keyName)
    local key = Enum.KeyCode[keyName]
    if not key then return false end
    local ok = pcall(function() VirtualInput:SendKeyEvent(true, key, false, game) end)
    if not ok then return false end
    task.wait(0.06)
    pcall(function() VirtualInput:SendKeyEvent(false, key, false, game) end)
    return true
end

-- ======================================================================
-- bobber discovery: nearest part whose name reads like a bobber.
-- Cached for 250 ms; the scan is bounded so a busy workspace cannot stall.
-- ======================================================================

local function findBobber()
    local origin = rootPart()
    if not origin then return nil end

    local best, bestDistance = nil, math.huge
    local scanned = 0

    local function consider(instance)
        if scanned > 4000 then return end
        scanned += 1
        if not instance:IsA("BasePart") then return end
        if not matchesAny(instance.Name, CONFIG.BobberNames) then return end
        local distance = (instance.Position - origin.Position).Magnitude
        if distance < bestDistance and distance < 260 then
            best, bestDistance = instance, distance
        end
    end

    local character = localPlayer.Character
    if character then
        for _, descendant in ipairs(character:GetDescendants()) do consider(descendant) end
    end

    local container = Workspace:FindFirstChild("Objects") or Workspace
    for _, descendant in ipairs(container:GetDescendants()) do
        consider(descendant)
        if scanned > 4000 then break end
    end

    return best
end

local function currentBobber()
    if state.bobber and state.bobber.Parent then return state.bobber end
    if os.clock() < state.bobberNext then return state.bobber end
    state.bobberNext = os.clock() + 0.25
    state.bobber = findBobber()
    return state.bobber
end

-- ======================================================================
-- minigame: found by name, then classified by observation.
-- The bar is the object that moves when we hold; the marker is the one that
-- moves on its own. No hard-coded GUI paths, so a restyle cannot break it.
-- ======================================================================

local function playerGui()
    return localPlayer:FindFirstChildOfClass("PlayerGui")
end

local function findNamedMinigame()
    local gui = playerGui()
    if not gui then return nil end
    for _, descendant in ipairs(gui:GetDescendants()) do
        if descendant:IsA("GuiObject") and descendant.Visible
            and matchesAny(descendant.Name, CONFIG.MinigameNames) then
            return descendant
        end
    end
    return nil
end

-- Geometric fallback: a visible frame with real children that is not the
-- full screen. Only consulted after the reel click, so a shop dialog can
-- never be mistaken for a bite.
local function findShapedMinigame()
    local gui = playerGui()
    local view = camera()
    if not gui or not view then return nil end

    local limitX = view.ViewportSize.X * 0.95
    local best, bestScore = nil, 0

    for _, descendant in ipairs(gui:GetDescendants()) do
        if descendant:IsA("GuiObject") and descendant.Visible then
            local size = descendant.AbsoluteSize
            if size.X > 180 and size.Y > 100 and size.X < limitX then
                local children = 0
                for _, child in ipairs(descendant:GetChildren()) do
                    if child:IsA("GuiObject") then children += 1 end
                end
                local score = children * 1000 + size.X * size.Y / 1000
                if children >= 3 and score > bestScore then
                    best, bestScore = descendant, score
                end
            end
        end
    end
    return best
end

local function findMinigame(allowShaped)
    if state.minigameFrame and state.minigameFrame.Parent and state.minigameFrame.Visible then
        return state.minigameFrame
    end
    if os.clock() < state.minigameNext then return nil end
    state.minigameNext = os.clock() + 0.1
    state.minigameFrame = findNamedMinigame()
    if not state.minigameFrame and allowShaped then
        state.minigameFrame = findShapedMinigame()
    end
    return state.minigameFrame
end

local function snapshot(container)
    local list, positions = {}, {}
    local count = 0
    for _, descendant in ipairs(container:GetDescendants()) do
        if descendant:IsA("GuiObject") and descendant.Visible then
            local size = descendant.AbsoluteSize
            if size.Y > 2 and size.X > 2 then
                count += 1
                list[count] = descendant
                positions[descendant] = descendant.AbsolutePosition
                if count >= 200 then break end
            end
        end
    end
    return list, positions
end

local function midY(instance)
    local position, size = instance.AbsolutePosition, instance.AbsoluteSize
    return position.Y + size.Y * 0.5
end

-- Press once, see what moved. Returns bar, marker, holdRaises.
local function calibrate(frame)
    local list, before = snapshot(frame)
    if #list < 2 then return nil end

    local cx, cy = viewportCentre()
    mousePress(cx, cy)
    task.wait(0.18)
    local _, during = snapshot(frame)
    mouseRelease()
    task.wait(0.12)
    local _, after = snapshot(frame)

    local bar, barDelta = nil, 0
    local marker, markerDelta = nil, 0

    for _, instance in ipairs(list) do
        local start = before[instance]
        local held = during[instance]
        local later = after[instance]
        if start and held then
            local delta = math.abs(held.Y - start.Y)
            if delta > barDelta then bar, barDelta = instance, delta end
        end
        if held and later then
            local delta = math.abs(later.Y - held.Y)
            if delta > markerDelta and instance ~= bar then
                marker, markerDelta = instance, delta
            end
        end
    end

    if not bar then return nil end

    local holdRaises = false
    local start = before[bar]
    local held = during[bar]
    if start and held then holdRaises = held.Y < start.Y end

    return bar, marker, holdRaises
end

local function pulseMinigame(frame)
    local start = os.clock()
    while frame.Parent and frame.Visible and alive do
        if os.clock() - start > CONFIG.MinigameTimeout then break end
        mousePress(viewportCentre())
        task.wait(CONFIG.PulseHold)
        mouseRelease()
        task.wait(CONFIG.PulseRest)
    end
    mouseRelease()
end

local function solveMinigame(frame)
    local bar, marker, holdRaises = calibrate(frame)
    if not bar or not marker then
        pulseMinigame(frame)
        return
    end

    local start = os.clock()
    local lastMarkerY = midY(marker)
    local markerVelocity = 0

    while frame.Parent and frame.Visible and alive do
        if os.clock() - start > CONFIG.MinigameTimeout then break end

        local my = midY(bar)
        local barHeight = bar.AbsoluteSize.Y
        local deadband = math.max(barHeight * CONFIG.Deadband, 1.5)

        local markerY = midY(marker)
        markerVelocity = markerVelocity * 0.7 + (markerY - lastMarkerY) * 0.3 * (1 / CONFIG.MinigamePoll)
        lastMarkerY = markerY

        local target = markerY + markerVelocity * CONFIG.LeadTime
        local wantsHold
        if holdRaises then
            wantsHold = my > target + deadband
        else
            wantsHold = my < target - deadband
        end

        if os.clock() - state.lastFlip >= CONFIG.ToggleFloor then
            if wantsHold and not state.mouseDown then
                mousePress(viewportCentre())
            elseif not wantsHold and state.mouseDown then
                mouseRelease()
            end
        end

        task.wait(CONFIG.MinigamePoll)
    end

    mouseRelease()
end

-- ======================================================================
-- tools, selling, movement
-- ======================================================================

local function equipRod()
    if not CONFIG.AutoEquipRod then return false end
    local character = localPlayer.Character
    local human = humanoid()
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    if not (character and human and backpack) then return false end

    local equipped = character:FindFirstChildWhichIsA("Tool")
    if equipped and contains(equipped.Name, CONFIG.RodPattern) then return true end

    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and contains(tool.Name, CONFIG.RodPattern) then
            local ok = pcall(function() human:EquipTool(tool) end)
            if ok then
                task.wait(0.2)
                return true
            end
        end
    end
    return false
end

local function findMerchant()
    local origin = rootPart()
    if not origin then return nil end
    local best, bestDistance = nil, math.huge
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("Model") and matchesAny(descendant.Name, CONFIG.MerchantNames) then
            local anchor = descendant.PrimaryPart or descendant:FindFirstChildWhichIsA("BasePart")
            if anchor then
                local distance = (anchor.Position - origin.Position).Magnitude
                if distance < bestDistance then best, bestDistance = anchor, distance end
            end
        end
    end
    return best
end

local function findSellButton()
    local gui = playerGui()
    if not gui then return nil end
    for _, descendant in ipairs(gui:GetDescendants()) do
        if (descendant:IsA("TextButton") or descendant:IsA("ImageButton"))
            and descendant.Visible and descendant.Active then
            local haystack = descendant.Name
            if descendant:IsA("TextButton") then haystack ..= " " .. descendant.Text end
            for _, word in ipairs(CONFIG.SellButtonWords) do
                if contains(haystack, word) then return descendant end
            end
        end
    end
    return nil
end

local function sellOnce()
    local merchant = findMerchant()
    local character = rootPart()
    local human = humanoid()
    if not (merchant and character and human) then
        notify("merchant not found")
        return false
    end

    -- stand in front of the merchant, facing it
    local stand = CFrame.lookAt(
        merchant.Position + Vector3.new(0, 0, CONFIG.SellRadius),
        merchant.Position
    )
    pcall(function() character.CFrame = stand end)
    task.wait(0.8)

    sendKey(CONFIG.SellKey)
    task.wait(0.6)

    for _ = 1, CONFIG.SellCycles do
        if not (CONFIG.AutoSell and alive) then break end
        local button = findSellButton()
        if button then
            local position, size = button.AbsolutePosition, button.AbsoluteSize
            mouseClick(position.X + size.X * 0.5, position.Y + size.Y * 0.5)
        else
            sendKey(CONFIG.SellKey)
        end
        task.wait(CONFIG.SellInterval)
        if not findSellButton() then break end
    end

    mouseRelease()
    return true
end

local function applyMovement()
    local human = humanoid()
    if not human then return end
    if CONFIG.SpeedEnabled then
        human.WalkSpeed = CONFIG.WalkSpeed
        pcall(function()
            human.UseJumpPower = true
            human.JumpPower = CONFIG.JumpPower
        end)
    else
        human.WalkSpeed = 16
        pcall(function()
            human.UseJumpPower = true
            human.JumpPower = 50
        end)
    end
end

local function savePoint()
    local character = rootPart()
    if character then
        state.savedPoint = character.CFrame
        notify("point saved")
    end
end

local function gotoPoint()
    local character = rootPart()
    if character and state.savedPoint then
        character.CFrame = state.savedPoint
    else
        notify("no saved point")
    end
end

-- ======================================================================
-- bobber ESP: one Highlight, one BillboardGui, both provisional
-- ======================================================================

local function clearESP()
    if state.espHighlight then
        pcall(function() state.espHighlight:Destroy() end)
        state.espHighlight = nil
    end
    if state.espLabel then
        pcall(function() state.espLabel:Destroy() end)
        state.espLabel = nil
    end
    state.espOwner = nil
end

local function updateESP()
    if not CONFIG.BobberESP or state.hidden then
        if state.espHighlight or state.espLabel then clearESP() end
        return
    end

    local bobber = currentBobber()
    if not bobber then
        if state.espHighlight or state.espLabel then clearESP() end
        return
    end

    if state.espOwner ~= bobber then
        clearESP()
        state.espOwner = bobber

        local highlight = Instance.new("Highlight")
        highlight.Name = "FischBobberESP"
        highlight.FillColor = rgb(CONFIG.ESPColor)
        highlight.FillTransparency = 0.55
        highlight.OutlineColor = rgb(CONFIG.ESPColor)
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Adornee = bobber
        highlight.Parent = bobber
        state.espHighlight = highlight

        if CONFIG.ESPShowDistance then
            local billboard = Instance.new("BillboardGui")
            billboard.Name = "FischBobberLabel"
            billboard.Size = UDim2.fromOffset(90, 18)
            billboard.StudsOffset = Vector3.new(0, 1.4, 0)
            billboard.AlwaysOnTop = true
            billboard.Parent = bobber

            local label = Instance.new("TextLabel")
            label.Size = UDim2.fromScale(1, 1)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.Code
            label.TextSize = 12
            label.TextColor3 = rgb(CONFIG.ESPColor)
            label.Text = ""
            label.Parent = billboard
            state.espLabel = label
        end
    end

    if state.espLabel and state.espLabel.Parent then
        local origin = rootPart()
        if origin then
            local distance = (bobber.Position - origin.Position).Magnitude
            state.espLabel.Text = ("bobber %.0f"):format(distance)
        end
    end
end

-- ======================================================================
-- the cast cycle
-- ======================================================================

local function waitForBite(bobber)
    local lastY = bobber.Position.Y
    local start = os.clock()

    while os.clock() - start < CONFIG.BiteTimeout do
        if not alive or not CONFIG.AutoFish then return false end

        if findMinigame() then return true end
        if not bobber.Parent then return true end

        local position = bobber.Position
        if lastY - position.Y > CONFIG.BiteDrop then return true end
        lastY = position.Y

        task.wait(CONFIG.BitePoll)
    end
    return false
end

local function castOnce()
    local human = humanoid()
    if not human or human.Health <= 0 then return end

    equipRod()

    state.stage = "casting"
    clickCentre()

    local bobber = currentBobber()
    local start = os.clock()
    while not bobber and os.clock() - start < CONFIG.CastTimeout do
        if not (alive and CONFIG.AutoFish) then return end
        task.wait(0.15)
        bobber = currentBobber()
    end

    if not bobber then
        state.stage = "no bobber"
        return
    end

    state.stage = "waiting"
    if not waitForBite(bobber) then
        state.stage = "no bite"
        return
    end

    state.stage = "reeling"
    clickCentre()
    task.wait(CONFIG.ReelClickDelay)

    local frame = nil
    start = os.clock()
    while not frame and os.clock() - start < 6 do
        frame = findMinigame()
        if not frame then task.wait(0.08) end
    end

    if frame then
        state.stage = "minigame"
        solveMinigame(frame)
        state.catches += 1
        state.minigameFrame = nil
    end

    state.casts += 1
    state.stage = "idle"
    state.bobber = nil
end

local function fishLoop()
    if state.running then return end
    state.running = true
    task.spawn(function()
        while alive and CONFIG.AutoFish do
            local ok, err = pcall(castOnce)
            if not ok then
                state.stage = "error"
                state.lastError = tostring(err)
                log("cast threw: " .. tostring(err))
                mouseRelease()
                task.wait(1.2)
            end
            task.wait(CONFIG.CastDelayMin + math.random() * (CONFIG.CastDelayMax - CONFIG.CastDelayMin))
        end
        state.running = false
        state.stage = "idle"
        mouseRelease()
    end)
end

-- ======================================================================
-- gui
-- ======================================================================

-- gethui keeps the panel out of PlayerGui's reset pass; PlayerGui and CoreGui are
-- the fallbacks for executors that expose neither. A nil parent is a silent
-- no-show, so every rung is probed and the last one cannot be nil.
local function resolveGuiParent()
    local env = getgenv and getgenv()
    if env and type(env.gethui) == "function" then
        local ok, result = pcall(env.gethui)
        if ok and result then return result, "gethui" end
    end
    if type(gethui) == "function" then
        local ok, result = pcall(gethui)
        if ok and result then return result, "gethui" end
    end
    local guiParent = playerGui()
    if guiParent then return guiParent, "PlayerGui" end
    return game:GetService("CoreGui"), "CoreGui"
end

log("milestone: building gui")
local parentGui, parentName = resolveGuiParent()
log("milestone: gui parent = " .. tostring(parentName))

local previous = parentGui and parentGui:FindFirstChild("FischSuite")
if previous then previous:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "FischSuite"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999
gui.Parent = parentGui
state.gui = gui
log("milestone: panel mounted")

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(252, 268)
main.Position = UDim2.fromOffset(26, 116)
main.BackgroundColor3 = Color3.fromRGB(15, 16, 19)
main.BackgroundTransparency = 0.06
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 9)
mainCorner.Parent = main

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = Color3.fromRGB(25, 27, 32)
titleBar.BorderSizePixel = 0
titleBar.Parent = main

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 9)
titleCorner.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -104, 1, 0)
title.Position = UDim2.fromOffset(12, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextColor3 = Color3.fromRGB(214, 218, 226)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "fisch " .. VERSION
title.Parent = titleBar

local function chip(text, parent, size)
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(size or 46, 20)
    button.BackgroundColor3 = Color3.fromRGB(38, 40, 46)
    button.BorderSizePixel = 0
    button.Font = Enum.Font.Gotham
    button.TextSize = 10
    button.TextColor3 = Color3.fromRGB(178, 183, 193)
    button.Text = text
    button.AutoButtonColor = true
    button.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = button
    return button
end

local hideChip = chip("HIDE", titleBar, 42)
hideChip.Position = UDim2.new(1, -92, 0, 5)

local panicChip = chip("PANIC", titleBar, 46)
panicChip.Position = UDim2.new(1, -46, 0, 5)

local row = Instance.new("Frame")
row.Size = UDim2.new(1, -20, 0, 24)
row.Position = UDim2.fromOffset(10, 38)
row.BackgroundTransparency = 1
row.Parent = main

local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.Padding = UDim.new(0, 5)
rowLayout.Parent = row

local toggleChips = {}

local function setChip(button, on)
    button.BackgroundColor3 = on and Color3.fromRGB(34, 84, 58) or Color3.fromRGB(38, 40, 46)
    button.TextColor3 = on and Color3.fromRGB(150, 235, 178) or Color3.fromRGB(178, 183, 193)
end

local function addToggleChip(text, get, set)
    local button = chip(text, row, 44)
    toggleChips[text] = function() setChip(button, get()) end
    button.MouseButton1Click:Connect(function()
        local ok, err = pcall(function() set(not get()) end)
        if not ok then log("chip error: " .. tostring(err)) end
        setChip(button, get())
    end)
    setChip(button, get())
    return button
end

addToggleChip("FISH", function() return CONFIG.AutoFish end, function(value)
    CONFIG.AutoFish = value
    if value then
        fishLoop()
    else
        mouseRelease()
    end
end)

addToggleChip("SELL", function() return CONFIG.AutoSell end, function(value)
    CONFIG.AutoSell = value
    if value then task.spawn(sellOnce) end
end)

addToggleChip("SPEED", function() return CONFIG.SpeedEnabled end, function(value)
    CONFIG.SpeedEnabled = value
    applyMovement()
end)

addToggleChip("ESP", function() return CONFIG.BobberESP end, function(value)
    CONFIG.BobberESP = value
    if not value then clearESP() end
end)

local list = Instance.new("Frame")
list.Size = UDim2.new(1, -20, 0, 96)
list.Position = UDim2.fromOffset(10, 70)
list.BackgroundTransparency = 1
list.Parent = main

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

local function addButton(text, order, handler)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, 24)
    button.BackgroundColor3 = Color3.fromRGB(32, 34, 39)
    button.BorderSizePixel = 0
    button.Font = Enum.Font.Gotham
    button.TextSize = 11
    button.TextColor3 = Color3.fromRGB(188, 193, 203)
    button.Text = text
    button.LayoutOrder = order
    button.Parent = list

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = button

    button.MouseButton1Click:Connect(function()
        local ok, err = pcall(handler)
        if not ok then log("button error: " .. tostring(err)) end
    end)
    return button
end

addButton("save point", 1, savePoint)
addButton("goto point", 2, gotoPoint)
addButton("dump names to console", 3, function()
    local bobber = findBobber()
    log("bobber: " .. (bobber and bobber:GetFullName() or "none"))
    local frame = findNamedMinigame()
    log("minigame: " .. (frame and frame:GetFullName() or "none"))
    local merchant = findMerchant()
    log("merchant: " .. (merchant and merchant:GetFullName() or "none"))
    local tool = localPlayer.Character and localPlayer.Character:FindFirstChildWhichIsA("Tool")
    log("equipped: " .. (tool and tool.Name or "none"))
end)

local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, -20, 0, 1)
divider.Position = UDim2.fromOffset(10, 172)
divider.BackgroundColor3 = Color3.fromRGB(44, 47, 54)
divider.BorderSizePixel = 0
divider.Parent = main

state.stageLabel = Instance.new("TextLabel")
state.stageLabel.Size = UDim2.new(1, -20, 0, 20)
state.stageLabel.Position = UDim2.fromOffset(10, 180)
state.stageLabel.BackgroundTransparency = 1
state.stageLabel.Font = Enum.Font.Code
state.stageLabel.TextSize = 11
state.stageLabel.TextColor3 = Color3.fromRGB(128, 133, 143)
state.stageLabel.TextXAlignment = Enum.TextXAlignment.Left
state.stageLabel.Text = "stage idle"
state.stageLabel.Parent = main

state.statsLabel = Instance.new("TextLabel")
state.statsLabel.Size = UDim2.new(1, -20, 0, 20)
state.statsLabel.Position = UDim2.fromOffset(10, 200)
state.statsLabel.BackgroundTransparency = 1
state.statsLabel.Font = Enum.Font.Code
state.statsLabel.TextSize = 11
state.statsLabel.TextColor3 = Color3.fromRGB(128, 133, 143)
state.statsLabel.TextXAlignment = Enum.TextXAlignment.Left
state.statsLabel.Text = "casts 0  catches 0"
state.statsLabel.Parent = main

state.statusLabel = Instance.new("TextLabel")
state.statusLabel.Size = UDim2.new(1, -20, 0, 28)
state.statusLabel.Position = UDim2.fromOffset(10, 226)
state.statusLabel.BackgroundTransparency = 1
state.statusLabel.Font = Enum.Font.Code
state.statusLabel.TextSize = 10
state.statusLabel.TextWrapped = true
state.statusLabel.TextColor3 = Color3.fromRGB(96, 100, 110)
state.statusLabel.TextXAlignment = Enum.TextXAlignment.Left
state.statusLabel.TextYAlignment = Enum.TextYAlignment.Top
state.statusLabel.Text = "RightShift menu · F fish · F2 hide · End unload"
state.statusLabel.Parent = main

-- drag
local function beginDrag(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
    state.dragStart = input.Position
    state.dragOrigin = main.Position
end

local function moveDrag(input)
    if not state.dragStart then return end
    local delta = input.Position - state.dragStart
    main.Position = UDim2.fromOffset(
        state.dragOrigin.X.Offset + delta.X,
        state.dragOrigin.Y.Offset + delta.Y
    )
end

titleBar.InputBegan:Connect(beginDrag)
titleBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then moveDrag(input) end
end)
UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then moveDrag(input) end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        state.dragStart = nil
    end
end)

-- ======================================================================
-- hide mode and unload
-- ======================================================================

local function setHidden(value)
    state.hidden = value
    gui.Enabled = not value
    if value then clearESP() end
    setChip(hideChip, value)
end

local function shutdown()
    if not alive then return end
    alive = false
    CONFIG.AutoFish = false
    CONFIG.AutoSell = false
    mouseRelease()
    clearESP()

    for _, connection in ipairs(state.conns) do
        pcall(function() connection:Disconnect() end)
    end
    state.conns = {}

    local human = humanoid()
    if human then
        pcall(function() human.WalkSpeed = 16 end)
    end

    pcall(function() gui:Destroy() end)

    local env = getgenv and getgenv()
    if env and env.__fischShutdown == shutdown then env.__fischShutdown = nil end

    notify("unloaded")
    log("unloaded")
end

local env = getgenv and getgenv()
if env then env.__fischShutdown = shutdown end

hideChip.MouseButton1Click:Connect(function() setHidden(not state.hidden) end)
panicChip.MouseButton1Click:Connect(shutdown)

-- ======================================================================
-- loops and keys
-- ======================================================================

track(RunService.Heartbeat:Connect(function()
    if not alive then return end

    local now = os.clock()

    if now >= state.telemetryNext then
        state.telemetryNext = now + 5
        if CONFIG.Telemetry then
            log(("stage=%s casts=%d catches=%d up=%ds")
                :format(state.stage, state.casts, state.catches, math.floor(elapsed())))
        end
    end

    updateESP()

    local human = humanoid()
    if human and (CONFIG.SpeedEnabled and human.WalkSpeed ~= CONFIG.WalkSpeed) then
        human.WalkSpeed = CONFIG.WalkSpeed
    end

    if state.stageLabel then
        state.stageLabel.Text = ("stage %s"):format(state.stage)
    end
    if state.statsLabel then
        state.statsLabel.Text = ("casts %d  catches %d  %dm%02ds")
            :format(state.casts, state.catches, math.floor(elapsed() / 60), math.floor(elapsed() % 60))
    end
end))

track(UserInputService.InputBegan:Connect(function(input, processed)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

    local key = input.KeyCode.Name

    if key == CONFIG.PanicKeyName then
        shutdown()
        return
    end

    if processed then return end

    if key == CONFIG.MenuKeyName then
        main.Visible = not main.Visible
    elseif key == CONFIG.HideKeyName then
        setHidden(not state.hidden)
    elseif key == CONFIG.FishKeyName then
        CONFIG.AutoFish = not CONFIG.AutoFish
        if CONFIG.AutoFish then fishLoop() else mouseRelease() end
        if toggleChips.FISH then toggleChips.FISH() end
    end
end))

track(UserInputService.WindowFocusReleased:Connect(function()
    if CONFIG.HideOnFocusLost and not state.hidden then setHidden(true) end
end))

track(localPlayer.CharacterAdded:Connect(function()
    mouseRelease()
    task.wait(1)
    applyMovement()
end))

applyMovement()
log("milestone: loops bound")
log(("%s loaded — RightShift menu, F fish, F2 hide, End unload"):format(VERSION))
notify("fisch " .. VERSION .. " loaded")
