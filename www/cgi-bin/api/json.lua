-- Minimal, dependency-free JSON encode/decode for the API layer.
-- No external json library is vendored anymore (cgilua/wsapi were dropped),
-- so this replaces it with just enough to cover our request/response shapes:
-- objects, arrays, strings, numbers, booleans, null.

local json = {}

json.null = setmetatable({}, { __tostring = function() return "null" end })

-- Encode

local escapes = {
    ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r',
    ['\t'] = '\\t', ['\b'] = '\\b', ['\f'] = '\\f',
}

local function encode_string(str)
    return '"' .. str:gsub('[%c"\\]', function(c)
        return escapes[c] or string.format('\\u%04x', string.byte(c))
    end) .. '"'
end

-- A table is treated as a JSON array if it has no non-integer keys and its
-- integer keys form a contiguous 1..n range (empty table encodes as {}).
local function is_array(tbl)
    local count = 0
    for k in pairs(tbl) do
        if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
            return false
        end
        count = count + 1
    end
    return count == #tbl
end

local encode_value

local function encode_array(tbl)
    local parts = {}
    for i = 1, #tbl do
        parts[i] = encode_value(tbl[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function encode_object(tbl)
    local parts = {}
    for k, v in pairs(tbl) do
        parts[#parts + 1] = encode_string(tostring(k)) .. ":" .. encode_value(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

encode_value = function(value)
    local t = type(value)
    if value == json.null then
        return "null"
    elseif t == "string" then
        return encode_string(value)
    elseif t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null" -- NaN/Inf have no JSON representation
        end
        return tostring(value)
    elseif t == "boolean" then
        return tostring(value)
    elseif t == "table" then
        if next(value) == nil then
            return "{}" -- ambiguous empty case, treat as empty object
        elseif is_array(value) then
            return encode_array(value)
        else
            return encode_object(value)
        end
    elseif t == "nil" then
        return "null"
    else
        error("json.encode: cannot encode type " .. t)
    end
end

json.encode = encode_value

-- Decode

local function skip_ws(str, pos)
    local _, e = str:find("^[ \t\r\n]*", pos)
    return e + 1
end

local decode_value

local function decode_error(str, pos, msg)
    error(("json.decode: %s at position %d"):format(msg, pos))
end

local function decode_string(str, pos)
    if str:sub(pos, pos) ~= '"' then decode_error(str, pos, "expected string") end
    local out = {}
    local i = pos + 1
    while true do
        local c = str:sub(i, i)
        if c == "" then
            decode_error(str, i, "unterminated string")
        elseif c == '"' then
            return table.concat(out), i + 1
        elseif c == "\\" then
            local nc = str:sub(i + 1, i + 1)
            if nc == "u" then
                local hex = str:sub(i + 2, i + 5)
                local code = tonumber(hex, 16) or 0
                out[#out + 1] = (code < 128) and string.char(code) or "?"
                i = i + 6
            else
                local map = { n = "\n", r = "\r", t = "\t", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                out[#out + 1] = map[nc] or nc
                i = i + 2
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
end

local function decode_number(str, pos)
    local s, e = str:find("^%-?%d+%.?%d*[eE]?[+-]?%d*", pos)
    if not s then decode_error(str, pos, "expected number") end
    return tonumber(str:sub(s, e)), e + 1
end

local function decode_array(str, pos)
    local arr = {}
    pos = skip_ws(str, pos + 1)
    if str:sub(pos, pos) == "]" then return arr, pos + 1 end
    while true do
        local value
        value, pos = decode_value(str, pos)
        arr[#arr + 1] = value
        pos = skip_ws(str, pos)
        local c = str:sub(pos, pos)
        if c == "," then
            pos = skip_ws(str, pos + 1)
        elseif c == "]" then
            return arr, pos + 1
        else
            decode_error(str, pos, "expected ',' or ']'")
        end
    end
end

local function decode_object(str, pos)
    local obj = {}
    pos = skip_ws(str, pos + 1)
    if str:sub(pos, pos) == "}" then return obj, pos + 1 end
    while true do
        local key
        key, pos = decode_string(str, pos)
        pos = skip_ws(str, pos)
        if str:sub(pos, pos) ~= ":" then decode_error(str, pos, "expected ':'") end
        pos = skip_ws(str, pos + 1)
        local value
        value, pos = decode_value(str, pos)
        obj[key] = value
        pos = skip_ws(str, pos)
        local c = str:sub(pos, pos)
        if c == "," then
            pos = skip_ws(str, pos + 1)
        elseif c == "}" then
            return obj, pos + 1
        else
            decode_error(str, pos, "expected ',' or '}'")
        end
    end
end

decode_value = function(str, pos)
    pos = skip_ws(str, pos)
    local c = str:sub(pos, pos)
    if c == '"' then
        return decode_string(str, pos)
    elseif c == "{" then
        return decode_object(str, pos)
    elseif c == "[" then
        return decode_array(str, pos)
    elseif c == "t" and str:sub(pos, pos + 3) == "true" then
        return true, pos + 4
    elseif c == "f" and str:sub(pos, pos + 4) == "false" then
        return false, pos + 5
    elseif c == "n" and str:sub(pos, pos + 3) == "null" then
        return json.null, pos + 4
    elseif c == "-" or c:match("%d") then
        return decode_number(str, pos)
    else
        decode_error(str, pos, "unexpected character '" .. c .. "'")
    end
end

-- Decode a JSON string. Returns nil, error_message on failure instead of
-- raising, since request bodies are untrusted input.
json.decode = function(str)
    if str == nil or str == "" then return {} end
    local ok, value_or_err, pos = pcall(function()
        local value, p = decode_value(str, 1)
        return value, p
    end)
    if not ok then
        return nil, value_or_err
    end
    return value_or_err
end

return json
