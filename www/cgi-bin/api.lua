#!/backk/bin/lua

-- Single CGI entry point for the JSON API. Replaces app.lua + CGILua/WSAPI.
local script_dir = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = script_dir .. "/?.lua;" .. script_dir .. "/?/init.lua;" .. package.path

local ok, err = pcall(function()
    require("api.router").handle()
end)

if not ok then
    local cgi = require "api.cgi"
    cgi.fail(500, "Internal error: " .. tostring(err))
end
