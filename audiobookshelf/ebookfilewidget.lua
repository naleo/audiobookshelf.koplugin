local AudiobookshelfApi = require("audiobookshelf/audiobookshelfapi")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local DocumentRegistry = require("document/documentregistry")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LuaSettings = require("luasettings")
local OverlapGroup = require("ui/widget/overlapgroup")
local ReaderUI = require("apps/reader/readerui")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local util = require("util")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local T = require("ffi/util").template
local _ = require("gettext")



local EbookFileWidget = InputContainer:extend{
    filename = nil,
    ino = nil,
    size_in_bytes = 0,
    book_id = nil,
    width = nil,
    side_margin = Size.padding.fullscreen,
    onClose = nil -- function to close whole parent menu path after download
}

function EbookFileWidget:readSettings()
    self.abs_settings = LuaSettings:open("plugins/audiobookshelf.koplugin/audiobookshelf_config.lua")
    return self.abs_settings
end


function EbookFileWidget:init()


    self.small_font = Font:getFace("smallffont")
    self.medium_font = Font:getFace("ffont")
    self.large_font = Font:getFace("largeffont")


    local first_text = TextBoxWidget:new{
        text = self.filename or "",
        face = self.small_font,
        width = (self.width - self.side_margin * 2) * 0.75
    }
    local content_height = first_text:getSize().h
    local left_container = LeftContainer:new{
        dimen = Geom:new{w = self.width - self.side_margin * 2, h =  content_height},
        first_text
    }
    local last_text = TextWidget:new{
        text = util.getFriendlySize(self.size_in_bytes),
        face = self.small_font
    }
    local right_container = RightContainer:new{
        dimen = Geom:new{w = self.width - self.side_margin * 2, h = content_height},
        last_text,
    }
    local overlay_container = OverlapGroup:new{
        dimen = Geom:new{w = self.width - self.side_margin * 2, h = content_height},
        left_container,
        right_container
    }

    local underline_container = UnderlineContainer:new{
        linesize = Size.line.thin,
        padding = Size.padding.default,
        vertical_align = "center",
        color = Blitbuffer.COLOR_DARK_GRAY,
        overlay_container
    }
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = self.width, h = underline_container:getSize().h },
        underline_container
    }

    self.dimen = Geom:new{ w = self.width, h = underline_container:getSize().h }
    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen
            },
        },
        HoldSelect = {
            GestureRange:new{
                ges = self.handle_hold_on_hold_release and "hold_release" or "hold",
                range = self.dimen
            },
        },
    }

end

function EbookFileWidget:onTapSelect()
    -- make sure it exists first
    if not self[1].dimen then return end
    self:downloadFile()
end

function EbookFileWidget:onHoldSelect()
    -- make sure it exists first
    if not self[1].dimen then return end
    -- stub for adding long hold functionality
    logger.warn(self.book_id, self.ino)
end

function EbookFileWidget:downloadFile()
    local function startDownloadFile(filename, path, callback_close)
        local safeFilename = util.getSafeFilename(filename, path, 230)
        UIManager:scheduleIn(1, function()
            local code = AudiobookshelfApi:downloadFile(self.book_id, self.ino, safeFilename, path)
            if code == 200 then
                local __, filename = util.splitFilePathName(path)
                UIManager:show(ConfirmBox:new{
                    text = T(_("File saved to:\n%1\nWould you like to read the downloaded book now?"),
                        BD.filepath(path .. "/" .. safeFilename)),
                    ok_callback = function()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("SetupShowReader"))

                        if callback_close then
                            callback_close()
                        end
                        ReaderUI:showReader(path .. "/" .. safeFilename)
                    end
                })
            else
                UIManager:show(InfoMessage:new{
                    text = T(_("Could not save file to:\n%1"), BD.filepath(path)),
                    timeout = 3,
                })
            end
        end)
        UIManager:show(InfoMessage:new{
            text = _("Downloading. This might take a moment."),
            timeout = 1,
        })
    end

    local function genTitle(original_filename, size, filename, path)
        local filesize_str = self.size_in_bytes and util.getFriendlySize(self.size_in_bytes) or _("N/A")

        return T(_("Filename:\n%1\n\nFile size:\n%2\n\nDownload filename:\n%3\n\nDownload folder:\n%4"),
            original_filename, filesize_str, filename, BD.dirpath(path))
    end

    local abs_settings = self:readSettings()
    local download_dir = abs_settings:readSetting("download_dir") or G_reader_settings:readSetting("lastdir")
    local chosen_filename = self.filename

    local buttons = {
        {
            {
                text = "Choose folder",
                callback = function()
                    require("ui/downloadmgr"):new{
                        onConfirm = function(path)
                            abs_settings:saveSetting("download_dir", path)
                            abs_settings:flush()
                            download_dir = path
                            self.download_dialog:setTitle(genTitle(self.filename, self.size_in_bytes, chosen_filename, path))
                        end,
                    }:chooseDir(download_dir)
                end,
            },
            {
                text = _("Change filename"),
                callback = function()
                    local input_dialog
                    input_dialog = InputDialog:new{
                        title = _("Enter filename"),
                        input = chosen_filename,
                        input_hint = self.filename,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(input_dialog)
                                    end,
                                },
                                {
                                    text = _("Set filename"),
                                    is_enter_default = true,
                                    callback = function()
                                        chosen_filename = input_dialog:getInputValue()
                                        if chosen_filename == "" then
                                            chosen_filename = self.filename
                                        end
                                        UIManager:close(input_dialog)
                                        self.download_dialog:setTitle(genTitle(self.filename, self.size_in_bytes, chosen_filename, download_dir))
                                    end,
                                },
                            }
                        },
                    }
                    UIManager:show(input_dialog)
                    input_dialog:onShowKeyboard()
                end,
            },
        },
        {
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(self.download_dialog)
                end,
            },
            {
                text = _("Download"),
                callback = function()
                    UIManager:close(self.download_dialog)
                    local path_dir = (download_dir ~= "/" and download_dir or "")
                    local callback_close = function() self:onClose() end
                    if lfs.attributes(path_dir) then
                        UIManager:show(ConfirmBox:new{
                            text = _("File already exists. Would you like to overwrite it?"),
                            ok_callback = function()
                                startDownloadFile(chosen_filename, path_dir, callback_close)
                            end
                        })
                    else
                        startDownloadFile(path_dir, callback_close)
                    end
                end,
            },
        },
    }

    self.download_dialog = ButtonDialog:new{
        title = genTitle(self.filename, self.size_in_bytes, chosen_filename, download_dir),
        buttons = buttons,
    }
    UIManager:show(self.download_dialog)
end

return EbookFileWidget
