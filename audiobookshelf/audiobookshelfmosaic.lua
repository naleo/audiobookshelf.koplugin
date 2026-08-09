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
local Button = require("ui/widget/button")
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
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = require("device").screen
local T = require("ffi/util").template
local _ = require("audiobookshelf/absi18n")
local logger = require("logger")

local AudiobookshelfMosaic = InputContainer:extend{
    cols = 3,
    rows = 3,
    items = nil,       -- array of ABS library items
    page = 0,          -- 0-based
    total = 0,
    library_id = nil,
    library_name = nil,
    active_tag = "",      -- current tag filter ("" = none), for the Filter row
    on_open = nil,        -- function(item) called on cover tap
    on_page = nil,        -- function(new_page) called to re-page
    on_close = nil,
    on_toggle_list = nil, -- function() switch back to text list
    on_search = nil,      -- function() open the search dialog (title bar left icon)
    on_filter = nil,      -- function() open the tag picker (Filter row)
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
    local this = self
    local scr_w, scr_h = Screen:getWidth(), Screen:getHeight()
    local per_page = self.cols * self.rows
    local total_pages = math.max(1, math.ceil((self.total or #self.items) / per_page))

    -- ── Title bar: same chrome as the list view (search icon left, title, X) ──
    local title_bar = TitleBar:new{
        width = scr_w,
        align = "center",
        title = self.library_name or _("Library"),
        title_multilines = false,
        left_icon = "appbar.search",
        left_icon_tap_callback = function()
            if this.on_search then this.on_search() end
        end,
        close_callback = function()
            if this.on_close then this.on_close() end
        end,
        show_parent = self,
    }
    local title_h = title_bar:getHeight()

    -- ── Filter + View rows (same text styling as the list-view rows) ──
    local margin = Size.margin.default
    local row_face = Font:getFace("cfont", 20)
    local row_h = math.floor(Screen:scaleBySize(38))
    local grid_w = scr_w - margin * 2

    local function make_menu_row(label, on_tap)
        local text_w = TextWidget:new{ text = label, face = row_face, max_width = grid_w }
        local row = InputContainer:new{
            dimen = Geom:new{ w = grid_w, h = row_h },
            FrameContainer:new{
                width = grid_w, height = row_h, bordersize = 0,
                padding = Size.padding.small,
                text_w,
            },
        }
        row.ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = function() return row.dimen end } },
        }
        function row:onTap() if on_tap then on_tap() end; return true end
        return row
    end

    local filter_label = (self.active_tag ~= "" and self.active_tag ~= nil)
        and T(_("⚑ Filter: %1 (tap to change)"), self.active_tag)
        or _("⚑ Filter: all books (tap to filter)")
    local filter_row = make_menu_row(filter_label, function()
        if this.on_filter then this.on_filter() end
    end)
    local view_row = make_menu_row(_("▦ View: cover mosaic (tap for list)"), function()
        if this.on_toggle_list then this.on_toggle_list() end
    end)

    local sep = LineWidget:new{
        dimen = Geom:new{ w = grid_w, h = Size.line.thin },
        background = Blitbuffer.COLOR_GRAY,
    }

    -- ── Page info footer with chevrons, mimicking Menu's paginator ──
    local page_text = TextWidget:new{
        text = T(_("%1 / %2"), self.page + 1, total_pages),
        face = Font:getFace("cfont", 16),
    }
    local left_chev = Button:new{
        icon = "chevron.left", width = Screen:scaleBySize(34), bordersize = 0,
        show_parent = self,
        callback = function()
            if this.page > 0 and this.on_page then this.on_page(this.page - 1) end
        end,
    }
    local right_chev = Button:new{
        icon = "chevron.right", width = Screen:scaleBySize(34), bordersize = 0,
        show_parent = self,
        callback = function()
            if (this.page + 1) < total_pages and this.on_page then this.on_page(this.page + 1) end
        end,
    }
    if self.page <= 0 then left_chev:disable() end
    if (self.page + 1) >= total_pages then right_chev:disable() end
    local footer = HorizontalGroup:new{
        align = "center",
        left_chev,
        HorizontalSpan:new{ width = Size.span.horizontal_default },
        page_text,
        HorizontalSpan:new{ width = Size.span.horizontal_default },
        right_chev,
    }
    local footer_h = math.max(left_chev:getSize().h, page_text:getSize().h) + Size.padding.default * 2

    -- ── Grid geometry (space left after chrome) ──
    local chrome_h = title_h + row_h * 2 + sep:getSize().h + footer_h
    local grid_h = scr_h - chrome_h - margin
    local cell_w = math.floor(grid_w / self.cols)
    local cell_h = math.floor(grid_h / self.rows)

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
        title_bar,
        filter_row,
        view_row,
        sep,
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
        padding = 0,
        content,
    }
end

--[[--
Build a "fake cover" for items without a cover image: a bordered card showing
title (large) and author (small), font auto-shrunk to fit. Mirrors the look of
KOReader's stock coverbrowser FakeCover, minus the file-based machinery.
--]]
function AudiobookshelfMosaic:_buildFakeCover(title, author, w, h)
    local inner_w = w - Size.padding.default * 2
    -- Shrink the title font until it fits the available height (cheap 3-step).
    local title_wg, author_wg
    for _, tsize in ipairs({ 18, 15, 12 }) do
        title_wg = TextBoxWidget:new{
            text = title,
            face = Font:getFace("cfont", tsize),
            width = inner_w,
            alignment = "center",
        }
        if title_wg:getSize().h < h * 0.6 then break end
    end
    if author and author ~= "" then
        author_wg = TextBoxWidget:new{
            text = author,
            face = Font:getFace("cfont", 11),
            width = inner_w,
            alignment = "center",
        }
    end
    local inner = VerticalGroup:new{ align = "center", title_wg }
    if author_wg then
        table.insert(inner, VerticalSpan:new{ width = Size.padding.default })
        table.insert(inner, author_wg)
    end
    return FrameContainer:new{
        width = w,
        height = h,
        bordersize = Size.border.thin,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, inner },
    }
end

function AudiobookshelfMosaic:_buildCell(item, cell_w, cell_h)
    local meta = item.media and item.media.metadata or {}
    local title = meta.title or _("Untitled")
    local author = meta.authorName or ""

    local pad = Size.padding.small
    local caption_h = math.floor(cell_h * 0.22)
    local img_max_w = cell_w - pad * 2
    local img_max_h = cell_h - caption_h - pad * 2

    -- Cover (disk-cached), wrapped in a thin border + white background so it
    -- reads as a book, matching the stock mosaic look. Fall back to a titled
    -- FakeCover card if no cover is available.
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
        if ok and w then
            cover_widget = FrameContainer:new{
                bordersize = Size.border.thin,
                background = Blitbuffer.COLOR_WHITE,
                padding = 0,
                margin = 0,
                w,
            }
        end
    end
    if not cover_widget then
        cover_widget = self:_buildFakeCover(title, author, img_max_w, img_max_h)
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
