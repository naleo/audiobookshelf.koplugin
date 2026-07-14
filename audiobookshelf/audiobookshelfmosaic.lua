--[[--
Audiobookshelf cover-mosaic view.

Renders library items as a grid of cover thumbnails with a title caption,
mirroring the "mosaic with covers" look of the ABS web library. Covers are
fetched once via AudiobookshelfApi:getCachedCoverPath (disk-cached) so paging is
fast after the first view.

Tapping a cover opens the book details widget (same as the list view). Swipe
left/right pages. Honours the persisted tag filter passed in by the browser.

@module audiobookshelfmosaic
--]]

local AudiobookshelfApi = require("audiobookshelf/audiobookshelfapi")
local BookDetailsWidget = require("audiobookshelf/bookdetailswidget")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen
local T = require("ffi/util").template
local _ = require("gettext")
local logger = require("logger")

local AudiobookshelfMosaic = InputContainer:extend{
    cols = 3,
    rows = 3,
    items = nil,       -- array of ABS library items
    page = 0,          -- 0-based
    total = 0,
    library_id = nil,
    library_name = nil,
    on_open = nil,        -- function(item) called on cover tap
    on_page = nil,        -- function(new_page) called to re-page
    on_close = nil,
    on_toggle_list = nil, -- function() switch back to text list
}

function AudiobookshelfMosaic:init()
    self.dimen = Screen:getSize()
    self.ges_events = {
        Swipe = {
            GestureRange:new{ ges = "swipe", range = self.dimen },
        },
    }
    self[1] = self:_build()
end

function AudiobookshelfMosaic:_build()
    local scr_w, scr_h = Screen:getWidth(), Screen:getHeight()
    local margin = Size.margin.default
    local per_page = self.cols * self.rows
    local total_pages = math.max(1, math.ceil((self.total or #self.items) / per_page))

    -- Header + footer heights
    local header_h = math.floor(scr_h * 0.06)
    local footer_h = math.floor(scr_h * 0.05)
    local grid_w = scr_w - margin * 2
    local grid_h = scr_h - header_h - footer_h - margin * 2
    local cell_w = math.floor(grid_w / self.cols)
    local cell_h = math.floor(grid_h / self.rows)

    local header_text = TextWidget:new{
        text = T(_("%1  —  page %2/%3  (tap for list)"), self.library_name or _("Library"),
                 self.page + 1, total_pages),
        face = Font:getFace("tfont", 18),
        max_width = grid_w,
    }
    -- Tapping the header switches back to the text list.
    local this = self
    local header = InputContainer:new{
        dimen = Geom:new{ w = grid_w, h = header_h },
        CenterContainer:new{ dimen = Geom:new{ w = grid_w, h = header_h }, header_text },
    }
    header.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return header.dimen end } },
    }
    function header:onTap()
        if this.on_toggle_list then this.on_toggle_list() end
        return true
    end
    local footer = TextWidget:new{
        text = _("swipe ← / →   •   tap a cover to open   •   swipe ↓ to close"),
        face = Font:getFace("infofont", 13),
        max_width = grid_w,
    }

    local rows_group = VerticalGroup:new{ align = "left" }
    local idx = 1
    for r = 1, self.rows do
        local row = HorizontalGroup:new{ align = "top" }
        for c = 1, self.cols do
            local item = self.items[idx]
            if item then
                table.insert(row, self:_buildCell(item, cell_w, cell_h))
            else
                table.insert(row, HorizontalSpan:new{ width = cell_w })
            end
            idx = idx + 1
        end
        table.insert(rows_group, row)
    end

    local content = VerticalGroup:new{
        align = "center",
        header,
        VerticalSpan:new{ width = Size.span.vertical_default },
        rows_group,
        VerticalSpan:new{ width = Size.span.vertical_default },
        footer,
    }

    return FrameContainer:new{
        width = scr_w,
        height = scr_h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = margin,
        content,
    }
end

function AudiobookshelfMosaic:_buildCell(item, cell_w, cell_h)
    local meta = item.media and item.media.metadata or {}
    local title = meta.title or _("Untitled")

    local pad = Size.padding.small
    local caption_h = math.floor(cell_h * 0.22)
    local img_max_w = cell_w - pad * 2
    local img_max_h = cell_h - caption_h - pad * 2

    -- Cover (disk-cached). Fall back to a placeholder box if unavailable.
    local cover_widget
    local cover_path = AudiobookshelfApi:getCachedCoverPath(item.id)
    if cover_path then
        local ok, w = pcall(function()
            local iw = ImageWidget:new{
                file = cover_path,
                width = img_max_w,
                height = img_max_h,
                scale_factor = 0,   -- fit whole cover, keep aspect, no crop
            }
            iw:getSize()            -- force decode now to catch cache errors
            return iw
        end)
        if ok and w then cover_widget = w end
    end
    if not cover_widget then
        cover_widget = FrameContainer:new{
            width = img_max_w,
            height = img_max_h,
            bordersize = Size.border.thin,
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            CenterContainer:new{
                dimen = Geom:new{ w = img_max_w, h = img_max_h },
                TextBoxWidget:new{
                    text = title,
                    face = Font:getFace("infofont", 12),
                    width = img_max_w - 4,
                    alignment = "center",
                },
            },
        }
    end

    local caption = TextBoxWidget:new{
        text = title,
        face = Font:getFace("cfont", 14),
        width = cell_w - pad * 2,
        alignment = "center",
        height = caption_h,
    }

    local cell_content = VerticalGroup:new{
        align = "center",
        CenterContainer:new{ dimen = Geom:new{ w = img_max_w, h = img_max_h }, cover_widget },
        VerticalSpan:new{ width = pad },
        caption,
    }

    local cell = FrameContainer:new{
        width = cell_w,
        height = cell_h,
        bordersize = 0,
        padding = pad,
        cell_content,
    }

    -- Wrap in a tappable container.
    local this = self
    local tappable = InputContainer:new{
        dimen = Geom:new{ w = cell_w, h = cell_h },
        cell,
    }
    tappable.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function() return tappable.dimen end,
            },
        },
    }
    function tappable:onTap()
        if this.on_open then this.on_open(item) end
        return true
    end
    return tappable
end

function AudiobookshelfMosaic:onSwipe(arg, ges)
    local per_page = self.cols * self.rows
    local total_pages = math.max(1, math.ceil((self.total or #self.items) / per_page))
    local dir = ges.direction
    if dir == "west" and (self.page + 1) < total_pages then
        if self.on_page then self.on_page(self.page + 1) end
        return true
    elseif dir == "east" and self.page > 0 then
        if self.on_page then self.on_page(self.page - 1) end
        return true
    elseif dir == "south" then
        -- swipe down closes, matching common KOReader dismiss gesture
        if self.on_close then self.on_close() end
        return true
    end
    return false
end

function AudiobookshelfMosaic:onClose()
    if self.on_close then self.on_close() end
    return true
end

return AudiobookshelfMosaic
