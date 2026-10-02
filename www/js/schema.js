// Settings schema: single source of truth for field types, ranges and
// defaults, mirrored BY HAND from mjsxj02hl_application/configs/configs.h
// (kept in sync manually for now -- see PROGRESS.md "Décisions actées").
//
// The server (www/cgi-bin/api/settings.lua) does NOT know about any of this:
// it's a generic INI<->JSON pass-through. All validation, clamping and
// defaulting happens here, in the client, before a POST is sent.
//
// Field shape: { key, label, type, default, min?, max?, options?, endLabels? }
//   type: "text" | "password" | "textarea" | "bool" | "int" | "select" | "range"
//   endLabels: for "range" only, ["<label at min>", "<label at max>"] shown
//   either side of the slider (e.g. "Less sensitive" / "More sensitive").
//   min/max: only present where the legacy UI actually clamped that field.
//            Fields with neither are intentionally unclamped -- this mirrors
//            a real (if inconsistent) legacy behavior, e.g. alarm timeouts
//            and rtsp/mqtt ports accept any number, while *_sens fields
//            clamp to [1,255]. Don't "fix" this asymmetry without checking
//            PROGRESS.md first.
//   options: for "select", an array of { value, label }.

// POSIX TZ sign convention: the *value* written to /configs/TZ is
// deliberately the opposite sign of the human-readable *label* shown here
// (e.g. value "UTC+12:00" is labeled "UTC-12:00"). This matches the legacy
// UI exactly and is very likely intentional (POSIX TZ strings use "east/west
// of Greenwich" with an inverted sign vs. common ISO 8601 usage), not a bug
// to fix. Do not swap value/label.
export const TIMEZONES = [
    { value: "UTC+12:00", label: "UTC-12:00" },
    { value: "UTC+11:00", label: "UTC-11:00" },
    { value: "UTC+10:00", label: "UTC-10:00" },
    { value: "UTC+9:30", label: "UTC-9:30" },
    { value: "UTC+9:00", label: "UTC-9:00" },
    { value: "UTC+8:00", label: "UTC-8:00" },
    { value: "UTC+7:00", label: "UTC-7:00" },
    { value: "UTC+6:00", label: "UTC-6:00" },
    { value: "UTC+5:00", label: "UTC-5:00" },
    { value: "UTC+4:30", label: "UTC-4:30" },
    { value: "UTC+4:00", label: "UTC-4:00" },
    { value: "UTC+3:30", label: "UTC-3:30" },
    { value: "UTC+3:00", label: "UTC-3:00" },
    { value: "UTC+2:00", label: "UTC-2:00" },
    { value: "UTC+1:00", label: "UTC-1:00" },
    { value: "UTC", label: "UTC" },
    { value: "UTC-1:00", label: "UTC+1:00" },
    { value: "UTC-2:00", label: "UTC+2:00" },
    { value: "UTC-3:00", label: "UTC+3:00" },
    { value: "UTC-3:30", label: "UTC+3:30" },
    { value: "UTC-4:00", label: "UTC+4:00" },
    { value: "UTC-4:30", label: "UTC+4:30" },
    { value: "UTC-5:00", label: "UTC+5:00" },
    { value: "UTC-5:30", label: "UTC+5:30" },
    { value: "UTC-5:45", label: "UTC+5:45" },
    { value: "UTC-6:00", label: "UTC+6:00" },
    { value: "UTC-6:30", label: "UTC+6:30" },
    { value: "UTC-7:00", label: "UTC+7:00" },
    { value: "UTC-8:00", label: "UTC+8:00" },
    { value: "UTC-9:00", label: "UTC+9:00" },
    { value: "UTC-9:30", label: "UTC+9:30" },
    { value: "UTC-10:00", label: "UTC+10:00" },
    { value: "UTC-10:30", label: "UTC+10:30" },
    { value: "UTC-11:00", label: "UTC+11:00" },
    { value: "UTC-12:00", label: "UTC+12:00" },
    { value: "UTC-12:45", label: "UTC+12:45" },
];

