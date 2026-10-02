-- Minimal CGI request/response helpers for the JSON API.
-- Replaces CGILua/WSAPI: talks the plain CGI/1.1 protocol directly
-- (env vars in, "Status:"/headers + blank line + body out on stdout).

local cgi = {}

-- Request -------------------------------------------------------------

local function url_decode(str)
    str = str:gsub("+", " ")
    str = str:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    return str
end

local function parse_query(str)
    local params = {}
    if not str or str == "" then return params end
    for pair in str:gmatch("[^&]+") do
        local k, v = pair:match("^([^=]*)=?(.*)$")
        if k and k ~= "" then
            params[url_decode(k)] = url_decode(v or "")
        end
    end
    return params
end

local function parse_cookies(str)
    local cookies = {}
    if not str then return cookies end
    for pair in str:gmatch("[^;]+") do
        local k, v = pair:match("^%s*([^=]+)=(.*)$")
        if k then cookies[k] = v end
    end
    return cookies
end

-- Reads the request body from stdin (binary-safe, exact CONTENT_LENGTH bytes).
local function read_body()
    local length = tonumber(os.getenv("CONTENT_LENGTH") or "0") or 0
    if length <= 0 then return "" end
    return io.stdin:read(length) or ""
end

-- Builds the request table for the current CGI invocation.
--
-- IMPORTANT: for multipart/form-data requests, stdin is deliberately left
-- UNREAD here (no req.body_raw, no req.files). Those requests are file
-- uploads (up to ~12 MB for a firmware image) on a device with a couple MB
-- of free RAM at best -- buffering the whole body as a Lua string would risk
-- OOMing the camera, exactly the failure mode this rewrite exists to avoid.
-- Routes that expect an upload must call cgi.receive_single_file_upload()
-- themselves, which streams stdin straight to disk. See api/system.lua.
function cgi.request()
    local req = {
        method = os.getenv("REQUEST_METHOD") or "GET",
        path = os.getenv("PATH_INFO") or "",
        query = parse_query(os.getenv("QUERY_STRING")),
        cookies = parse_cookies(os.getenv("HTTP_COOKIE")),
        content_type = os.getenv("CONTENT_TYPE") or "",
    }

    if req.content_type:match("^multipart/form%-data") then
        return req -- caller must use cgi.receive_single_file_upload()
    end

    local body = read_body()
    req.body_raw = body

    if req.content_type:match("^application/json") then
        local json = require "api.json"
        local decoded, err = json.decode(body)
        req.json = decoded or {}
        req.json_error = err
    end

    return req
end

