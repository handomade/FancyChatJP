-- lib/imgui_font.lua
-- Ashita's default ImGui atlas (Agave) has no CJK.  Addon
-- AddFontFromFileTTF(path, size) only bakes Latin, so a "loaded"
-- Meiryo face still draws '?'.  We must pass Japanese glyph ranges,
-- preferably via io.Fonts:GetGlyphRangesJapanese(), and merge into
-- the default font so Settings/tabs pick them up without PushFont.
--
-- CatsEye's launcher rewrites boot.ini on each play.  Do not tell
-- users to set ResetIniFiles=false; that can freeze a broken boot
-- profile.  Runtime merge from Windows Fonts is the supported path.
--
-- AddFont + Build must not run inside d3d_present.  That callback is
-- between ImGui NewFrame and Render.  Rebuilding the atlas there frees
-- the texture the current frame is about to draw, and Present dies
-- with EXCEPTION_ACCESS_VIOLATION.  push() only notices a missing
-- CJK font.  flush() from d3d_endscene does the add between frames.

require('common')
local imgui     = require('imgui')
local imguiWrap = require('imguiWrap')
local ffi       = require('ffi')

local M = {
	font     = nil,
	size     = 18,
	depth    = 0,
	verified = false,
	usable   = false,
	merged   = false,
	pending  = false,
}

-- Inclusive pairs, 0-terminated.  Ashita 4.16 does not bind
-- GetGlyphRangesJapanese, so this array is what Build() reads.
local RANGE_TABLE = {
	0x0020, 0x00FF,
	0x2000, 0x206F,
	0x3000, 0x30FF,
	0x31F0, 0x31FF,
	0x4E00, 0x9FFF,
	0xFF00, 0xFFEF,
	0xFFFD, 0xFFFD,
	0,
}

ffi.cdef[[
typedef unsigned short ImWchar;
typedef void (__thiscall *fc_gettext_rgba_t)(void* self, unsigned char** pixels, int* w, int* h, int* bpp);
typedef int (__stdcall *fc_create_tex_t)(void* self, unsigned int w, unsigned int h, unsigned int levels, unsigned int usage, unsigned int fmt, unsigned int pool, void** outTex);
typedef int (__stdcall *fc_lock_rect_t)(void* self, unsigned int level, void* locked, const void* rect, unsigned int flags);
typedef int (__stdcall *fc_unlock_rect_t)(void* self, unsigned int level);
]]

