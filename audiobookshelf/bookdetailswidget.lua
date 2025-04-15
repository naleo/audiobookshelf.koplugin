local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local EbookFileWidget = require("audiobookshelf/ebookfilewidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local ListView = require("ui/widget/listview")
local RenderImage = require("ui/renderimage")
local Size = require("ui/size")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TitleBar = require("ui/widget/titlebar")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Device = require("device")
local Screen = Device.screen

local AudiobookshelfApi = require("audiobookshelf/audiobookshelfapi")

local BookDetailsWidget = FocusManager:extend{
    padding = Size.padding.fullscreen,
    onCloseParent = nil,
}

function BookDetailsWidget:onClose()
    UIManager:close(self)
    if self.onCloseParent then
        self:onCloseParent()
    end
end

function BookDetailsWidget:init()
    self.layout = {}

    self.book_info = AudiobookshelfApi:getLibraryItem(self.book_id)

    self.small_font = Font:getFace("smallffont")
    self.medium_font = Font:getFace("ffont")
    self.large_font = Font:getFace("largeffont")


    local screen_size = Screen:getSize()
    self.covers_fullscreen = true
    self[1] = FrameContainer:new{
        width = screen_size.w,
        height = screen_size.h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        self:getDetailsContent(screen_size.w)
    }

    self.dithered = true
end

function BookDetailsWidget:getDetailsContent(width)
    local title_bar = TitleBar:new{
        width = width,
        bottom_v_padding = 0,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    local content = VerticalGroup:new{
        align = "left",
        title_bar,
        self:genBookDetails(),
        self:genHeader("Description"),
        self:genDescriptionContent(),
        self:genHeader("Files"),
        self:genFileList(),
    }
    return content
end

function BookDetailsWidget:genFileList()
    local screen_height = Screen:getHeight()
    local screen_width = Screen:getWidth()
    local list = VerticalGroup:new{
        height =  screen_height * 0.2,
    }
    for _, file in ipairs(self.book_info.libraryFiles) do
        if file.fileType == "ebook" then
            table.insert(list, EbookFileWidget:new{
                width = screen_width,
                ino = file.ino,
                filename = file.metadata.filename,
                size_in_bytes =  file.metadata.size,
                book_id = self.book_info.id,
                onClose = self.onClose
            })
        end
    end
    return list
end



function BookDetailsWidget:genBookDetails()
    local screen_width = Screen:getWidth()

    local img_width, img_height
    if Screen:getScreenMode() == "landscape" then
        img_width = Screen:scaleBySize(132)
        img_height = Screen:scaleBySize(184)
    else
        img_width = Screen:scaleBySize(132 * 1.5)
        img_height = Screen:scaleBySize(184 * 1.5)
    end

    local book_authors = {}
    for _, author in ipairs(self.book_info.media.metadata.authors) do
        table.insert(book_authors, author.name)
    end
    local book_author_string = table.concat(book_authors, ", ")

    local book_metadata_group = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = img_height * 0.15},
    }
    table.insert(book_metadata_group,
        TextBoxWidget:new{ -- book title
            text = self.book_info.media.metadata.title,
            face = self.medium_font,
            alignment = "left",
        }
    )
    if self.book_info.media.metadata.seriesName ~= "" then
        table.insert(book_metadata_group,
            TextBoxWidget:new{ -- book series (if applicable)
                text = self.book_info.media.metadata.seriesName,
                face = self.small_font,
                alignment = "left",
            }
        )
    end
    table.insert(book_metadata_group,
        TextBoxWidget:new{ -- book author
            text = "by " .. book_author_string,
            face = self.small_font,
            alignment = "left",
        }
    )
    local metadata_label_group = VerticalGroup:new{
        align = "left",
        TextWidget:new{ -- book publish year
            text = "Publish year",
            face = self.small_font,
            alignment = "left",
            fgcolor = Blitbuffer.COLOR_GRAY_9,
        },
        TextWidget:new{ -- book publish year
            text = "Publisher",
            face = self.small_font,
            alignment = "left",
            fgcolor = Blitbuffer.COLOR_GRAY_9,
        },
        TextWidget:new{ -- book publish year
            text = "Genres",
            face = self.small_font,
            alignment = "left",
            fgcolor = Blitbuffer.COLOR_GRAY_9,
        },
        TextWidget:new{ -- book publish year
            text = "Language",
            face = self.small_font,
            alignment = "left",
            fgcolor = Blitbuffer.COLOR_GRAY_9,
        },
    }

    local metadata_labeled_group = VerticalGroup:new{
        align = "left",
        TextWidget:new{ -- book publish year
            text = self.book_info.media.metadata.publishedYear or "",
            face = self.small_font,
            alignment = "left",
        },
        TextWidget:new{ -- book publish year
            text = self.book_info.media.metadata.publisher or "",
            face = self.small_font,
            alignment = "left",
        },
        TextWidget:new{ -- book publish year
            text = table.concat(self.book_info.media.metadata.genres, ", ") or "",
            face = self.small_font,
            alignment = "left",
        },
        TextWidget:new{ -- book publish year
            text = self.book_info.media.metadata.language or "",
            face = self.small_font,
            alignment = "left",
        },
    }

    local extra_metadata_group = HorizontalGroup:new{
        align = "top",
        metadata_label_group,
        HorizontalSpan:new{ width = math.floor(screen_width * 0.02)},
        metadata_labeled_group,
    }

    table.insert(book_metadata_group, extra_metadata_group)



    local book_details_group = HorizontalGroup:new{
        align = "top",
        HorizontalSpan:new{ width = math.floor(screen_width * 0.05) }
    }

    local image = AudiobookshelfApi:getLibraryItemCover(self.book_id)

    if image then
        local actual_w, actual_h = image:getWidth(), image:getHeight()
        if actual_w > img_width or actual_h > img_height then
            local scale_factor = math.min(img_width / actual_w, img_height / actual_h)
            actual_w = math.min(math.floor(actual_w * scale_factor)+1, img_width)
            actual_h = math.min(math.floor(actual_h * scale_factor)+1, img_height)
            image = RenderImage:scaleBlitBuffer(image , actual_w, actual_h, true)
        end
    table.insert(book_details_group, ImageWidget:new{
        image = image,
        width = actual_w,
        height = actual_h
    })
    end

    table.insert(
        book_details_group,
        HorizontalSpan:new{ width = math.floor(screen_width * 0.05) }
    )
    table.insert(book_details_group, book_metadata_group)

    return book_details_group


