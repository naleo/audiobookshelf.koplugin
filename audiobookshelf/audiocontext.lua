-- Builds the real collaborators once and shares them between the UI and the
-- plugin's suspend/resume/exit handlers.
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Api = require("audiobookshelf/audiobookshelfapi")
local Kinamp = require("audiobookshelf/kinampclient")
local Session = require("audiobookshelf/audiosession")
local Store = require("audiobookshelf/audiostore")

local Context = {}
local instance

-- Resume this many seconds before the saved position: the seek and the Bluetooth
-- reconnect swallow a few seconds of audio, and a short recap helps anyway.
local REWIND_SECONDS = 30

-- After a fresh player start, disconnect and reconnect the headset once playback
-- is running at the right position. Tested on a Kindle with AirPods (firmware
-- 5.19): the audio link is silent until this happens, even when the player is
-- started directly without KinAMP's Bluetooth radio cycle.
local RECONNECT_ON_COLD_START = true

function Context.get()
    if instance then return instance end
    local config_file = string.gsub(debug.getinfo(1).source, "^@(.+/)[^/]+$", "%1") .. "/../audiobookshelf_config.lua"
    local settings = LuaSettings:open(config_file)
    local store = Store.new(LuaSettings:open(DataStorage:getSettingsDir() .. "/audiobookshelf_audio.lua"))
    local session = Session.new({
        api = Api,
        store = store,
        kinamp = Kinamp,
        rewind = REWIND_SECONDS,
        reconnect_on_cold_start = RECONNECT_ON_COLD_START,
        log = function(message) logger.warn("audiobookshelf session:", message) end,
        sched = {
            scheduleIn = function(seconds, fn) UIManager:scheduleIn(seconds, fn) end,
            unschedule = function(fn) UIManager:unschedule(fn) end,
        },
        notify = function(message)
            UIManager:show(InfoMessage:new{ text = message, timeout = 3 })
        end,
    })
    instance = { api = Api, settings = settings, store = store, session = session, kinamp = Kinamp,
                 rewind = REWIND_SECONDS }
    return instance
end

function Context.peek()
    return instance
end

return Context
