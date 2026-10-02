-- Route: GET /image (replaces get_image.cgi)
-- Same command/contract as legacy, but reachable only with a valid session
-- -- the legacy get_image.cgi had no auth check at all (see PROGRESS.md
-- "Décisions actées": fixed, not reproduced as-is).

local cgi = require "api.cgi"
local fnc = require "functions"
local paths = require "paths"

local M = {}

function M.get_image(req, username)
    local handle = io.popen(paths.mjsxj02hl .. " --get-image " .. paths.tmp_image .. " 2>&1")
    local message = handle and handle:read("*a") or ""
    local ok = handle ~= nil and handle:close()

    if ok then
        local data = fnc.file.get_contents(paths.tmp_image)
        os.remove(paths.tmp_image)
        cgi.send_raw(200, "image/jpeg", data or "")
    else
        cgi.send_raw(200, "text/html", "<h1>" .. (message or "") .. "</h1>")
    end
end

return M
