-- Routes: GET /system/info, GET/POST /system/autorun, POST /system/reboot,
-- POST /system/factory_reset, POST /system/backup, POST /system/restore,
-- POST /system/bootloader/download, POST /system/bootloader/upgrade,
-- POST /system/firmware
--
-- Same side effects/sizes as the legacy system/*.lp pages. Uploads stream
-- straight to disk via cgi.receive_single_file_upload -- see cgi.lua for why
-- (12 MB firmware image vs. a device with a couple MB of free RAM).

local cgi = require "api.cgi"
local fnc = require "functions"
local paths = require "paths"

local M = {}

local AUTORUN_DEFAULT = "#!/bin/sh\n\n# Launching the watchdog\nwatchdog.sh &"
local BACKUP_SIZE = 393216 -- 384 KiB
local BOOTLOADER_SIZE = 262144 -- 256 KiB
local FIRMWARE_SIZE = 12058688
local FIRMWARE_UIMAGE_HEADER_SIZE = 64
local FIRMWARE_UIMAGE = {
    kind = 5,
    name = "hlc6",
    size = FIRMWARE_SIZE - FIRMWARE_UIMAGE_HEADER_SIZE, -- 0xB80000
}

local function reboot_response()
    if os.execute(paths.reboot) then
        cgi.ok({ rebooting = true })
    else
        cgi.fail(200, "To apply changes, you need reboot the device.", { rebooting = false })
    end
end

-- GET /system/info --------------------------------------------------------

function M.get_info(req)
    local version = fnc.file.get_contents(paths.version_file)
    version = fnc.string.trim(version or "", "\n")
    if fnc.string.is_empty(version) then version = "Unknown" end
    cgi.ok({
        version = version,
        sdcard_present = fnc.file.exists(paths.sdcard_device),
    })
end

-- autorun -------------------------------------------------------------------

function M.get_autorun(req)
    local content = fnc.file.get_contents(paths.autorun_file)
    content = fnc.string.trim(content or "", "\n")
    if fnc.string.is_empty(content) then content = AUTORUN_DEFAULT end
    cgi.ok({ content = content })
end

-- No restart/reboot here, matching legacy: a run.sh change only takes effect
-- on the next manual reboot.
function M.post_autorun(req)
    local body = req.json or {}
    local content = AUTORUN_DEFAULT
    if body.action == "save" then
        content = body.content or AUTORUN_DEFAULT
    elseif body.action ~= "defaults" then
        return cgi.fail(400, "Unknown action")
    end
    local ok, err = fnc.file.put_contents(paths.autorun_file, content .. "\n")
    if not ok then
        return cgi.fail(200, err or "Error saving autorun script!")
    end
    cgi.ok({ content = content })
end

-- reboot / factory reset -----------------------------------------------------

function M.post_reboot(req)
    reboot_response()
end

-- No reboot fallback on failure here: the factory-reset binary itself
-- reboots the device on success, matching the legacy page exactly.
function M.post_factory_reset(req)
    if os.execute(paths.mjsxj02hl .. " --factory-reset") then
        cgi.ok({ rebooting = true })
    else
        cgi.fail(200, "Factory reset error!")
    end
end

-- backup / restore (mtd6, "configs" partition) -------------------------------

function M.post_backup(req)
    if not os.execute(paths.cat .. " " .. paths.mtd_configs_block .. " > " .. paths.tmp_backup) then
        return cgi.fail(200, "Error creating a backup file!")
    end
    cgi.ok({ size = BACKUP_SIZE, download_url = paths.tmp_backup })
end

function M.post_restore(req)
    local upload, err = cgi.receive_single_file_upload(paths.tmp_backup, BACKUP_SIZE + 4096)
    if not upload then
        return cgi.fail(200, err or "No backup file selected!")
    end
    if upload.size ~= BACKUP_SIZE then
        os.remove(paths.tmp_backup)
        return cgi.fail(200, "Invalid size of the backup file!")
    end
    local flashed = fnc.app.flash_partition(paths.tmp_backup, paths.mtd_configs)
    os.remove(paths.tmp_backup)
    if not flashed then
        return cgi.fail(200, "Error restoring a backup copy of the settings!")
    end
    reboot_response()
end

-- bootloader (mtd0) -----------------------------------------------------------

function M.post_bootloader_download(req)
    if not os.execute(paths.cat .. " " .. paths.mtd_bootloader_block .. " > " .. paths.tmp_bootloader) then
        return cgi.fail(200, "Error creating a bootloader file!")
    end
    cgi.ok({ size = BOOTLOADER_SIZE, download_url = paths.tmp_bootloader })
end

function M.post_bootloader_upgrade(req)
    local upload, err = cgi.receive_single_file_upload(paths.tmp_bootloader, BOOTLOADER_SIZE + 4096)
    if not upload then
        return cgi.fail(200, err or "No bootloader file selected!")
    end
    if upload.size ~= BOOTLOADER_SIZE then
        os.remove(paths.tmp_bootloader)
        return cgi.fail(200, "Invalid size of the bootloader file!")
    end
    local flashed = fnc.app.flash_partition(paths.tmp_bootloader, paths.mtd_bootloader)
    os.remove(paths.tmp_bootloader)
    if not flashed then
        return cgi.fail(200, "Bootloader update error!")
    end
    reboot_response()
end

-- firmware -------------------------------------------------------------------
--
-- Writes the image to the SD card, then triggers U-Boot's SD-update path by
-- setting bit0 of a trigger register that survives a software reboot (same
-- effect as holding the physical reset button at boot). See paths.lua and
-- PROGRESS.md for the full mechanism (reverse-engineered + tested on a real
-- device by a peer session, 2026-10-01). U-Boot re-validates the image's own
-- data CRC32 before erasing anything -- the checks here are an early refusal
-- for obviously-wrong uploads, not the final safety net.

-- Reads back a 32-bit register via devmem to confirm a write actually took.
-- Returns the integer value, or nil + error.
local function read_register(address)
    local handle = io.popen(paths.devmem .. " " .. address .. " 32 2>&1")
    if not handle then return nil, "Could not run devmem" end
    local output = handle:read("*a") or ""
    local ok = handle:close()
    if not ok then return nil, "devmem read failed: " .. output end
    local hex = output:match("0[xX](%x+)") or output:match("^%s*(%x+)%s*$")
    local value = hex and tonumber(hex, 16)
    if not value then return nil, "Unexpected devmem output: " .. output end
    return value
end

-- Flushes pending writes, sets the trigger register to 1, and reads it back
-- to make sure it actually stuck before we consider it safe to reboot.
local function trigger_sd_update()
    os.execute(paths.sync)
    if not os.execute(paths.devmem .. " " .. paths.fw_trigger_register .. " 32 1") then
        return false, "Error writing the U-Boot update-trigger register!"
    end
    local value, err = read_register(paths.fw_trigger_register)
    if not value then
        return false, "Could not verify the update-trigger register: " .. (err or "unknown error")
            .. " -- aborting, device NOT rebooted."
    end
    if (value & 1) == 0 then
        return false, "Update-trigger register did not take the expected value (read "
            .. tostring(value) .. ") -- aborting, device NOT rebooted."
    end
    return true
end

function M.post_firmware(req)
    if not fnc.file.exists(paths.sdcard_device) then
        return cgi.fail(200, "To update the firmware, you need a SD card!")
    end
    local upload, err = cgi.receive_single_file_upload(paths.firmware_dest, FIRMWARE_SIZE + 65536)
    if not upload then
        return cgi.fail(200, err or "No firmware file selected!")
    end
    if upload.size ~= FIRMWARE_SIZE then
        os.remove(paths.firmware_dest)
        return cgi.fail(200, "Invalid size of the firmware file!")
    end

    local valid, header_err = fnc.uimage.validate(paths.firmware_dest, FIRMWARE_UIMAGE)
    if not valid then
        os.remove(paths.firmware_dest)
        return cgi.fail(200, "Invalid firmware image: " .. (header_err or "header check failed") .. "!")
    end

    -- Guard against U-Boot reflashing the BOOTLOADER itself: it does that
    -- instead of the normal kernel+rootfs+app+kback update if this file is
    -- present on the SD card.
    if fnc.file.exists(paths.sdcard_boot_trigger) then
        os.remove(paths.firmware_dest)
        return cgi.fail(200, "A " .. paths.sdcard_boot_trigger .. " file is present on the SD card -- refusing "
            .. "to proceed, since U-Boot would reflash the bootloader instead of the normal firmware. "
            .. "Remove that file first if this was intentional.")
    end

    local triggered, trigger_err = trigger_sd_update()
    if not triggered then
        os.remove(paths.firmware_dest)
        return cgi.fail(200, trigger_err)
    end

    if os.execute(paths.reboot) then
        cgi.ok({ rebooting = true })
    else
        cgi.fail(200, "Update staged and triggered, but the device could not be rebooted automatically -- "
            .. "please reboot it manually to apply the firmware update.", { rebooting = false })
    end
end

return M
