-- Loader v3 for kyle12314124/fischs :: fisch.lua
-- Paste into the executor, execute, done.
-- Mirror order matters: jsDelivr is not subject to raw.githubusercontent's
-- minutes-long cache, and the sha pin is immutable, so a stale CDN copy can
-- never win. A copy without the universe gate is treated as stale, not run.

local OWNER, REPO, FILE = "kyle12314124", "fischs", "fisch.lua"
local LOADER_VERSION = "loader3"
local PIN_SHA = "977e5e674be3add6a1cbce2498824ca79efbb663"
local CACHE_BUST = "?v=" .. tostring(os.time())

-- every release must contain this marker; a body without it is an old file
local MARKER = "UNIVERSE_ID"

local MIRRORS = {
    "https://cdn.jsdelivr.net/gh/%s/%s@main/%s" .. CACHE_BUST,
    "https://cdn.jsdelivr.net/gh/%s/%s@" .. PIN_SHA .. "/%s",
    "https://raw.githubusercontent.com/%s/%s/main/%s" .. CACHE_BUST,
    "https://raw.githubusercontent.com/%s/%s/master/%s",
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

local function usable(body)
    if type(body) ~= "string" or #body < 256 then return false end
    if string.find(body, "404: Not Found", 1, true) then return false end
    return string.find(body, MARKER, 1, true) ~= nil
end

-- game.HttpGet first: it exists in nearly every executor and follows redirects.
local function httpGet(url)
    local ok, body = pcall(function() return game:HttpGet(url, true) end)
    if ok and usable(body) then return body end

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
            if usable(body) then return body, nil end
            return nil, "stale or empty body (" .. tostring(#tostring(body)) .. " bytes)"
        end
    end

    return nil, tostring(body or "HttpGet unavailable")
end

print("[fisch:" .. LOADER_VERSION .. "] fetching " .. FILE)

local source, lastError

for _, template in ipairs(MIRRORS) do
    local url = string.format(template, OWNER, REPO, FILE)
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
