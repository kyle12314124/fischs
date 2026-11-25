-- fisch doctor — run this when the suite loads but nothing appears.
-- Read-only apart from one throwaway ScreenGui it creates and removes.
-- Prints one line per capability so the first failing line names the culprit.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local function log(message) print("[fisch:diag] " .. message) end

local function capability(name, present, detail)
    log(("%-18s %s%s"):format(name, present and "ok" or "MISSING", detail and ("  " .. detail) or ""))
end

local function safeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil, tostring(result)
end

log("start")
log("place        " .. tostring(game.PlaceId))
log("game         " .. tostring(game.Name))
log("job          " .. tostring(game.JobId))
log("player       " .. tostring(Players.LocalPlayer and Players.LocalPlayer.Name))

local executor = safeCall(function()
    if type(identifyexecutor) == "function" then return identifyexecutor() end
    if type(getexecutorname) == "function" then return getexecutorname() end
    return "unknown"
end)
log("executor     " .. tostring(executor))

capability("httpget", type(game.HttpGet) == "function")
capability("loadstring", type(loadstring) == "function" or type(load) == "function")
capability("getgenv", type(getgenv) == "function")
capability("gethui", type(gethui) == "function")
capability("writefile", type(writefile) == "function")
capability("VirtualInput", type(game:GetService("VirtualInputManager")) == "table")

local requester =
    (type(syn) == "table" and type(syn.request) == "function" and "syn.request")
    or (type(request) == "function" and "request")
    or (type(http_request) == "function" and "http_request")
    or nil
capability("request", requester ~= nil, requester or "none found")

-- transport check against the real repo
local probeUrl = "https://raw.githubusercontent.com/kyle12314124/fischs/main/README.md"
local body, err = safeCall(function() return game:HttpGet(probeUrl, true) end)
if type(body) == "string" and #body > 0 and not string.find(body, "404: Not Found", 1, true) then
    log("fetch        ok, " .. #body .. " bytes from raw.githubusercontent.com")
else
    log("fetch        FAILED — " .. tostring(err))
end

-- compile check without executing
local source = safeCall(function() return game:HttpGet(
    "https://raw.githubusercontent.com/kyle12314124/fischs/main/fisch.lua", true) end)
if type(source) == "string" and #source > 100 then
    local compile = loadstring or load
    local chunk, compileError = compile(source)
    if chunk then
        log("compile      ok, " .. #source .. " bytes")
    else
        log("compile      FAILED — " .. tostring(compileError))
    end
else
    log("compile      skipped, source not fetched")
end

-- GUI mount check: the exact thing that makes the panel invisible
log("gui          mounting test panel")
local parent = nil
if type(getgenv) == "function" then
    local env = safeCall(getgenv)
    if type(env) == "table" and type(env.gethui) == "function" then
        parent = safeCall(env.gethui)
    end
end
if not parent and type(gethui) == "function" then parent = safeCall(gethui) end
if not parent then parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui") end
if not parent then parent = game:GetService("CoreGui") end

if not parent then
    log("gui          NO PARENT — this is why nothing shows")
else
    local test = Instance.new("ScreenGui")
    test.Name = "FischDiagPanel"
    test.ResetOnSpawn = false
    test.DisplayOrder = 999
    local ok, reason = pcall(function() test.Parent = parent end)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromOffset(260, 44)
    label.Position = UDim2.fromOffset(24, 24)
    label.BackgroundColor3 = Color3.fromRGB(12, 13, 16)
    label.BackgroundTransparency = 0.1
    label.TextColor3 = Color3.fromRGB(120, 220, 255)
    label.Font = Enum.Font.Code
    label.TextSize = 12
    label.Text = "fisch diag: panel mounts\nthis box should be visible"
    label.Parent = test
    task.wait(0.4)
    log("gui          parent=" .. tostring(test.Parent) .. " visible=" .. tostring(test.Enabled)
        .. (ok and "" or ("  error=" .. tostring(reason))))
    task.wait(4)
    test:Destroy()
    log("gui          test panel removed")
end

log("done — if fetch and compile are ok but the panel never appeared, "
    .. "the executor is stripping ScreenGui; run the suite from gethui or CoreGui")

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "fisch diag",
        Text = "check console (F9) — done",
        Duration = 5,
    })
end)
