local AudiobookshelfApi = require("audiobookshelf/audiobookshelfapi")
local Menu = require("ui/widget/menu")
local _ = require("gettext")

local AudiobookshelfBrowser = Menu:extend{
    no_title= false,
    title = _("Audiobookshelf Browser"),
    is_popout = false,
    is_borderless = true,
    show_parent = nil
}

function AudiobookshelfBrowser:init()
    AudiobookshelfApi:getLibraries()
end

return AudiobookshelfBrowser
