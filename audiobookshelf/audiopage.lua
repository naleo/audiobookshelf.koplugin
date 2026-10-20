-- The audiobook page: cover artwork on top, then the book's details, then the
-- buttons. KOReader's ButtonDialog cannot hold an image, so this is a small
-- dialog of its own. Callers fall back to a plain ButtonDialog if building it fails.
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen

local AudioPage = InputContainer:extend{
    modal = true,
    title = "",    -- the details text
    buttons = {},  -- rows of buttons, same shape as ButtonDialog
    image = nil,   -- optional blitbuffer with the cover
}

function AudioPage:init()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local width = math.floor(screen_w * 0.88)
    local pad = Size.padding.large
    local inner = width - 2 * pad - 2 * Size.border.window

    local group = VerticalGroup:new{ align = "center" }
    if self.image then
        table.insert(group, ImageWidget:new{
            image = self.image,
            image_disposable = true, -- the blitbuffer is freed with the widget
            width = inner,
            height = math.floor(screen_h * 0.30),
            scale_factor = 0, -- fit, keeping the aspect ratio
        })
        table.insert(group, VerticalSpan:new{ width = pad })
    end
    table.insert(group, TextBoxWidget:new{
        text = self.title,
        face = Font:getFace("cfont", 20),
        width = inner,
        alignment = "center",
    })
    table.insert(group, VerticalSpan:new{ width = pad })
    self.button_table = ButtonTable:new{
        buttons = self.buttons,
        width = inner,
        show_parent = self,
    }
    table.insert(group, self.button_table)

    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = pad,
        margin = 0,
        group,
    }
    self.dimen = Geom:new{ w = screen_w, h = screen_h }
    self[1] = CenterContainer:new{ dimen = self.dimen, self.frame }

    if Device:isTouchDevice() then
        self.ges_events = {
            TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } },
        }
    end
end

function AudioPage:onTapClose(arg, ges)
    if ges and ges.pos and self.frame.dimen and ges.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

function AudioPage:onClose()
    UIManager:close(self)
    return true
end

function AudioPage:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
end

function AudioPage:onCloseWidget()
    UIManager:setDirty(nil, function() return "partial", self.frame.dimen end)
end

return AudioPage
