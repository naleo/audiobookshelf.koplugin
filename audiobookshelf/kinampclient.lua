-- Thin adapter over KinAMP's own KOReader module. KinAMP must be installed.
local Client = {}

local function backend()
    local ok, B = pcall(require, "kinamp_backend")
    if ok and type(B) == "table" then return B end
    return nil
end

function Client.available()
    return backend() ~= nil
end

-- Starts KinAMP's player without KinAMP's own startup. That startup cycles the
-- Bluetooth radio (to arm a 20 minute keepalive), which leaves the headset
-- "connected" with a stale audio link: silent until it is reconnected, and it
-- puts up a "Preparing Bluetooth" popup. Starting the player directly avoids all
-- of it. Returns false when it could not (missing pieces), so the caller can fall
-- back to KinAMP's own path.
local function launchDirect(B)
    local loaded, C = pcall(require, "kinamp_config")
    if not loaded or type(C) ~= "table" or not C.bin_path or not C.log_file then return false end
    if not B.shell_escape then return false end
    local cmd = string.format("nohup %s --music > %s 2>&1 &", B.shell_escape(C.bin_path), B.shell_escape(C.log_file))
    local function run()
        os.execute(cmd)
        B.launch_pending = false
    end
    -- Bluetooth is the only way sound leaves this Kindle: a dead radio means a
    -- silent player. When it is off, KinAMP's own routine brings it up (with the
    -- radio already down it needs no cycle).
    local bt_ok, BT = pcall(require, "kinamp_bt")
    if bt_ok and type(BT) == "table" and BT.available and BT.available() and BT.getState() == 0 then
        B.launch_pending = true -- tells wait_until_running not to count the time this takes
        BT.armKeepalive(function() run() end)
    else
        run()
    end
    return true
end

-- true when the commands reached a running daemon; false when the player had to be
-- started (the caller then waits for it). Overwrites KinAMP's internal queue.
function Client.playFromIndex(index, paths)
    local B = backend()
    if not B then return false end
    if B.is_running() then
        return B.play_from_index(index, paths) and true or false
    end
    -- A cold player reads its queue and start index from these two files.
    if B.save_internal_playlist and B.update_config and B.save_internal_playlist(paths) then
        B.update_config(index - 1, false)
        if launchDirect(B) then return false end
    end
    return B.play_from_index(index, paths) and true or false
end

function Client.seek(seconds)
    local B = backend()
    if B then B.seek(seconds) end
end

function Client.stop()
    local B = backend()
    if B then B.stop() end
end

function Client.getStatus()
    local B = backend()
    if not B then return nil end
    return B.get_status()
end

-- Disconnect and reconnect the connected Bluetooth device through KinAMP's own
-- Bluetooth module (what its menu does). callback(ok) is always called once;
-- ok is false when there is nothing to reconnect or it did not work.
function Client.reconnectBluetooth(callback)
    local loaded, BT = pcall(require, "kinamp_bt")
    if not loaded or type(BT) ~= "table" or not BT.available or not BT.available() then
        callback(false)
        return
    end
    local function connect(mac)
        BT.connect(mac, function(connected) callback(connected and true or false) end)
    end
    local listed, devices = pcall(BT.getConnected)
    local device = listed and devices and devices[1]
    if device and device.mac then
        -- Connect whether or not the disconnect was seen to complete.
        BT.disconnect(device.mac, function() connect(device.mac) end)
        return
    end
    -- Nothing listed as connected yet (the radio was just cycled): connect the
    -- device KinAMP last used, if it remembers one.
    local last = BT.getLastDevice and BT.getLastDevice()
    if last and last.mac then
        connect(last.mac)
    else
        callback(false)
    end
end

function Client.waitUntilRunning(callback)
    local B = backend()
    if not B then
        callback(false)
        return
    end
    B.wait_until_running(callback)
end

return Client