-- Streams a multipart/form-data body with exactly one file part straight to
-- `dest_path`, never holding more than a small sliding buffer in memory
-- regardless of the upload size. Returns { path, filename, size } or nil+err.
--
-- Contract (matches what our own SPA sends -- see PROGRESS.md): the request
-- has a single part, the file field. Any extra parts are ignored, not
-- collected -- this is not a general-purpose multipart parser.
function cgi.receive_single_file_upload(dest_path, max_bytes)
    local length = tonumber(os.getenv("CONTENT_LENGTH") or "0") or 0
    local content_type = os.getenv("CONTENT_TYPE") or ""
    local boundary = content_type:match("multipart/form%-data;%s*boundary=(.+)$")
    if not boundary then return nil, "Not a multipart/form-data request" end
    if length <= 0 then return nil, "Empty request body" end
    if max_bytes and length > max_bytes + 4096 then
        io.stdin:read(length) -- drain so the server doesn't see a broken pipe
        return nil, "Upload too large"
    end

    local CHUNK = 8192
    local remaining = length
    local buf = ""

    local function fill(min_len)
        while #buf < min_len and remaining > 0 do
            local want = math.min(CHUNK, remaining)
            local chunk = io.stdin:read(want)
            if not chunk or #chunk == 0 then break end
            remaining = remaining - #chunk
            buf = buf .. chunk
        end
    end

    local start_marker = "--" .. boundary .. "\r\n"
    fill(#start_marker)
    local pos = buf:find(start_marker, 1, true)
    while not pos and remaining > 0 do
        fill(#buf + CHUNK)
        pos = buf:find(start_marker, 1, true)
    end
    if not pos then
        if remaining > 0 then io.stdin:read(remaining) end
        return nil, "Malformed multipart body (no initial boundary)"
    end
    buf = buf:sub(pos + #start_marker)

    local header_end = buf:find("\r\n\r\n", 1, true)
    while not header_end and remaining > 0 do
        fill(#buf + CHUNK)
        header_end = buf:find("\r\n\r\n", 1, true)
    end
    if not header_end then
        if remaining > 0 then io.stdin:read(remaining) end
        return nil, "Malformed multipart body (no part headers)"
    end
    local headers = buf:sub(1, header_end - 1)
    local filename = headers:match('filename="([^"]*)"')
    buf = buf:sub(header_end + 4)

    local out, open_err = io.open(dest_path, "wb")
    if not out then
        if remaining > 0 then io.stdin:read(remaining) end
        return nil, "Cannot open destination file: " .. tostring(open_err)
    end

    -- Never flush the last `holdback` bytes of the sliding buffer: a
    -- boundary marker split across two reads must never be partially
    -- written to disk as if it were file data.
    local end_marker = "\r\n--" .. boundary
    local holdback = #end_marker + 2 -- +2 covers the final boundary's trailing "--"
    local total_written = 0
    local finished = false

    while true do
        local marker_pos = buf:find(end_marker, 1, true)
        if marker_pos then
            out:write(buf:sub(1, marker_pos - 1))
            total_written = total_written + (marker_pos - 1)
            finished = true
            break
        end
        if remaining <= 0 and #buf <= holdback then
            break -- ran out of input without ever finding the closing boundary
        end
        if #buf > holdback then
            local safe_len = #buf - holdback
            out:write(buf:sub(1, safe_len))
            total_written = total_written + safe_len
            buf = buf:sub(safe_len + 1)
        end
        fill(#buf + CHUNK)
    end

    out:close()
    if remaining > 0 then io.stdin:read(remaining) end -- drain trailing epilogue

    if not finished then
        os.remove(dest_path)
        return nil, "Malformed multipart body (no closing boundary found)"
    end

    return { path = dest_path, filename = filename, size = total_written }
end

-- Response --------------------------------------------------------------

local response_started = false
local pending_headers = {}

function cgi.set_cookie(name, value, opts)
    opts = opts or {}
    local parts = { name .. "=" .. value }
    parts[#parts + 1] = "Path=" .. (opts.path or "/")
    if opts.max_age then parts[#parts + 1] = "Max-Age=" .. tostring(opts.max_age) end
    if opts.expires then parts[#parts + 1] = "Expires=" .. opts.expires end
    if opts.http_only ~= false then parts[#parts + 1] = "HttpOnly" end
    pending_headers[#pending_headers + 1] = "Set-Cookie: " .. table.concat(parts, "; ")
end

local status_texts = {
    [200] = "OK", [400] = "Bad Request", [401] = "Unauthorized",
    [403] = "Forbidden", [404] = "Not Found", [405] = "Method Not Allowed",
    [500] = "Internal Server Error",
}

local function send_head(status, content_type)
    if response_started then return end
    response_started = true
    io.write("Status: " .. status .. " " .. (status_texts[status] or "") .. "\r\n")
    io.write("Content-Type: " .. content_type .. "\r\n")
    for _, header in ipairs(pending_headers) do
        io.write(header .. "\r\n")
    end
    io.write("\r\n")
end

function cgi.send_json(status, data)
    local json = require "api.json"
    send_head(status, "application/json")
    io.write(json.encode(data))
end

function cgi.send_raw(status, content_type, body)
    send_head(status, content_type)
    io.write(body)
end

function cgi.ok(data)
    data = data or {}
    data.ok = true
    cgi.send_json(200, data)
end

function cgi.fail(status, error_message, extra)
    local data = extra or {}
    data.ok = false
    data.error = error_message
    cgi.send_json(status, data)
end

return cgi
