-- Validates a U-Boot "legacy image" (mkimage/uImage) header: the same format
-- U-Boot itself parses on the camera before it erases/flashes anything.
-- Standard 64-byte header, all multi-byte fields big-endian:
--   offset  0 (4B) magic
--   offset  4 (4B) header CRC32 (not checked here -- U-Boot verifies this
--                  and the data CRC32 before writing anything to flash;
--                  recomputing it in Lua isn't needed for our purposes)
--   offset 12 (4B) data size (payload size, i.e. file size minus the 64-byte header)
--   offset 30 (1B) image type
--   offset 32 (32B) NUL-terminated name
--
-- Only checks the fields that distinguish "this is really a demo_hlc6.bin
-- combined firmware image for this device" from garbage -- the magic, the
-- declared payload size, the type, and the name. The final, authoritative
-- check (full data CRC32) is U-Boot's own, done on-device before it erases
-- anything.

local functions = {
    uimage = {},
    string = require "functions.string",
}
package.loaded[...] = functions.uimage

local HEADER_SIZE = 64
local MAGIC = 0x27051956
local NAME_OFFSET = 32
local NAME_SIZE = 32

-- Reads and unpacks the header fields we care about from an open file
-- (already positioned at offset 0). Returns a table or nil+error.
local function read_header(file)
    local raw = file:read(HEADER_SIZE)
    if not raw or #raw < HEADER_SIZE then
        return nil, "File too small to contain a uImage header"
    end
    -- Read each field directly by its documented byte offset rather than
    -- unpacking the whole struct positionally, so this stays correct
    -- regardless of the (unused) padding fields in between.
    local function u32(offset)
        return string.unpack(">I4", raw, offset + 1)
    end
    local function u8(offset)
        return string.unpack(">I1", raw, offset + 1)
    end
    local name = raw:sub(NAME_OFFSET + 1, NAME_OFFSET + NAME_SIZE):match("^[^%z]*")
    return {
        magic = u32(0),
        size = u32(12),
        kind = u8(30),
        name = name,
    }
end

-- expected = { kind = <int>, name = <string>, size = <int> } -- all required.
-- Returns true, or false + human-readable error.
function functions.uimage.validate(filename, expected)
    local file, open_err = io.open(filename, "rb")
    if not file then
        return false, "Cannot open file: " .. tostring(open_err)
    end
    local ok, header, err = pcall(read_header, file)
    file:close()
    if not ok then
        return false, "Malformed image header: " .. tostring(header)
    end
    if not header then
        return false, err or "Malformed image header"
    end

    if header.magic ~= MAGIC then
        return false, string.format("Invalid image magic (got 0x%08x, expected 0x%08x)", header.magic, MAGIC)
    end
    if expected.kind and header.kind ~= expected.kind then
        return false, string.format("Invalid image type (got %d, expected %d)", header.kind, expected.kind)
    end
    if expected.name and header.name ~= expected.name then
        return false, string.format("Invalid image name (got %q, expected %q)", header.name, expected.name)
    end
    if expected.size and header.size ~= expected.size then
        return false, string.format("Invalid image payload size (got %d, expected %d)", header.size, expected.size)
    end
    return true
end

return functions.uimage
