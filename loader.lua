-- Loader for kyle12314124/fischs :: fisch.lua
-- Paste into the executor, execute, done.

local OWNER, REPO, FILE = "kyle12314124", "fischs", "fisch.lua"
local CACHE_BUST = "?v=" .. tostring(os.time())

local MIRRORS = {
    "https://raw.githubusercontent.com/%s/%s/main/%s%s",
    "https://raw.githubusercontent.com/%s/%s/master/%s%s",
    "https://cdn.jsdelivr.net/gh/%s/%s@main/%s%s",
}

local source, lastError

for _, template in ipairs(MIRRORS) do
    local url = string.format(template, OWNER, REPO, FILE, CACHE_BUST)
    local ok, body = pcall(game.HttpGet, game, url)

    if ok and type(body) == "string" and #body > 0
        and not string.find(body, "404: Not Found", 1, true) then
        source = body
        break
    end

    lastError = body
end

if not source then
    warn("[fisch] source unreachable: " .. tostring(lastError))
    return
end

local chunk, compileError = loadstring(source)

if not chunk then
    warn("[fisch] compile failed: " .. tostring(compileError))
    return
end

chunk()
