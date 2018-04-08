require 'cairo'
require 'imlib2'

-- refresh rate factor used when cmus is not running or track is stopped
-- cmus will be checked on each <refresh_rate_factor_stopped>-th
--   conky update interval
local refresh_rate_factor_stopped = 8

-- progress bar colors
local progress_bar_bg_color = 0x3b3b3b
local progress_bar_bg_alpha = 0.6
local progress_bar_fg_color_playing = 0x34cdff
local progress_bar_fg_color_paused = 0xff7200
local progress_bar_fg_alpha = 0.8

-- global data
local cmus_info_global = nil
local artwork_image_data = nil
local current_refresh_rate_factor = refresh_rate_factor_stopped

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
        'folder.jpg', 'Folder.jpg', 'folder.png', 'Folder.png',
        'cover.jpg', 'cover.png', 'Cover.jpg', 'Cover.png',
        'front.jpg', 'front.png', 'Front.jpg', 'Front.png'
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
    local f = io.popen("cmus-remote -Q 2>&1")
    local line = f:read("*l")

    local info = {}

    while line do
        if string.find(line, "^file") then
            info.file = string.match(line, ".*", 6)
        elseif string.find(line, "^status") then
            local status = string.match(line, "[%w]*", 8)
            if status == 'stopped' then
                info = nil
                break
            end
            info.status = status
        elseif string.find(line, "^duration") then
            info.duration = tonumber(string.match(line, "%d*", 10))
        elseif string.find(line, "^position") then
            info.position = tonumber(string.match(line, "%d*", 10))
        elseif string.find(line, "^tag title") then
            info.title = string.match(line, ".*", 11)
        elseif string.find(line, "^tag artist") then
            info.artist = string.match(line, ".*", 12)
        elseif string.find(line, "^tag album ") then
            info.album = string.match(line, ".*", 11)
        elseif string.find(line, "^tag date") then
            info.date = string.match(line, ".*", 10)
        elseif string.find(line, "^tag tracknumber") then
            info.tracknumber = string.match(line, ".*", 17)
        end
        line = f:read("*l")
    end
    f:close()

    -- cannot find better approach to check if cmus-remote failed
    if info ~=nil and info.status == nil then
        info = nil
    end

    return info
end

local function rgb_to_r_g_b(color, alpha)
    local color_r = ((color / 0x10000) % 0x100) / 255.
    local color_g = ((color / 0x100) % 0x100) / 255.
    local color_b = (color % 0x100) / 255.
	return color_r, color_g, color_b, alpha
end

local function progress_bar_draw(cr, cmus_info)
    local progress_bar_fg_color
    if cmus_info.status == 'playing' then
        progress_bar_fg_color = progress_bar_fg_color_playing
    else
        progress_bar_fg_color = progress_bar_fg_color_paused
    end

    bar_bottom_left_x= 160
    bar_bottom_left_y= 103
    bar_width= 200
    bar_height= 5

    -- draw progress bar background
    cairo_set_source_rgba(
        cr, rgb_to_r_g_b(progress_bar_bg_color, progress_bar_bg_alpha)
    )
    cairo_rectangle(cr, bar_bottom_left_x, bar_bottom_left_y,
                    bar_width, bar_height)
    cairo_fill(cr)

    -- draw progress bar
    cairo_set_source_rgba(
        cr, rgb_to_r_g_b(progress_bar_fg_color, progress_bar_fg_alpha)
    )
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
    local status = 'stopped'
    if cmus_info_global ~= nil then
        status = cmus_info_global.status
    end
    return status
end

function conky_cmus_get_duration()
    local get_duration = ''
    if cmus_info_global ~= nil then
        get_duration = pretty_time(cmus_info_global.duration)
    end
    return get_duration
end

function conky_cmus_get_current_time()
    local current_time = ''
    if cmus_info_global ~= nil then
        current_time = pretty_time(cmus_info_global.position)
    end
    return current_time
end

function conky_cmus_get_artist()
    local artist = ''
    if cmus_info_global ~= nil then
        artist = cmus_info_global.artist
    end
    return artist
end

function conky_cmus_get_artist_uppercase()
    local artist_uppercase = ''
    if cmus_info_global ~= nil then
        artist_uppercase = cmus_info_global.artist:upper()
    end
    return artist_uppercase
end

function conky_cmus_get_album()
    local album = ''
    if cmus_info_global ~= nil then
        album = cmus_info_global.album
    end
    return album
end

function conky_cmus_get_song_title()
    local song_title = ''
    if cmus_info_global ~= nil then
        song_title = cmus_info_global.title
    end
    return song_title
end

function conky_cmus_get_track_number()
    local track_number = ''
    if cmus_info_global ~= nil then
        track_number = cmus_info_global.tracknumber
    end
    return track_number
end

function conky_cmus_get_date()
    local date = ''
    if cmus_info_global ~= nil then
        date = cmus_info_global.date
    end
    return date
end

function conky_cmus_get_position()
    local position = ''
    if cmus_info_global ~= nil then
        position = cmus_info_global.position
    end
    return position
end

function conky_main()
    if conky_window == nil then
        return
    end

    local cmus_info = cmus_info_global;
    local updates = tonumber(conky_parse('${updates}'))
    if updates % current_refresh_rate_factor == 0 then
        cmus_info = cmus_get_info()
    end

    if cmus_info == nil then
        current_refresh_rate_factor = refresh_rate_factor_stopped
    else
        current_refresh_rate_factor = 1

        local new_track = cmus_info.file
        local old_track = cmus_info_global and cmus_info_global.file

        -- check if playing track has changed. If so, update album art
        if new_track ~= old_track then
            local album_art = find_album_art(dirname(new_track))
            artwork_image_update(album_art)
        end

        local cs = cairo_xlib_surface_create(conky_window.display,
                                             conky_window.drawable,
                                             conky_window.visual,
                                             conky_window.width,
                                             conky_window.height)
        cr = cairo_create(cs)

        if updates > 5 then
            if cmus_info ~= nil then
                progress_bar_draw(cr, cmus_info)
                artwork_image_draw()
            end
        end
        cairo_destroy(cr)
        cairo_surface_destroy(cs)
    end

    cmus_info_global = cmus_info
end

