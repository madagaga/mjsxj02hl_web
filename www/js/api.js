// Thin fetch wrapper around the JSON API (www/cgi-bin/api.lua). Every call
// resolves to the parsed JSON body -- callers check `.ok` themselves, same
// as the server's { ok, error, ... } contract (see PROGRESS.md).

const BASE = "/cgi-bin/api.lua";

async function request(method, path, body) {
    const opts = { method, credentials: "same-origin" };
    if (body !== undefined) {
        opts.headers = { "Content-Type": "application/json" };
        opts.body = JSON.stringify(body);
    }
    let res;
    try {
        res = await fetch(BASE + path, opts);
    } catch (e) {
        return { ok: false, error: "Network error: " + e.message };
    }
    try {
        return await res.json();
    } catch (e) {
        return { ok: false, error: "Invalid response from device (HTTP " + res.status + ")" };
    }
}

async function upload(path, file, onProgress) {
    // Uses XHR instead of fetch so we get upload progress events -- useful
    // for the firmware upload (up to ~12 MB over what might be a slow Wi-Fi
    // link to the camera).
    return new Promise((resolve) => {
        const xhr = new XMLHttpRequest();
        xhr.open("POST", BASE + path);
        xhr.upload.onprogress = (e) => {
            if (onProgress && e.lengthComputable) onProgress(e.loaded / e.total);
        };
        xhr.onload = () => {
            try {
                resolve(JSON.parse(xhr.responseText));
            } catch (e) {
                resolve({ ok: false, error: "Invalid response from device (HTTP " + xhr.status + ")" });
            }
        };
        xhr.onerror = () => resolve({ ok: false, error: "Network error during upload" });
        const form = new FormData();
        form.append("file", file);
        xhr.send(form);
    });
}

export const api = {
    login: (username, password) => request("POST", "/login", { username, password }),
    logout: () => request("POST", "/logout"),
    session: () => request("GET", "/session"),

    profile: () => request("GET", "/profile"),
    changePassword: (current_passwd, new_passwd, confirm_passwd) =>
        request("POST", "/profile", { current_passwd, new_passwd, confirm_passwd }),

    wifiGet: () => request("GET", "/wifi"),
    wifiSave: (ssid, psk, scan_ssid) => request("POST", "/wifi", { action: "save", ssid, psk, scan_ssid }),
    wifiDefaults: () => request("POST", "/wifi", { action: "defaults" }),

    settingsGet: () => request("GET", "/settings"),
    // OpenWrt-style: stage edits across any number of sections client-side,
    // apply them all in one call -> one restart instead of one per section.
    settingsApply: (sections) => request("POST", "/settings", { sections }),

    systemInfo: () => request("GET", "/system/info"),
    autorunGet: () => request("GET", "/system/autorun"),
    autorunSave: (content) => request("POST", "/system/autorun", { action: "save", content }),
    autorunDefaults: () => request("POST", "/system/autorun", { action: "defaults" }),
    reboot: () => request("POST", "/system/reboot"),
    factoryReset: () => request("POST", "/system/factory_reset"),
    backupCreate: () => request("POST", "/system/backup"),
    backupRestore: (file, onProgress) => upload("/system/restore", file, onProgress),
    bootloaderDownload: () => request("POST", "/system/bootloader/download"),
    bootloaderUpgrade: (file, onProgress) => upload("/system/bootloader/upgrade", file, onProgress),
    firmwareUpload: (file, onProgress) => upload("/system/firmware", file, onProgress),
};
