-- lib/imgui_font.lua
-- Ashita's default ImGui atlas (Agave) has no CJK.  Addon
-- AddFontFromFileTTF(path, size) only bakes Latin, so a "loaded"
-- Meiryo face still draws '?'.  We must pass Japanese glyph ranges,
-- preferably via io.Fonts:GetGlyphRangesJapanese(), and merge into
-- the default font so Settings/tabs pick them up without PushFont.
--
-- CatsEye's launcher rewrites boot ini unless ResetIniFiles is false;
-- the boot [ashita.imgui.fonts] is_jp=true path needs that.

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
}

-- Inclusive pairs, 0-terminated.  Used only if GetGlyphRangesJapanese
-- is not exposed to Lua.  Keep both a Lua table and a persistent
-- little-endian blob: some bindings take the 4th argument as a string
-- and use lua_tolstring as an ImWchar*.
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

local function pack_u16le(vals)
	local bytes = {}
	for i, v in ipairs(vals) do
		local n = tonumber(v) or 0
		bytes[i] = string.char(n % 256, math.floor(n / 256) % 256)
	end
	return table.concat(bytes)
end

-- Must outlive the font (ImFontConfig::GlyphRanges).
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

local function jp_ranges()
	local fonts = io_fonts()
	if fonts then
		local ok, ptr = pcall(function()
			if fonts.GetGlyphRangesJapanese then
				return fonts:GetGlyphRangesJapanese()
			end
			return fonts.GetGlyphRangesJapanese(fonts)
		end)
		if ok and ptr then return ptr end
	end
	return RANGE_BLOB
end

local function font_candidates()
	local install = ''
	pcall(function() install = AshitaCore:GetInstallPath() or '' end)
	return {
		install .. '/resources/fonts/meiryo.ttc',
		install .. '\\resources\\fonts\\meiryo.ttc',
		'C:\\Windows\\Fonts\\meiryo.ttc',
		'C:\\Windows\\Fonts\\msgothic.ttc',
		'C:\\Windows\\Fonts\\YuGothR.ttc',
	}
end

local function try_add(path, size, ranges)
	local fonts = io_fonts()
	local cfg_merge = { MergeMode = true, PixelSnapH = true }
	local attempts = {}
	if fonts then
		attempts[#attempts + 1] = function()
			return fonts:AddFontFromFileTTF(path, size, cfg_merge, ranges)
		end
		attempts[#attempts + 1] = function()
			return fonts:AddFontFromFileTTF(path, size, nil, ranges)
		end
		attempts[#attempts + 1] = function()
			return fonts.AddFontFromFileTTF(fonts, path, size, cfg_merge, ranges)
		end
	end
	attempts[#attempts + 1] = function()
		return imgui.AddFontFromFileTTF(path, size, cfg_merge, ranges)
	end
	attempts[#attempts + 1] = function()
		return imgui.AddFontFromFileTTF(path, size, nil, ranges)
	end
	attempts[#attempts + 1] = function()
		return imgui.AddFontFromFileTTF(path, size, cfg_merge, RANGE_TABLE)
	end
	attempts[#attempts + 1] = function()
		return imgui.AddFontFromFileTTF(path, size, nil, RANGE_TABLE)
	end

	for _, fn in ipairs(attempts) do
		local ok, font = pcall(fn)
		if ok and font then
			return font
		end
	end
	return nil
end

function M.bake()
	if current_has_cjk() then
		M.verified = true
		M.usable   = false
		M.merged   = true
		M.font     = nil
		print('FancyChat: ImGui font already has Japanese glyphs')
		return true
	end
	if M.font or M.merged then return true end

	local size = 18
	pcall(function()
		local s = imgui.GetFontSize()
		if type(s) == 'number' and s >= 12 then size = s end
	end)
	M.size = size

	local ranges = jp_ranges()
	for _, path in ipairs(font_candidates()) do
		if file_exists(path) then
			local font = try_add(path, size, ranges)
			if font then
				M.font = font
				print(string.format('FancyChat: added ImGui font %s', path))
				return true
			end
		end
	end

	print('FancyChat: could not add a CJK ImGui font this session')
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
	if not M.font then return false end

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

function M.pop()
	if M.depth <= 0 then return end
	imgui.PopFont()
	M.depth = M.depth - 1
end

return M