end

function BookDetailsWidget:genHeader(title)
    local width, height = Screen:getWidth(), Size.item.height_default

    local header_title = TextWidget:new{
        text = title,
        face = self.medium_font,
        fgcolor = Blitbuffer.COLOR_GRAY_9
    }
    local padding_span = HorizontalSpan:new{ width = self.padding }
    local line_width = (width - header_title:getSize().w) / 2 - self.padding * 2
    local line_container = LeftContainer:new{
        dimen = Geom:new{ w = line_width, h = height },
        LineWidget:new{
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            dimen = Geom:new{
                w = line_width,
                h = Size.line.thick,
            }
        }
    }

    local span_top, span_bottom
    if Screen:getScreenMode() == "landscape" then
        span_top = VerticalSpan:new{ width = Size.span.horizontal_default }
        span_bottom = VerticalSpan:new{ width = Size.span.horizontal_default }
    else
        span_top = VerticalSpan:new{ width = Size.item.height_default }
        span_bottom = VerticalSpan:new{ width = Size.span.vertical_large }
    end

    return VerticalGroup:new{
        span_top,
        HorizontalGroup:new{
            align = "center",
            padding_span,
            line_container,
            padding_span,
            header_title,
            padding_span,
            line_container,
            padding_span,
        },
        span_bottom,
    }
end

function BookDetailsWidget:genDescriptionContent()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    local text = ScrollTextWidget:new{
        text = self:stripBasicHTMLTags(self.book_info.media.metadata.description or ""),
        face = self.small_font,
        width = screen_width - self.padding * 2,
        height = screen_height * 0.2,
        dialog = self,
    }
    return CenterContainer:new{
        dimen = Geom:new{ w = screen_width, h = text:getSize().h },
        text
    }
end

function BookDetailsWidget:stripBasicHTMLTags(text)
    return string.gsub(text, '<[^>]*>', '')
end

function BookDetailsWidget:onClose()
    UIManager:close(self, "flashpartial")
    return true
end

return BookDetailsWidget
