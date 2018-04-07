require 'cairo'
require 'imlib2'

local cmus_info = {}
local artwork_image_data = nil

-- some helper functions

local function list_dir(dir)
    local files = {}
    local pfile = io.popen('ls -a "'..dir..'"')
    local i = 0
    for filename in pfile:lines() do
        i = i + 1
        files[i] = filename
    end
    pfile:close()
    return files
end

local function dirname(file)
    if file:match(".-/.-") then
	    local dir = string.gsub(file, "(.*)(/.*)", "%1")
	    return dir
	else
        return '.'
    end
end

local function table_has_value (tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end



local function find_album_art(dir)
    -- try to find album art in same folder where playing track is
    local files = list_dir(dir)
    local matching_names = {
        'folder.jpg', 'Folder.jpg', 'folder.png', 'Folder.png'
    }
    for index, artwork_filename in ipairs(matching_names) do
        if table_has_value(files, artwork_filename) then
            return dir..'/'..artwork_filename
        end
    end

    local extensions = {'.jpg', '.jpeg', '.png'}
    for file_idx, file in ipairs(files) do
        for index, extension in ipairs(extensions) do
            if string.find(file, extension..'$') then
                return dir..'/'..file
            end
        end
    end
end

local function artwork_image_update(file)
    -- artwork is updated only on track change

    -- artwork size
    local width = 100
    local height = 100

    if artwork_image_data ~= nil then
        imlib_context_set_image(artwork_image_data)
        imlib_free_image()
    end

    local image = imlib_load_image(file)
    if image == nil then
        print('Cannot load image!')
        print(file)
        return
    end

    imlib_context_set_image(image)
    artwork_image_data = imlib_create_cropped_scaled_image(
        0, 0, imlib_image_get_width(), imlib_image_get_height(),
        width, height
    )
    imlib_free_image()
end

local function artwork_image_draw()
    local x = 380
    local y = 30
    imlib_context_set_image(artwork_image_data)
    imlib_render_image_on_drawable(x, y)
end



local function pretty_time(num_of_seconds)
	local min = math.floor(num_of_seconds / 60)
	local sec = num_of_seconds % 60
	if sec < 10 then
		sec = "0"..sec
	end
	return min..":"..sec
end

local function cmus_get_info()
    local f = io.popen("cmus-remote -Q")
    local line = f:read("*l")

    while line do
        if string.find(line, "^file") then
            local file = string.match(line, ".*", 6)

            --check if playing track has changed
            --  if so, update album art
            if file ~= cmus_info.file then
                local album_art = find_album_art(dirname(file))
                artwork_image_update(album_art)
            end
            cmus_info.file = string.match(line, ".*", 6)
        elseif string.find(line, "^status") then
            cmus_info.status = string.match(line, "[%w]*", 8)
        elseif string.find(line, "^duration") then
            cmus_info.duration = tonumber(string.match(line, "%d*", 10))
        elseif string.find(line, "^position") then
            cmus_info.position = tonumber(string.match(line, "%d*", 10))
        elseif string.find(line, "^tag title") then
            cmus_info.title = string.match(line, ".*", 11)
        elseif string.find(line, "^tag artist") then
            cmus_info.artist = string.match(line, ".*", 12)
        elseif string.find(line, "^tag album ") then
            cmus_info.album = string.match(line, ".*", 11)
        elseif string.find(line, "^tag date") then
            cmus_info.date = string.match(line, ".*", 10)
        elseif string.find(line, "^tag tracknumber") then
            cmus_info.tracknumber = string.match(line, ".*", 17)
        end
        line = f:read("*l")
    end
    f:close()

    return cmus_info
end

local function rgb_to_r_g_b(color, alpha)
    local color_r = ((color / 0x10000) % 0x100) / 255.
    local color_g = ((color / 0x100) % 0x100) / 255.
    local color_b = (color % 0x100) / 255.
	return color_r, color_g, color_b, alpha
end

local function progress_bar_draw(cr)
    bg_color = 0x3b3b3b
    bg_alpha = 0.6

    fg_alpha = 0.8
    if cmus_info.status == 'playing' then
        fg_color = 0x34cdff
    else
        fg_color = 0xff7200
    end

    bar_bottom_left_x= 160
    bar_bottom_left_y= 103
    bar_width= 200
    bar_height= 5

    -- draw progress bar background
    cairo_set_source_rgba(cr, rgb_to_r_g_b(bg_color, bg_alpha))
    cairo_rectangle(cr, bar_bottom_left_x, bar_bottom_left_y,
                    bar_width, bar_height)
    cairo_fill(cr)

    -- draw progress bar
    cairo_set_source_rgba(cr, rgb_to_r_g_b(fg_color, fg_alpha))
    value = cmus_info.position
    max_value = cmus_info.duration
    scale = value / max_value
    progress_bar_width = scale * bar_width
    cairo_rectangle(cr, bar_bottom_left_x, bar_bottom_left_y,
                    progress_bar_width, bar_height)
    cairo_fill(cr)
end


-- conky API

function conky_cmus_get_status()
    return cmus_info.status
end

function conky_cmus_get_duration()
    return pretty_time(cmus_info.duration)
end

function conky_cmus_get_current_time()
    return pretty_time(cmus_info.position)
end

function conky_cmus_get_artist()
    return cmus_info.artist
end

function conky_cmus_get_artist_uppercase()
    return cmus_info.artist:upper()
end

function conky_cmus_get_album()
    return cmus_info.album
end

function conky_cmus_get_song_title()
    return cmus_info.title
end

function conky_cmus_get_track_number()
    return cmus_info.tracknumber
end

function conky_cmus_get_date()
    return cmus_info.date
end

function conky_cmus_get_position()
    return cmus_info.position
end

function conky_main()
    if conky_window == nil then
        return
    end
    local cmus_info = cmus_get_info()
    local cs = cairo_xlib_surface_create(conky_window.display,
                                         conky_window.drawable,
                                         conky_window.visual,
                                         conky_window.width,
                                         conky_window.height)
    cr = cairo_create(cs)
    local updates = tonumber(conky_parse('${updates}'))
    if updates > 5 then
        if cmus_info.status ~= 'stopped' then
            progress_bar_draw(cr)
            artwork_image_draw()
        end
    end
    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