-- ImGui 1.81 stores this pointer and reads it again inside Build().
local RANGES = ffi.new('ImWchar[?]', #RANGE_TABLE)
for i, v in ipairs(RANGE_TABLE) do
	RANGES[i - 1] = v
end

-- VanaCore's binding accepts this blob as the glyph-range argument.
-- CatsEye's binding rejects it, so that client never uses this value.
local function pack_u16le(vals)
	local bytes = {}
	for i, v in ipairs(vals) do
		local n = tonumber(v) or 0
		bytes[i] = string.char(n % 256, math.floor(n / 256) % 256)
	end
	return table.concat(bytes)
end
local RANGE_BLOB = pack_u16le(RANGE_TABLE)

local HIRAGANA_A = '\227\129\130'

local function file_exists(path)
	local f = io.open(path, 'rb')
	if not f then return false end
	f:close()
	return true
end

local function text_width(s)
	local ok, a = pcall(function()
		local x = imgui.CalcTextSize(s)
		if type(x) == 'number' then return x end
		if type(x) == 'table' and x.x then return x.x end
		return 0
	end)
	if ok and type(a) == 'number' then return a end
	return 0
end

local function current_has_cjk()
	local w_jp = text_width(HIRAGANA_A)
	local w_q  = text_width('?')
	return w_jp > 0 and w_q > 0 and w_jp > w_q * 1.15
end

local function io_fonts()
	local ok, fonts = pcall(function() return imgui.GetIO().Fonts end)
	if ok then return fonts end
	return nil
end

local function trim_slash(path)
	return (tostring(path or ''):gsub('[\\/]+$', ''))
end

local function parent_dir(path)
	return trim_slash(path):match('^(.*)[\\/]')
end

-- Ashita\addons\fancychat -> Ashita.  GetInstallPath is normally that
-- Ashita folder, but a launcher can point it at the game root instead.
local function ashita_dirs()
	local dirs = {}
	local function add(path)
		path = trim_slash(path)
		if path == '' then return end
		for _, have in ipairs(dirs) do
			if have:lower() == path:lower() then return end
		end
		dirs[#dirs + 1] = path
	end
	pcall(function() add(AshitaCore:GetInstallPath()) end)
	pcall(function()
		if addon and addon.path then
			local addons = parent_dir(addon.path)
			add(parent_dir(addons))
			add(addons)
		end
	end)
	return dirs
end

local function font_candidates()
	local names = {
		'meiryo.ttc',
		'msgothic.ttc',
		'YuGothM.ttc',
		'YuGothR.ttc',
		'YuGothB.ttc',
	}
	local list = {}
	local function add(path)
		if path and path ~= '' then list[#list + 1] = path end
	end
	for _, dir in ipairs(ashita_dirs()) do
		for _, name in ipairs(names) do
			add(dir .. '\\resources\\fonts\\' .. name)
		end
	end
	for _, name in ipairs(names) do
		add('C:\\Windows\\Fonts\\' .. name)
	end
	local local_fonts = os.getenv('LOCALAPPDATA')
	if local_fonts and local_fonts ~= '' then
		for _, name in ipairs(names) do
			add(local_fonts .. '\\Microsoft\\Windows\\Fonts\\' .. name)
		end
	end
	return list
end

local function sol_word(obj)
	-- tostring of a userdata is its payload address.  Sol stores the
	-- C pointer in the first word of that payload.
	local hex = tostring(obj):match('0x(%x+)')
	if hex then
		local payload = tonumber(hex, 16)
		if payload and payload > 0x10000 then
			local ok, inner = pcall(function()
				return tonumber(ffi.cast('uintptr_t*', payload)[0])
			end)
			if ok and inner and inner > 0x10000 then return inner end
		end
	end
	local ok, p = pcall(function()
		return tonumber(ffi.cast('uintptr_t*', obj)[0])
	end)
	if ok and p and p > 0x10000 then return p end
	return nil
end

local function is_pow2_tex(n)
	return n == 256 or n == 512 or n == 1024 or n == 2048 or n == 4096 or n == 8192
end

-- ImGui 1.81 ImFontAtlas, 32-bit, no vtable.  Checked before any write.
local OFF_TEXID    = 8
local OFF_PIX_A8   = 20
local OFF_PIX_RGBA = 24
local OFF_TEX_W    = 28
local OFF_TEX_H    = 32

local function atlas_from(fonts)
	local addr = sol_word(fonts)
	if not addr or addr < 0x10000 then return nil end
	local ok, good = pcall(function()
		local base = ffi.cast('uint8_t*', addr)
		local w = ffi.cast('int*', base + OFF_TEX_W)[0]
		local h = ffi.cast('int*', base + OFF_TEX_H)[0]
		local locked = base[0]
		return locked <= 1 and is_pow2_tex(w) and is_pow2_tex(h)
	end)
	if ok and good then return addr end
	return nil
end

local function device_ptr()
	local obj
	pcall(function() obj = AshitaCore:GetDirect3DDevice() end)
	if not obj then return nil end
	local addr = sol_word(obj)
	if not addr or addr < 0x10000 then return nil end
	local ok = pcall(function()
		local vt = ffi.cast('uintptr_t*', addr)[0]
		if vt < 0x10000 then error('vt') end
	end)
	if not ok then return nil end
	return addr
end

-- Ashita 4.16 binds AddFontFromFileTTF but not ImFontAtlas::Build.
-- GetTexDataAsRGBA32 builds the atlas when the CPU pixels are cleared,
-- then the new pixels are uploaded over a fresh texture.
local function rebuild_old_atlas(fonts)
	local atlas = atlas_from(fonts)
	local dev = device_ptr()
	if not atlas or not dev then
		print('FancyChat: ImGui atlas rebuild skipped')
		return false
	end
	local gettex = ashita.memory.find(
		'Ashita.dll', 0,
		'558BEC81EC0C010000A1????????33C58945FC8B4508538BD9',
		0, 0)
	if not gettex or gettex == 0 then
		print('FancyChat: ImGui GetTexData not found')
		return false
	end

	local base = ffi.cast('uint8_t*', atlas)
	ffi.cast('void**', base + OFF_PIX_A8)[0] = nil
	ffi.cast('void**', base + OFF_PIX_RGBA)[0] = nil

	local pixels = ffi.new('unsigned char*[1]')
	local tw, th, tb = ffi.new('int[1]'), ffi.new('int[1]'), ffi.new('int[1]')
	local getfn = ffi.cast('fc_gettext_rgba_t', gettex)
	getfn(base, pixels, tw, th, tb)
	local width, height = tw[0], th[0]
	if not pixels[0] or not is_pow2_tex(width) or height < 64 then
		print('FancyChat: ImGui atlas build produced no pixels')
		return false
	end

	local devvt = ffi.cast('void**', ffi.cast('void***', dev)[0])
	local create = ffi.cast('fc_create_tex_t', devvt[20])
	local tex = ffi.new('void*[1]')
	-- Matches Ashita's own font texture: A8R8G8B8, dynamic, default pool.
	local hr = create(ffi.cast('void*', dev), width, height, 1, 0x200, 21, 0, tex)
	if hr ~= 0 or tex[0] == nil then
		print(string.format('FancyChat: ImGui texture create failed (%08X)', hr or 0))
		return false
	end

	local texvt = ffi.cast('void**', ffi.cast('void***', tex[0])[0])
	local lock = ffi.cast('fc_lock_rect_t', texvt[16])
	local unlock = ffi.cast('fc_unlock_rect_t', texvt[17])
	local locked = ffi.new('char[8]')
	hr = lock(tex[0], 0, locked, nil, 0)
	if hr ~= 0 then
		print(string.format('FancyChat: ImGui texture lock failed (%08X)', hr))
		return false
	end
	local pitch = ffi.cast('int*', locked)[0]
	local dst = ffi.cast('uint8_t*', ffi.cast('void**', locked + 4)[0])
	local src = pixels[0]
	for y = 0, height - 1 do
		local srow = src + y * width * 4
		local drow = dst + y * pitch
		for x = 0, width - 1 do
			local s = srow + x * 4
			local d = drow + x * 4
			d[0] = s[2]
			d[1] = s[1]
			d[2] = s[0]
			d[3] = s[3]
		end
	end
	unlock(tex[0], 0)
	ffi.cast('void**', base + OFF_TEXID)[0] = tex[0]
	print(string.format('FancyChat: ImGui atlas rebuilt %dx%d', width, height))
	return true
end

-- ImFontConfig on ImGui 1.81 / 32-bit.  SizePixels and the default
-- GlyphRanges (starts at U+0020) identify the entry AddFont just appended.
local CONFIG_SIZE = 120
local OFF_CFG_SIZE = 16
local OFF_CFG_RANGES = 48
local OFF_CFG_MERGE = 60

local function patch_glyph_ranges(atlas)
	local base = ffi.cast('uint8_t*', atlas)
	local function last_config(off)
		local count = ffi.cast('int*', base + off)[0]
		local data = tonumber(ffi.cast('uintptr_t', ffi.cast('void**', base + off + 8)[0]))
		if not count or count < 1 or count > 8 or not data or data < 0x10000 then return nil end
		local cfg = ffi.cast('uint8_t*', data) + (count - 1) * CONFIG_SIZE
		local px = ffi.cast('float*', cfg + OFF_CFG_SIZE)[0]
		if px < 8 or px > 64 then return nil end
		local ranges = tonumber(ffi.cast('uintptr_t', ffi.cast('void**', cfg + OFF_CFG_RANGES)[0]))
		if not ranges or ranges < 0x10000 then return nil end
		if ffi.cast('ImWchar*', ranges)[0] ~= 0x20 then return nil end
		return cfg
	end
	for _, off in ipairs({ 76, 64, 88, 100 }) do
		local ok, cfg = pcall(last_config, off)
		if ok and cfg then
			ffi.cast('void**', cfg + OFF_CFG_RANGES)[0] = RANGES
			cfg[OFF_CFG_MERGE] = 1
			return true
		end
	end
	print('FancyChat: ImGui glyph ranges were not stored')
	return false
end

local function jp_ranges(fonts)
	if not fonts then return RANGE_BLOB end
	local ok, ptr = pcall(function()
		if fonts.GetGlyphRangesJapanese then
			return fonts:GetGlyphRangesJapanese()
		end
		return fonts.GetGlyphRangesJapanese(fonts)
	end)
	if ok and ptr then return ptr end
	return RANGE_BLOB
end

local function try_add(path, size)
	local fonts = io_fonts()
	if not fonts then return nil end
	local cfg = { MergeMode = true, PixelSnapH = true, FontNo = 0 }
	local attempts = {}
	-- VanaCore (ImGui 1.92) takes the range argument and rasterises
	-- on use.  This is the registration that already shows Japanese.
	if imguiWrap.isNewVer then
		local ranges = jp_ranges(fonts)
		attempts[#attempts + 1] = function()
			return fonts:AddFontFromFileTTF(path, size, cfg, ranges)
		end
		attempts[#attempts + 1] = function()
			return fonts:AddFontFromFileTTF(path, size, nil, ranges)
		end
		attempts[#attempts + 1] = function()
			return fonts:AddFontFromFileTTF(path, size, cfg, RANGE_TABLE)
		end
	end
	-- CatsEye (ImGui 1.81) rejects that argument.  Register the face
	-- without it, then point the atlas config at RANGES and upload
	-- a new texture.  That upload must not run on 1.92.
	attempts[#attempts + 1] = function()
		return fonts:AddFontFromFileTTF(path, size, cfg)
	end
	attempts[#attempts + 1] = function()
		return fonts:AddFontFromFileTTF(path, size)
	end
	local ranged_attempts = imguiWrap.isNewVer and 3 or 0
	for i, fn in ipairs(attempts) do
		local ok, font = pcall(fn)
		if ok and font then
			local ranged = i <= ranged_attempts
			if not ranged and not imguiWrap.isNewVer then
				local atlas = atlas_from(fonts)
				if atlas then patch_glyph_ranges(atlas) end
				if not rebuild_old_atlas(fonts) then return nil end
			end
			M.added_with_ranges = ranged
			return font
		end
	end
	return nil
end

function M.bake()
	-- Called from d3d_endscene, outside NewFrame.  Do not CalcTextSize
	-- or GetFontSize here; those require a frame.
	if M.font or M.merged then return true end

	local size = M.size or 18
	local found = {}
	for _, path in ipairs(font_candidates()) do
		if file_exists(path) then
			found[#found + 1] = path
			local font = try_add(path, size)
			if font then
				M.font = font
				print(string.format('FancyChat: added ImGui font %s', path))
				return true
			end
			print(string.format('FancyChat: ImGui font file found but not accepted: %s', path))
		end
	end

	if #found == 0 then
		local where = ''
		pcall(function() where = trim_slash(AshitaCore:GetInstallPath() or '') end)
		print('FancyChat: no CJK font file found. Ashita=' .. where)
		print('FancyChat: put meiryo.ttc in Ashita\\resources\\fonts\\ (the Ashita folder, not the game folder).')
	else
		print('FancyChat: could not add a CJK ImGui font this session')
	end
	return false
end

local function push_raw()
	if not M.font then return end
	if imguiWrap.isNewVer then
		local size = M.size
		pcall(function()
			if M.font.LegacySize then size = M.font.LegacySize end
		end)
		imgui.PushFont(M.font, size)
	else
		imgui.PushFont(M.font)
	end
	M.depth = M.depth + 1
end

function M.push()
	-- Boot [ashita.imgui.fonts] is_jp already baked CJK into the default
	-- face: never PushFont, and do not probe CalcTextSize every frame.
	if M.merged then return false end
	if M.boot_cjk == nil then
		M.boot_cjk = current_has_cjk()
	end
	if M.boot_cjk then
		M.merged = true
		M.font   = nil
		return false
	end
	-- Notice the missing face here, but do not AddFont or Build.
	-- Those run in flush() between frames.  Building the atlas inside
	-- Present is what crashed CatsEye (interface 4.16).
	if not M.font and not M.bake_tried then
		M.bake_tried = true
		pcall(function()
			local s = imgui.GetFontSize()
			if type(s) == 'number' and s >= 12 then M.size = s end
		end)
		M.pending = true
		return false
	end
	if M.pending or not M.font then return false end

	if not M.verified then
		push_raw()
		local has = current_has_cjk()
		M.pop()
		-- MergeMode returns the default font pointer.  If CJK is now on
		-- the default face (with or without our PushFont), we are done.
		if current_has_cjk() then
			M.verified = true
			M.usable   = false
			M.merged   = true
			M.font     = nil
			print('FancyChat: Japanese glyphs available on the default ImGui font')
			return false
		end
		M.verified = true
		M.usable   = has
		if not M.usable then
			print(string.format(
				'FancyChat: CJK probe failed (jp=%.1f ?=%.1f). Boot is_jp font needs a full FFXI restart.',
				text_width(HIRAGANA_A), text_width('?')))
			M.font = nil
			return false
		end
	end

	if not M.usable then return false end
	push_raw()
	return true
end

function M.flush()
	if not M.pending then return end
	M.pending = false
	local ok = pcall(M.bake)
	if not ok then
		print('FancyChat: ImGui font add failed')
		M.font = nil
		return
	end
	-- 1.92 rasterises on first use.  The face is ready next Present.
	-- 1.92 rasterises on first use, but only after the range argument
	-- was accepted.  A face added without ranges stays Latin.
	if M.font and imguiWrap.isNewVer and M.added_with_ranges then
		M.verified = true
		M.usable   = true
	end
end

function M.pop()
	if M.depth <= 0 then return end
	imgui.PopFont()
	M.depth = M.depth - 1
end

return M