const OSD_SIZE_OPTIONS = [-3, -2, -1, 0, 1, 2, 3].map((v) => ({ value: v, label: String(v) }));
const CODEC_OPTIONS = [
    { value: 1, label: "H.264 (AVC)" },
    { value: 2, label: "H.265 (HEVC)" },
];
const RCMODE_OPTIONS = [
    { value: 0, label: "Constant bitrate" },
    { value: 1, label: "Constant quality" },
    { value: 2, label: "Variable bitrate" },
];
const QOS_OPTIONS = [0, 1, 2].map((v) => ({ value: v, label: String(v) }));
const NIGHT_MODE_OPTIONS = [
    { value: 0, label: "Disabled" },
    { value: 1, label: "Enabled" },
    { value: 2, label: "Automatic" },
];
const DEBUG_LEVEL_OPTIONS = [
    { value: 0, label: "Disabled" },
    { value: 1, label: "Error" },
    { value: 2, label: "Warning" },
    { value: 3, label: "Info" },
    { value: 4, label: "Debug" },
];

export const SETTINGS_SCHEMA = {
    general: [
        { key: "name", label: "Device name", type: "text", default: "My Camera" },
        { key: "led", label: "Enable onboard LED indicator", type: "bool", default: true },
        { key: "timezone", label: "Time zone", type: "select", default: "UTC-3", options: TIMEZONES },
    ],
    osd: [
        { key: "enable", label: "Enable OSD", type: "bool", default: false },
        { key: "datetime", label: "Display date and time", type: "bool", default: true },
        { key: "datetime_x", label: "Date/time X position", type: "int", default: 48, min: 0, max: 1920 },
        { key: "datetime_y", label: "Date/time Y position", type: "int", default: 0, min: 0, max: 1080 },
        { key: "datetime_size", label: "Date/time size", type: "select", default: 0, options: OSD_SIZE_OPTIONS },
        { key: "motion", label: "Display motion detection boxes", type: "bool", default: false },
        { key: "humanoid", label: "Display humanoid detection boxes", type: "bool", default: false },
    ],
    video: [
        { key: "gop", label: "Group of pictures (GOP) every N*FPS", type: "int", default: 1, min: 1, max: 60 },
        { key: "flip", label: "Flip", type: "bool", default: false },
        { key: "mirror", label: "Mirror", type: "bool", default: false },
        { key: "primary_type", label: "Primary: video compression standard", type: "select", default: 1, options: CODEC_OPTIONS },
        { key: "primary_bitrate", label: "Primary: bitrate (kbps)", type: "int", default: 1800, min: 2, max: 61480 },
        { key: "primary_rcmode", label: "Primary: rate control mode", type: "select", default: 2, options: RCMODE_OPTIONS },
        { key: "secondary_type", label: "Secondary: video compression standard", type: "select", default: 1, options: CODEC_OPTIONS },
        { key: "secondary_bitrate", label: "Secondary: bitrate (kbps)", type: "int", default: 900, min: 2, max: 61480 },
        { key: "secondary_rcmode", label: "Secondary: rate control mode", type: "select", default: 2, options: RCMODE_OPTIONS },
    ],
    audio: [
        { key: "volume", label: "Volume", type: "int", default: 70, min: 0, max: 100 },
        { key: "primary_enable", label: "Enable audio for primary channel", type: "bool", default: true },
        { key: "secondary_enable", label: "Enable audio for secondary channel", type: "bool", default: true },
    ],
    speaker: [
        { key: "type", label: "File format", type: "select", default: 1, options: [{ value: 1, label: "PCM" }, { value: 2, label: "G711" }] },
        { key: "volume", label: "Volume", type: "int", default: 70, min: 0, max: 100 },
    ],
    alarm: [
        { key: "enable", label: "Enable alarms", type: "bool", default: true },
        { key: "motion_sens", label: "Motion sensitivity", type: "range", default: 150, min: 1, max: 255, endLabels: ["Less sensitive", "More sensitive"] },
        { key: "motion_timeout", label: "Motion timeout (seconds)", type: "int", default: 60 },
        { key: "motion_detect_exec", label: "Command on motion detected", type: "text", default: "" },
        { key: "motion_lost_exec", label: "Command on motion lost", type: "text", default: "" },
        { key: "humanoid_sens", label: "Humanoid sensitivity", type: "range", default: 150, min: 1, max: 255, endLabels: ["Less sensitive", "More sensitive"] },
        { key: "humanoid_timeout", label: "Humanoid timeout (seconds)", type: "int", default: 60 },
        { key: "humanoid_detect_exec", label: "Command on humanoid detected", type: "text", default: "" },
        { key: "humanoid_lost_exec", label: "Command on humanoid lost", type: "text", default: "" },
    ],
    rtsp: [
        { key: "enable", label: "Enable RTSP server", type: "bool", default: true },
        { key: "port", label: "Port", type: "int", default: 554 },
        { key: "username", label: "Username (empty to disable auth)", type: "text", default: "" },
        { key: "password", label: "Password", type: "password", default: "" },
        { key: "primary_name", label: "Primary channel name", type: "text", default: "primary" },
        { key: "secondary_name", label: "Secondary channel name", type: "text", default: "secondary" },
    ],
    mqtt: [
        { key: "enable", label: "Enable MQTT client", type: "bool", default: false },
        { key: "server", label: "Server address (empty to disable)", type: "text", default: "" },
        { key: "port", label: "Port", type: "int", default: 1883 },
        { key: "username", label: "Username (empty for anonymous)", type: "text", default: "" },
        { key: "password", label: "Password", type: "password", default: "" },
        { key: "topic", label: "Topic", type: "text", default: "mjsxj02hl" },
        { key: "qos", label: "Quality of Service", type: "select", default: 1, options: QOS_OPTIONS },
        { key: "retain", label: "Retained messages", type: "bool", default: true },
        { key: "reconnection_interval", label: "Reconnection interval (seconds)", type: "int", default: 60 },
        { key: "periodical_interval", label: "Periodical message interval (seconds)", type: "int", default: 60 },
        { key: "discovery", label: "Home Assistant discovery prefix", type: "text", default: "homeassistant" },
    ],
    night: [
        { key: "mode", label: "Night mode", type: "select", default: 2, options: NIGHT_MODE_OPTIONS },
        { key: "gray", label: "Grayscale", type: "select", default: 2, options: NIGHT_MODE_OPTIONS },
    ],
    logger: [
        { key: "level", label: "Log level", type: "select", default: 2, options: DEBUG_LEVEL_OPTIONS },
        { key: "file", label: "Log file path (empty to disable)", type: "text", default: "" },
    ],
    // Added 2026-09-29 on the application side (mjsxj02hl_application configs.h)
    // for the in-progress libsceneauto rewrite -- lets an advanced user point
    // at a different sensor's ISP tuning INI / IVP model without a rebuild.
    // Empty value = board default path, not an error.
    paths: [
        { key: "scene_day", label: "Day scene INI path (empty = board default)", type: "text", default: "" },
        { key: "scene_night", label: "Night scene INI path (empty = board default)", type: "text", default: "" },
        { key: "ivp_model", label: "IVP model (.oms) path (empty = board default)", type: "text", default: "" },
    ],
};

