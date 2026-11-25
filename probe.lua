-- fisch probe — no UI, no render loop, no Drawing, no writes.
-- Three hotkeys, one dump each, printed before they run.
-- Run this first in a session, then paste what it finds into CONFIG in fisch.lua
-- if the auto-detection needs a nudge after a game update.
--   F6 = PlayerGui tree        (the minigame frame lives here)
--   F7 = bobber part candidates (the thing that dips on a bite)
--   F8 = merchant, tools, equipped rod

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
if not localPlayer then
    repeat task.wait(0.1) until Players.LocalPlayer
    localPlayer = Players.LocalPlayer
end

local VERSION = "probe1"
local MAX_LINES = 120

local function log(message)
    print("[fisch:probe] " .. message)
end

local function rootPart()
    local character = localPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function dumpGui()
    log("F6 — PlayerGui tree")
    local gui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not gui then
        log("no PlayerGui")
        return
    end

    local printed = 0
    local function walk(instance, depth)
        if printed >= MAX_LINES or depth > 4 then return end
        for _, child in ipairs(instance:GetChildren()) do
            if printed >= MAX_LINES then return end
            local size = ""
            if child:IsA("GuiObject") then
                local s = child.AbsoluteSize
                size = (" %dx%d%s"):format(s.X, s.Y, child.Visible and "" or " hidden")
            end
            printed += 1
            log(("%s%s [%s]%s"):format(string.rep("  ", depth), child.Name, child.ClassName, size))
            walk(child, depth + 1)
        end
    end

    walk(gui, 0)
    if printed >= MAX_LINES then log("… truncated at " .. MAX_LINES .. " lines") end
end

local function dumpBobbers()
    log("F7 — bobber candidates")
    local origin = rootPart()
    if not origin then
        log("no character")
        return
    end

    local found = 0
    local function consider(instance)
        if found >= MAX_LINES then return end
        if not instance:IsA("BasePart") then return end
        local name = string.lower(instance.Name)
        if string.find(name, "bobber", 1, true)
            or string.find(name, "float", 1, true)
            or string.find(name, "bait", 1, true) then
            found += 1
            local distance = (instance.Position - origin.Position).Magnitude
            log(("%s [%s] %.1f studs  parent=%s")
                :format(instance:GetFullName(), instance.ClassName, distance,
                    instance.Parent and instance.Parent.Name or "nil"))
        end
    end

    local character = localPlayer.Character
    if character then
        for _, descendant in ipairs(character:GetDescendants()) do consider(descendant) end
    end
    for _, descendant in ipairs(Workspace:GetDescendants()) do consider(descendant) end

    if found == 0 then
        log("no matching part — cast first, then press F7 again")
    end
end

local function dumpMerchant()
    log("F8 — merchant, tools, equipped")
    local origin = rootPart()

    local merchants = 0
    for _, descendant in ipairs(Workspace:GetDescendants()) do
        if descendant:IsA("Model") then
            local name = string.lower(descendant.Name)
            if string.find(name, "merchant", 1, true)
                or string.find(name, "vendor", 1, true)
                or string.find(name, "salesman", 1, true) then
                merchants += 1
                local anchor = descendant.PrimaryPart or descendant:FindFirstChildWhichIsA("BasePart")
                local distance = anchor and origin and (anchor.Position - origin.Position).Magnitude or -1
                log(("merchant %s  %.1f studs"):format(descendant:GetFullName(), distance))
                if merchants >= 20 then break end
            end
        end
    end
    if merchants == 0 then log("no merchant model found") end

    local character = localPlayer.Character
    local equipped = character and character:FindFirstChildWhichIsA("Tool")
    log("equipped: " .. (equipped and equipped.Name or "none"))

    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") then log("backpack: " .. tool.Name) end
        end
    end
end

log(VERSION .. " loaded — F6 gui tree, F7 bobbers, F8 merchant/tools")

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

    local ok, err = pcall(function()
        if input.KeyCode == Enum.KeyCode.F6 then dumpGui()
        elseif input.KeyCode == Enum.KeyCode.F7 then dumpBobbers()
        elseif input.KeyCode == Enum.KeyCode.F8 then dumpMerchant()
        end
    end)
    if not ok then log("dump threw: " .. tostring(err)) end
end)
