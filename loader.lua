-- Loader v2 for kyle12314124/fischs :: fisch.lua
-- Paste into the executor, execute, done.
-- Failures are reported on screen as well as in the console: a silent loader
-- is indistinguishable from a dead one.

local OWNER, REPO, FILE = "kyle12314124", "fischs", "fisch.lua"
local LOADER_VERSION = "loader2"
local CACHE_BUST = "?v=" .. tostring(os.time())

local MIRRORS = {
    "https://raw.githubusercontent.com/%s/%s/main/%s%s",
    "https://raw.githubusercontent.com/%s/%s/master/%s%s",
    "https://cdn.jsdelivr.net/gh/%s/%s@main/%s%s",
}

local function notify(text, duration)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "fisch " .. LOADER_VERSION,
            Text = text,
            Duration = duration or 8,
        })
    end)
end

local function clean(body)
    return type(body) == "string" and #body > 0
        and not string.find(body, "404: Not Found", 1, true)
end

-- game.HttpGet first: it exists in nearly every executor and follows redirects.
local function httpGet(url)
    local ok, body = pcall(function() return game:HttpGet(url, true) end)
    if ok and clean(body) then return body end

    local requester
    if type(syn) == "table" and type(syn.request) == "function" then
        requester = syn.request
    elseif type(http) == "table" and type(http.request) == "function" then
        requester = http.request
    elseif type(request) == "function" then
        requester = request
    elseif type(http_request) == "function" then
        requester = http_request
    elseif type(fluxus) == "table" and type(fluxus.request) == "function" then
        requester = fluxus.request
    end

    if requester then
        local ok2, response = pcall(requester, { Url = url, Method = "GET" })
        if ok2 and type(response) == "table" then
            local body = response.Body or response.body
            if clean(body) then return body, nil end
            return nil, tostring(response.StatusCode or response.Status or "no body")
        end
    end

    return nil, tostring(body or "HttpGet unavailable")
end

print("[fisch:" .. LOADER_VERSION .. "] fetching " .. FILE)

local source, lastError

for _, template in ipairs(MIRRORS) do
    local url = string.format(template, OWNER, REPO, FILE, CACHE_BUST)
    local body, err = httpGet(url)
    if body then
        source = body
        print("[fisch:" .. LOADER_VERSION .. "] fetched from " .. url)
        break
    end
    lastError = err
    print("[fisch:" .. LOADER_VERSION .. "] mirror failed: " .. tostring(err))
end

if not source then
    warn("[fisch] source unreachable: " .. tostring(lastError))
    notify("source unreachable — open the console (F9)")
    return
end

local compile = loadstring or load
local chunk, compileError = compile(source)

if not chunk then
    warn("[fisch] compile failed: " .. tostring(compileError))
    notify("compile failed — open the console (F9)")
    return
end

print("[fisch:" .. LOADER_VERSION .. "] compiling ok, running")

local ok, runtimeError = pcall(chunk)
if not ok then
    warn("[fisch] runtime error: " .. tostring(runtimeError))
    notify("runtime error — open the console (F9)")
end