// Wi-Fi is a separate endpoint (/api/wifi), backed by wpa_supplicant.conf,
// not by the mjsxj02hl.conf INI -- kept out of SETTINGS_SCHEMA on purpose.
export const WIFI_SCHEMA = [
    { key: "scan_ssid", label: "SSID scan technique", type: "select", default: 1, options: [{ value: 0, label: "Broadcast probe request" }, { value: 1, label: "Directed probe request" }] },
    { key: "ssid", label: "SSID", type: "text", default: "" },
    { key: "psk", label: "Password", type: "password", default: "" },
];

function clampInt(value, field) {
    let n = parseInt(value, 10);
    if (!Number.isFinite(n)) n = field.default;
    if (typeof field.min === "number" && n < field.min) n = field.min;
    if (typeof field.max === "number" && n > field.max) n = field.max;
    return n;
}

// Coerces/validates a single field's raw value (e.g. from a form control)
// according to its schema type. Never throws: falls back to the field's
// default on unusable input.
export function coerceField(field, rawValue) {
    switch (field.type) {
        case "bool":
            return Boolean(rawValue);
        case "int":
        case "range":
            return clampInt(rawValue, field);
        case "select": {
            if (field.options && typeof field.default === "number") {
                return clampInt(rawValue, field);
            }
            return rawValue == null || rawValue === "" ? field.default : String(rawValue);
        }
        case "text":
        case "password":
        case "textarea":
        default:
            return rawValue == null ? field.default : String(rawValue);
    }
}

// Builds a fully-populated object for a section/list of fields, filling in
// defaults for anything missing from `values` (e.g. a freshly-read INI file
// that doesn't have this section yet, or a partial API response).
export function withDefaults(fields, values) {
    values = values || {};
    const result = {};
    for (const field of fields) {
        result[field.key] = values[field.key] === undefined
            ? field.default
            : coerceField(field, values[field.key]);
    }
    return result;
}

// Validates/clamps a full set of form values before POSTing, using the same
// per-field rules as withDefaults, but treating every field as explicitly
// provided (used right before a save).
export function validate(fields, values) {
    return withDefaults(fields, values);
}

export function getDefaults(fields) {
    return withDefaults(fields, {});
}
