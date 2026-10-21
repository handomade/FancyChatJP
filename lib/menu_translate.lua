-- lib/menu_translate.lua
-- CatsEye custom NPC menus arrive as incoming chat 0x017 from a
-- speaker named _CUSTOM_MENU.  The body is concatenated quoted
-- strings: "Title:""Option""Option".  Rewriting that packet is what
-- the client then draws.  Already-Japanese text is left alone.

require('common')
local ffi       = require('ffi')
local imgui     = require('imgui')
local state     = require('lib.state')
local translate = require('lib.translate')
local encoding  = require('gdifonts.encoding')

if not pcall(function() return ffi.C.VirtualQuery end) then
	ffi.cdef[[
		typedef struct {
			unsigned int BaseAddress;
			unsigned int AllocationBase;
			unsigned int AllocationProtect;
			unsigned int RegionSize;
			unsigned int State;
			unsigned int Protect;
			unsigned int Type;
		} MEM_BASIC_INFO32;
		unsigned int VirtualQuery(const void* addr, MEM_BASIC_INFO32* info, unsigned int len);
	]]
end

local allSettings = state.allSettings
local uiw         = state.uiw

local M = {}

local SKIP = {
	'magic', 'ability', 'inventor', 'loot', 'mount', 'emote', 'job',
	'bank', 'trade', 'equip', 'comment', 'comyn', 'storage',
	'mog', 'auc', 'map', 'inline', 'playermo', 'abimenu', 'abiselec',
	'guild', 'delivery', 'handover', 'tskill', 'sort', 'fep', 'menuwind',
	'mcr', 'money', 'ws_', 'magselec', 'chscjob', 'myroom', 'roomlist',
	'arealist', 'maplist', 'merityn', 'chatctrl',
	'logwindo', 'fulllog',
}

local last_dump = ''
local last_dump_t = 0
local last_packet = 'none'
local last_probe = 'found=none'
local probed = {}

local function enabled()
	return allSettings
		and allSettings.TranslateMenu
		and allSettings.TranslateMenu[1] == true
end

local function is_system_menu(name)
	local n = (name or ''):lower()
	if n == '' then return false end
	for i = 1, #SKIP do
		if n:find(SKIP[i], 1, true) then return true end
	end
	return false
end

local function addon_dir()
	local src = debug.getinfo(1, 'S').source or ''
	if src:sub(1, 1) == '@' then src = src:sub(2) end
	return src:match('^(.*)[\\/]lib[\\/]') or '.'
end

local function dump_status(line)
	local now = os.clock()
	if line == last_dump and (now - last_dump_t) < 1 then return end
	last_dump = line
	last_dump_t = now
	local f = io.open(addon_dir() .. '\\menu_scan.txt', 'w')
	if not f then return end
	f:write(line)
	f:close()
end

local function hex_dump(s, maxn)
	maxn = maxn or 256
	local n = #s
	if n > maxn then n = maxn end
	local hex = {}
	local vis = {}
	for i = 1, n do
		local b = s:byte(i)
		hex[#hex + 1] = string.format('%02X', b)
		if b == 7 then
			vis[#vis + 1] = '#'
		elseif b == 10 then
			vis[#vis + 1] = '\\n'
		elseif b == 0 then
			vis[#vis + 1] = '|'
		elseif b >= 0x20 and b <= 0x7E then
			vis[#vis + 1] = string.char(b)
		else
			vis[#vis + 1] = '.'
		end
	end
	return table.concat(hex, ' '), table.concat(vis)
end

local function dump_append(kind, line)
	local path = addon_dir() .. '\\npc_in.txt'
	local f = io.open(path, 'a')
	if not f then return end
	f:write(string.format('--- %s %s ---\n%s\n', kind, os.date('%H:%M:%S'), line))
	f:close()
end

-- "Nothing", "Yes", "Fishing Points", "Select Type:".
-- Not locale codes, date formats, or window ids.
local function is_option_line(s)
	if type(s) ~= 'string' then return false end
	if #s < 2 or #s > 48 then return false end
	if s:find('_', 1, true) then return false end
	if s:find('[^%a%s\':%.,%?!%-]') then return false end
	local low = s:lower()
	if low:find('menu', 1, true) or low:find('catseye', 1, true) then return false end
	if low:find('ashita', 1, true) or low:find('dddd', 1, true) then return false end
	if s == 'Yes' or s == 'No' or s == 'OK' then return true end
	if s:find(' ', 1, true) or s:find(':', 1, true) then
		return s:find('%u') ~= nil and s:find('%l') ~= nil
	end
	return s:find('^%u%l%l+$') ~= nil
end

local function to_sjis(utf8)
	local ok, sjis = pcall(function()
		return encoding:UTF8_To_ShiftJIS(utf8)
	end)
	if not ok or type(sjis) ~= 'string' or sjis == '' then return nil end
	for i = 1, #sjis do
		if sjis:byte(i) >= 0x80 then return sjis end
	end
	return nil
end

-- Cut to maxn bytes on a Shift-JIS character boundary (no dangling lead).
local function sjis_clip(sjis, maxn)
	if type(sjis) ~= 'string' or maxn < 1 then return nil end
	if #sjis <= maxn then return sjis end
	local last = 0
	local i = 1
	while i <= #sjis do
		local b = sjis:byte(i)
		local wide = (b >= 0x81 and b <= 0x9F) or (b >= 0xE0 and b <= 0xFC)
		local n = wide and 2 or 1
		if i + n - 1 > maxn then break end
		last = i + n - 1
		i = i + n
	end
	if last < 1 then return nil end
	return sjis:sub(1, last)
end

-- Walk a binary string.  A real option list is 2+ option-lines
-- joined by 0x07 (FFXI) or 0x00.
local function lists_in_blob(blob, min_off)
	local out = {}
	if type(blob) ~= 'string' then return out end
	local i = min_off or 1
	local n = #blob
	while i <= n do
		local batch = {}
		local at = i
		while at <= n do
			local b = blob:byte(at)
			if b == 0 or b == 7 then
				at = at + 1
				break
			end
			if b < 0x20 or b > 0x7E then
				at = at + 1
				break
			end
			local j = at
			while j <= n do
				local c = blob:byte(j)
				if c == 0 or c == 7 then break end
				if c < 0x20 or c > 0x7E then
					j = nil
					break
				end
				j = j + 1
			end
			if not j then
				at = at + 1
				break
			end
			local s = blob:sub(at, j - 1)
			if not is_option_line(s) then
				if #batch > 0 then break end
				at = j + 1
				break
			end
			local term = 0
			if j <= n then term = blob:byte(j) or 0 end
			batch[#batch + 1] = { off = at, text = s, term = term }
			at = j + 1
			if term ~= 0 and term ~= 7 then break end
		end
		if #batch >= 2 then
			out[#out + 1] = batch
			i = at
		else
			i = i + 1
		end
	end
	return out
end

local function rewrite_blob(blob, lists)
	local buf = { blob:byte(1, #blob) }
	local wrote = 0
	local names = {}
	for li = 1, #lists do
		local batch = lists[li]
		for i = 1, #batch do
			local slot = batch[i]
			names[#names + 1] = slot.text
			local jp = translate.prepare(slot.text, true)
			if jp then
				local sjis = to_sjis(jp)
				if sjis and #sjis <= #slot.text then
					for k = 1, #sjis do
						buf[slot.off + k - 1] = sjis:byte(k)
					end
					for k = #sjis + 1, #slot.text do
						buf[slot.off + k - 1] = 0x20
					end
					wrote = wrote + 1
				end
			end
		end
	end
	if wrote == 0 then return nil, names, 0 end
	local chars = {}
	for i = 1, #buf do
		chars[i] = string.char(buf[i] or 0)
	end
	return table.concat(chars), names, wrote
end

-- Instant hits for the known custom-menu labels.  Anything else goes
-- through menu_dict.txt, then the translation site.
local BUILTIN = {
	['select type:'] = '\231\168\174\233\161\158\227\130\146\233\129\184\230\138\158:',
	['select type'] = '\231\168\174\233\161\158\227\130\146\233\129\184\230\138\158',
	['nothing'] = '\227\129\170\227\129\151',
	['fishing points'] = '\233\135\163\227\130\138\227\131\157\227\130\164\227\131\179\227\131\136',
	['harvesting points'] = '\229\143\142\231\169\171\227\131\157\227\130\164\227\131\179\227\131\136',
	['excavation points'] = '\231\153\186\230\142\152\227\131\157\227\130\164\227\131\179\227\131\136',
	['logging points'] = '\228\188\144\230\142\161\227\131\157\227\130\164\227\131\179\227\131\136',
	['mining points'] = '\230\142\161\230\142\152\227\131\157\227\130\164\227\131\179\227\131\136',
	['yes'] = '\227\129\175\227\129\132',
	['no'] = '\227\129\132\227\129\132\227\129\136',
	['ok'] = '\230\177\186\229\174\154',
	['cancel'] = '\227\130\173\227\131\163\227\131\179\227\130\187\227\131\171',
	['join the goblin venture guild?'] = '\227\130\180\227\131\150\227\131\170\227\131\179\227\131\153\227\131\179\227\131\129\227\131\163\227\131\188\227\130\174\227\131\171\227\131\137\227\129\171\229\138\160\229\133\165\227\129\151\227\129\190\227\129\153\227\129\139?',
	['right away!'] = '\228\187\138\227\129\153\227\129\144!',
	['not interested'] = '\227\130\132\227\130\129\227\129\166\227\129\138\227\129\143',
	["wizardoll's spell shop"] = '\227\130\166\227\130\163\227\130\182\227\131\188\227\131\137\227\131\188\227\131\171\227\129\174\233\173\148\230\179\149\229\186\151',
	['browse learnable spells'] = '\231\191\146\229\190\151\227\129\167\227\129\141\227\130\139\233\173\148\230\179\149\227\130\146\232\166\139\227\130\139',
	['browse all available spells'] = '\227\129\153\227\129\185\227\129\166\227\129\174\233\173\148\230\179\149\227\130\146\232\166\139\227\130\139',
	['eminence armor'] = '\227\130\168\227\131\159\227\131\141\227\131\179\227\130\185\227\130\162\227\131\188\227\131\158\227\131\188',
	['choose a spell category:'] = '\229\145\170\230\150\135\227\129\174\231\168\174\233\161\158:',
	['choose a spell category'] = '\229\145\170\230\150\135\227\129\174\231\168\174\233\161\158',
	['white magic'] = '\231\153\189\233\173\148\230\179\149',
	['black magic'] = '\233\187\146\233\173\148\230\179\149',
	['blue magic'] = '\233\157\146\233\173\148\230\179\149',
	['summoning magic'] = '\229\143\172\229\150\154\233\173\148\230\179\149',
	['ninjutsu'] = '\229\191\141\232\161\147',
	['songs'] = '\230\173\140\229\148\177',
	['singing'] = '\230\173\140\229\148\177',
	['geomancy'] = '\233\162\168\230\176\180\233\173\148\230\179\149',
	["what'll it be?"] = '\227\129\169\227\129\134\227\129\151\227\129\190\227\129\153\227\129\139?',
	['spend obsidian fragments'] = '\233\187\146\230\155\156\231\159\179\227\129\174\230\172\160\231\137\135\227\130\146\228\189\191\227\129\134',
	['buy hq crystals'] = 'HQ\231\181\144\230\153\182\227\130\146\232\178\183\227\129\134',
	['open daily chest'] = '\230\175\142\230\151\165\227\129\174\231\174\177\227\130\146\233\150\139\227\129\143',
}

local function norm_option(s)
	return (s or ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''):lower()
end

local function has_high(s)
	if type(s) ~= 'string' then return false end
	for i = 1, #s do
		if s:byte(i) >= 0x80 then return true end
	end
	return false
end

-- Trailing "(3000)" / "(Prev)" / "(0):" stay English.
-- LRU, not "keep longest": 白魔法 is 6 bytes and was dropped after shop menus.
local rev_map = {}
local rev_lru = {}
local last_menu_t = 0

local function remember(en, sjis, utf8)
	if type(en) ~= 'string' or en == '' then return end
	local function add(jp)
		if type(jp) ~= 'string' or jp == '' or jp == en then return end
		rev_map[jp] = en
		for i = 1, #rev_lru do
			if rev_lru[i] == jp then
				table.remove(rev_lru, i)
				break
			end
		end
		rev_lru[#rev_lru + 1] = jp
		while #rev_lru > 256 do
			local old = table.remove(rev_lru, 1)
			rev_map[old] = nil
		end
	end
	add(sjis)
	add(utf8)
end

local function rev_keys_by_len()
	local keys = {}
	for jp in pairs(rev_map) do
		keys[#keys + 1] = jp
	end
	table.sort(keys, function(a, b) return #a > #b end)
	return keys
end

local function restore_originals(blob)
	if type(blob) ~= 'string' then return nil, 0 end
	local keys = rev_keys_by_len()
	if #keys == 0 then return nil, 0 end
	local out = blob
	local n = 0
	for i = 1, #keys do
		local jp = keys[i]
		local en = rev_map[jp]
		if en then
			local at = 1
			while true do
				local a = out:find(jp, at, true)
				if not a then break end
				out = out:sub(1, a - 1) .. en .. out:sub(a + #jp)
				n = n + 1
				at = a + #en
			end
		end
	end
	if n == 0 then return nil, 0 end
	if #out == #blob then return out, n end
	if #out < #blob then
		return out .. string.rep('\0', #blob - #out), n
	end
	local r = #out % 4
	if r ~= 0 then
		out = out .. string.rep('\0', 4 - r)
	end
	if #out > 508 then return nil, 0 end
	return string.char(out:byte(1) or 0, math.floor(#out / 2)) .. out:sub(3), n
end

local function split_keep_parens(s)
	if type(s) ~= 'string' or s == '' then return s, '' end
	local keep = ''
	while true do
		local body, tail = s:match('^(.-)(%s*%b()[:：]?)$')
		if not tail then break end
		keep = tail .. keep
		s = body:gsub('%s+$', '')
		if s == '' then
			return '', keep
		end
	end
	return s, keep
end

local user_dict = {}
local user_loaded = 0

local function menu_dict_path()
	return AshitaCore:GetInstallPath()
		.. '\\config\\addons\\' .. addon.name .. '\\translate\\menu_dict.txt'
end

local function ensure_menu_dict()
	local path = menu_dict_path()
	local f = io.open(path, 'rb')
	if f then
		f:close()
		return path
	end
	os.execute('mkdir "' .. AshitaCore:GetInstallPath()
		.. '\\config\\addons\\' .. addon.name .. '\\translate" 2>nul')
	f = io.open(path, 'wb')
	if not f then return path end
	f:write('\239\187\191')
	f:write('# FancyChatJP menu dictionary\n')
	f:write('# UTF-8 tab-separated. Open in Excel/LibreOffice as UTF-8, separator=Tab.\n')
	f:write('# english<TAB>japanese   (one pair per row)\n')
	f:write('# Save as Unicode Text / UTF-8 TSV, then talk to the NPC again.\n')
	local keys = {}
	for k in pairs(BUILTIN) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	for i = 1, #keys do
		f:write(keys[i] .. '\t' .. BUILTIN[keys[i]] .. '\n')
	end
	f:close()
	return path
end

local function load_user_dict()
	local now = os.clock()
	if now - user_loaded < 1 then return end
	user_loaded = now
	local path = ensure_menu_dict()
	local f = io.open(path, 'rb')
	if not f then return end
	local next_dict = {}
	local have = {}
	for line in f:lines() do
		line = line:gsub('^\239\187\191', ''):gsub('\r', '')
		if line:sub(1, 1) ~= '#' and line:find('\t', 1, true) then
			local src, dst = line:match('^(.-)\t(.*)$')
			if src and dst then
				src = src:gsub('\r', '')
				dst = dst:gsub('\r', ''):gsub('^%s+', ''):gsub('%s+$', '')
				if src ~= '' and dst ~= '' then
					local key = norm_option(src)
					next_dict[key] = dst
					have[key] = true
				end
			end
		end
	end
	f:close()
	user_dict = next_dict
	local extra = {}
	for k, v in pairs(BUILTIN) do
		if not have[k] then
			extra[#extra + 1] = k .. '\t' .. v
			user_dict[k] = v
		end
	end
	if #extra > 0 then
		local af = io.open(path, 'ab')
		if af then
			af:write(table.concat(extra, '\n') .. '\n')
			af:close()
		end
	end
end

local function append_user_dict(en, jp)
	if type(en) ~= 'string' or type(jp) ~= 'string' then return end
	local key = norm_option(en)
	if key == '' or jp == '' then return end
	if user_dict[key] == jp then return end
	user_dict[key] = jp
	local path = menu_dict_path()
	local af = io.open(path, 'ab')
	if not af then return end
	af:write(key .. '\t' .. jp:gsub('\t', ' ') .. '\n')
	af:close()
end

-- "AFF +1" / "HQ" — site leaves these English and the menu would wait.
local function looks_like_code(s)
	if type(s) ~= 'string' or s == '' then return false end
	local body = s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
	local letters = body:gsub('[^%a]', '')
	if letters == '' then return true end
	if body:find('%+', 1, true) and #letters <= 4 and letters == letters:upper() then
		return true
	end
	if #letters <= 6 and body:match('^[%u%d][%u%d%s%+%-%./]*$') then
		return true
	end
	return false
end

local function lookup_option(src)
	if type(src) ~= 'string' or src == '' then return nil end
	if has_high(src) then return nil end
	load_user_dict()
	local left, keep = split_keep_parens(src)
	if left == '' then return nil, keep end
	local key = norm_option(left)
	if key == '' then return nil, keep end
	local hit = user_dict[key] or BUILTIN[key]
	if (not hit or hit == '') then
		hit = translate.official_jp(left)
		if hit and has_high(hit) then
			append_user_dict(left, hit)
		end
	end
	if (not hit or hit == '') and translate.is_zone_or_spell(left) then
		return nil, keep
	end
	if (not hit or hit == '') and looks_like_code(left) then
		return nil, keep
	end
	if not hit or hit == '' then
		hit = translate.prepare(left, true)
	end
	if not hit or hit == '' or not has_high(hit) then return nil, keep end
	return hit, keep
end

local function parse_quoted(blob, from)
	local parts = {}
	local i = from
	while i <= #blob do
		local b = blob:byte(i)
		if not b or b == 0 then break end
		if b ~= 0x22 then break end
		local j = blob:find('"', i + 1, true)
		if not j then break end
		parts[#parts + 1] = blob:sub(i + 1, j - 1)
		i = j + 1
	end
	return parts, i
end

local function finish_packet(blob)
	local n = #blob
	local r = n % 4
	if r ~= 0 then
		blob = blob .. string.rep('\0', 4 - r)
		n = #blob
	end
	if n < 8 or n > 508 then return nil end
	return string.char(blob:byte(1) or 0x17, math.floor(n / 2)) .. blob:sub(3)
end

-- One menu option. FFXI string slots are per-line, not English-length.
local LINE_MAX = 50
-- 0x017 chat body the client copies. Growing past the original quoted
-- list (or this cap) clips the tail, so "(Next)" becomes "(".
local MSG_MAX = 140

local function is_nav_option(text)
	local t = (text or ''):gsub('%s+', ''):lower()
	return t == '(next)' or t == '(prev)' or t == '(previous)'
		or t == '(cancel)' or t == '(exit)' or t == '(back)'
end

local function fit_option(sjis, keep)
	keep = keep or ''
	if #keep >= LINE_MAX then
		return keep:sub(1, LINE_MAX)
	end
	local name = sjis_clip(sjis, LINE_MAX - #keep)
	if not name or name == '' then
		return keep
	end
	return name .. keep
end

local function quoted_len(options)
	local n = 0
	for i = 1, #options do
		n = n + 2 + #(options[i] or '')
	end
	return n
end

local function name_of(s)
	local keep = s.keep or ''
	local text = s.text or ''
	if keep ~= '' and #text >= #keep and text:sub(-#keep) == keep then
		return text:sub(1, #text - #keep), keep
	end
	return text, keep
end

local function squeeze_keep(keep)
	if type(keep) ~= 'string' or keep == '' then return keep end
	keep = keep:gsub('%s+', ' ')
	keep = keep:gsub('^%s+%(', '(')
	keep = keep:gsub('%(%s+', '(')
	keep = keep:gsub('%s+%)', ')')
	return keep
end

-- Shorten translated names so the quoted list fits the original English
-- body.  (Prev)/(Next) are restored last and never clipped.
local function fit_message(slots, out, budget)
	budget = budget or MSG_MAX
	if budget > MSG_MAX then budget = MSG_MAX end
	if budget < 8 then budget = MSG_MAX end
	for k = 1, #slots do
		if is_nav_option(slots[k].src or slots[k].text) then
			local src = slots[k].src or slots[k].text
			slots[k].text = src
			slots[k].full = nil
			out[k] = src
		end
	end
	local guard = 0
	while quoted_len(out) + 1 > budget and guard < 80 do
		guard = guard + 1
		local idx, longest = 0, 0
		for k = 1, #slots do
			local s = slots[k]
			if s.full and not is_nav_option(s.src or '') then
				local name = name_of(s)
				if #name > longest then
					longest = #name
					idx = k
				end
			end
		end
		if idx == 0 then break end
		local s = slots[idx]
		local name, keep = name_of(s)
		if longest <= 2 then
			local tight = squeeze_keep(keep)
			if tight ~= keep and #tight < #keep then
				s.keep = tight
				s.text = name .. tight
				out[idx] = s.text
			else
				break
			end
		else
			local clipped = sjis_clip(name, longest - 2)
			if not clipped or #clipped >= longest then break end
			s.text = clipped .. keep
			out[idx] = s.text
		end
	end
	for k = 1, #slots do
		if is_nav_option(slots[k].src or slots[k].text) then
			out[k] = slots[k].src or slots[k].text
			slots[k].text = out[k]
		end
	end
end

local function assemble_menu(prefix, orig_len, options)
	local body = {}
	for k = 1, #options do
		body[k] = '"' .. options[k] .. '"'
	end
	local rebuilt = prefix .. table.concat(body) .. '\0'
	if #rebuilt <= orig_len then
		return rebuilt .. string.rep('\0', orig_len - #rebuilt)
	end
	return finish_packet(rebuilt)
end

local function rewrite_custom_menu(blob)
	if type(blob) ~= 'string' or #blob < 24 then return nil end
	local name = blob:sub(9, 24)
	if not name:find('_CUSTOM_', 1, true) then return nil end
	local mark = blob:find('_CUSTOM_', 1, true)
	if not mark then return nil end
	local nul = blob:find('\0', mark, true)
	if not nul then return nil end
	local i = nul
	while i <= #blob and blob:byte(i) == 0 do
		i = i + 1
	end
	if blob:byte(i) ~= 0x22 then return nil end
	local qstart = i
	local parts, qend = parse_quoted(blob, qstart)
	if #parts < 2 then return nil, parts, 0, 0, 0 end

	local slots = {}
	local wrote = 0
	local pending = 0
	local waiting = 0
	for k = 1, #parts do
		local src = parts[k]
		if is_nav_option(src) then
			slots[k] = { text = src, src = src }
		elseif has_high(src) then
			slots[k] = { text = src }
		else
			local jp, keep = lookup_option(src)
			keep = keep or ''
			local sjis = jp and to_sjis(jp) or nil
			local dirty = sjis and (sjis:find('"', 1, true) or sjis:find('\0', 1, true))
			dirty = dirty or keep:find('"', 1, true) or keep:find('\0', 1, true)
			if sjis and not dirty then
				local shown = fit_option(sjis, keep)
				slots[k] = { text = shown, src = src, jp = jp, keep = keep, full = sjis }
				wrote = wrote + 1
			else
				if jp == nil and src:find('%a') then
					pending = pending + 1
					local left = split_keep_parens(src)
					if translate.waiting(left) then
						waiting = waiting + 1
					end
				end
				slots[k] = { text = src }
			end
		end
	end
	if wrote == 0 then return nil, parts, 0, pending, waiting end
	last_menu_t = os.clock()

	local out = {}
	for k = 1, #slots do
		out[k] = slots[k].text
	end
	fit_message(slots, out, quoted_len(parts))

	for k = 1, #slots do
		local s = slots[k]
		out[k] = s.text
		if s.src and s.text ~= s.src then
			remember(s.src, s.text, (s.jp or '') .. (s.keep or ''))
			if s.full and s.full ~= s.text then
				remember(s.src, s.full .. (s.keep or ''), (s.jp or '') .. (s.keep or ''))
			end
		end
	end

	local prefix = blob:sub(1, qstart - 1)
	local packed = assemble_menu(prefix, #blob, out)
	if not packed then return nil, parts, 0, pending, waiting end
	return packed, parts, wrote, pending, waiting
end

local INTEREST = {
	[0x017] = true, [0x027] = true, [0x032] = true, [0x033] = true,
	[0x034] = true, [0x036] = true, [0x05A] = true, [0x05C] = true,
}

-- Chat modes that carry NPC / system lines (e2j used several of these).
local TEXT_MODES = {
	[9] = true, [10] = true, [13] = true, [121] = true,
	[144] = true, [145] = true, [150] = true, [151] = true,
	[200] = true, [206] = true, [214] = true,
}

function M.on_text(e)
	if not enabled() then return end
	if type(e.message) ~= 'string' then return end
	local raw = e.message
	if not raw:find('_CUSTOM_', 1, true) and not raw:find('""', 1, true) then
		return
	end
	local mode = e.mode
	if type(mode) == 'number' then mode = bit.band(mode, 0xFF) end
	local hex, vis = hex_dump(raw, 400)
	dump_append('text_in', string.format(
		'mode=%s injected=%s blocked=%s len=%d\nvis=%s\nhex=%s',
		tostring(mode), tostring(e.injected), tostring(e.blocked),
		#raw, vis, hex))
end

local function ascii_runs(blob, from)
	local out = {}
	local i = from or 1
	while i <= #blob do
		local b = blob:byte(i)
		if b and b >= 0x20 and b <= 0x7E then
			local j = i
			while j <= #blob do
				local c = blob:byte(j)
				if not c or c < 0x20 or c > 0x7E then break end
				j = j + 1
			end
			if j - i >= 4 then
				out[#out + 1] = blob:sub(i, j - 1)
			end
			i = j + 1
		else
			i = i + 1
		end
	end
	return out
end

local HOLD_SEC = 6
local held = nil
local injecting = false
local out_injecting = false

local function to_bytes(s)
	if type(s) ~= 'string' then return s end
	if s.totable then return s:totable() end
	local t = {}
	for i = 1, #s do
		t[i] = s:byte(i)
	end
	return t
end

local function inject_incoming(id, data)
	local bytes = to_bytes(data)
	local pm = AshitaCore:GetPacketManager()
	if pm and pm.AddIncomingPacket then
		if pcall(function() pm:AddIncomingPacket(id, #bytes, bytes) end) then
			return true
		end
		if pcall(function() pm:AddIncomingPacket(id, bytes) end) then
			return true
		end
	end
	if _G.AddIncomingPacket then
		if pcall(function() _G.AddIncomingPacket(id, bytes) end) then
			return true
		end
	end
	return false
end

-- data_modified cannot grow a packet; later options get cut. Inject instead.
local function deliver_rewritten(e, orig, new)
	if not new then return end
	if #new > #orig then
		e.blocked = true
		injecting = true
		pcall(inject_incoming, e.id, new)
		injecting = false
	else
		e.data_modified = new
	end
end

local function inject_outgoing(id, data)
	local bytes = to_bytes(data)
	local pm = AshitaCore:GetPacketManager()
	if pm and pm.AddOutgoingPacket then
		if pcall(function() pm:AddOutgoingPacket(id, #bytes, bytes) end) then
			return true
		end
		if pcall(function() pm:AddOutgoingPacket(id, bytes) end) then
			return true
		end
	end
	if _G.AddOutgoingPacket then
		if pcall(function() _G.AddOutgoingPacket(id, bytes) end) then
			return true
		end
	end
	return false
end

local function to_utf8(sjis)
	local ok, u = pcall(function()
		return encoding:ShiftJIS_To_UTF8(sjis)
	end)
	if ok and type(u) == 'string' and u ~= '' then return u end
	return nil
end

local function dict_reverse(inner)
	local utf = to_utf8(inner) or inner
	local function scan(dict)
		if type(dict) ~= 'table' then return nil end
		for en, jp in pairs(dict) do
			if jp == inner or jp == utf then
				for _, seen in pairs(rev_map) do
					if type(seen) == 'string' and seen:lower() == en:lower() then
						return seen
					end
				end
				if en == en:lower() then
					en = en:gsub('(%a)([%a\']*)', function(a, rest)
						return a:upper() .. rest
					end)
				end
				return en
			end
		end
		return nil
	end
	return scan(user_dict) or scan(BUILTIN)
end

local function inner_to_english(inner)
	if type(inner) ~= 'string' or inner == '' then return inner, false end
	inner = inner:gsub('%s+$', '')
	if not has_high(inner) then return inner, false end
	local last = inner:byte(#inner)
	if last and last >= 0x81 and last <= 0xFC then
		local i = 1
		while i <= #inner do
			local b = inner:byte(i)
			if b >= 0x81 and b <= 0x9F or b >= 0xE0 and b <= 0xFC then
				if i == #inner then
					inner = inner:sub(1, #inner - 1)
					break
				end
				i = i + 2
			else
				i = i + 1
			end
		end
	end
	local hit = rev_map[inner]
	if hit then return hit, true end
	local utf = to_utf8(inner)
	if utf and rev_map[utf] then return rev_map[utf], true end
	if #inner >= 4 then
		local best, blen = nil, #inner
		for jp, en in pairs(rev_map) do
			if #jp > blen and jp:sub(1, #inner) == inner then
				best, blen = en, #jp
			end
		end
		if best then return best, true end
	end
	hit = dict_reverse(inner)
	if hit then return hit, true end
	return inner, false
end

-- 0x00B6 tell to _CUSTOM_MENU: GMTELL(player):(title):(option)
-- Keep framing bytes, put original English back in the parentheses,
-- then inject so the size can grow past the Japanese packet.
local function rebuild_gmtell(blob)
	if type(blob) ~= 'string' or #blob < 24 then return nil, 0 end
	local name = blob:sub(5, 20)
	if not name:find('_CUSTOM_MENU', 1, true) then return nil, 0 end
	local hdr = blob:sub(1, 20)
	local msg = blob:sub(21)
	if not msg:find('GMTELL(', 1, true) then return nil, 0 end
	local name_end = msg:find('):', 1, true)
	if not name_end then return nil, 0 end
	local t0 = msg:find('(', name_end + 2, true)
	if not t0 then return nil, 0 end
	local t1 = msg:find('):', t0, true)
	if not t1 then return nil, 0 end
	local o0 = msg:find('(', t1 + 2, true)
	if not o0 then return nil, 0 end
	local z = msg:find('\0', o0, true) or (#msg + 1)
	local o1 = o0
	for i = o0, z - 1 do
		if msg:byte(i) == 0x29 then o1 = i end
	end
	if o1 <= o0 then return nil, 0 end
	local title = msg:sub(t0 + 1, t1 - 1)
	local opt = msg:sub(o0 + 1, o1 - 1)
	local en_t, ok_t = inner_to_english(title)
	local en_o, ok_o = inner_to_english(opt)
	if not ok_t and not ok_o then return nil, 0 end
	if not ok_t then en_t = title end
	if not ok_o then en_o = opt end
	local newmsg = msg:sub(1, t0) .. en_t .. msg:sub(t1, o0) .. en_o .. msg:sub(o1)
	newmsg = newmsg:gsub('%z+$', '') .. '\0'
	local new = hdr .. newmsg
	local r = #new % 4
	if r ~= 0 then new = new .. string.rep('\0', 4 - r) end
	if #new > 508 then return nil, 0 end
	return string.char(new:byte(1) or 0xB6, math.floor(#new / 2)) .. new:sub(3), (ok_t and 1 or 0) + (ok_o and 1 or 0)
end

local function flush_held(reason)
	if not held then return false end
	local h = held
	held = nil
	local new, names, wrote, pending = rewrite_custom_menu(h.data)
	local pkt = new or h.data
	injecting = true
	local pok, iok = pcall(inject_incoming, h.id, pkt)
	injecting = false
	local ok = pok and iok and true or false
	last_packet = string.format(
		'flush %s wrote=%d pending=%d ok=%s lines=%s',
		reason, wrote or 0, pending or 0, tostring(ok),
		names and table.concat(names, ' | ') or '')
	dump_status(last_packet .. '\n')
	dump_append('flush', last_packet .. ' pcall=' .. tostring(pok) .. ' ret=' .. tostring(iok))
	return ok
end

function M.poll_held()
	if not held then return end
	if not enabled() then
		flush_held('off')
		return
	end
	local new, names, wrote, pending, waiting = rewrite_custom_menu(held.data)
	waiting = waiting or 0
	held.waiting = waiting
	held.wrote = wrote or 0
	if waiting == 0 then
		flush_held('ready')
		return
	end
	local elapsed = os.clock() - held.t0
	if elapsed >= HOLD_SEC then
		flush_held('timeout')
		return
	end
	last_packet = string.format(
		'holding %.1fs waiting=%d wrote=%d lines=%s',
		elapsed, waiting, wrote or 0,
		names and table.concat(names, ' | ') or '')
	dump_status(last_packet .. '\n')
end

-- メニュー翻訳中  あと  秒  件
local TXT_MENU = '\227\131\161\227\131\139\227\131\165\227\131\188\231\191\187\232\168\179\228\184\173'
local TXT_LEFT = '\227\129\130\227\129\168'
local TXT_SEC  = '\231\167\146'
local TXT_CNT  = '\228\187\182'

function M.draw_status()
	if not held then return end
	local elapsed = os.clock() - held.t0
	local left = HOLD_SEC - elapsed
	if left < 0 then left = 0 end
	local waiting = held.waiting or 0
	local ok, dsize = pcall(function()
		return imgui.GetIO().DisplaySize
	end)
	if not ok or not dsize then return end
	local x = (dsize.x or 0) * 0.5 - 110
	local y = (dsize.y or 0) * 0.34
	imgui.SetNextWindowPos({x, y}, ImGuiCond_Always)
	pcall(function() imgui.SetNextWindowBgAlpha(0.78) end)
	local flags = bit.bor(
		ImGuiWindowFlags_NoDecoration or 0,
		ImGuiWindowFlags_NoSavedSettings or 0,
		ImGuiWindowFlags_NoFocusOnAppearing or 0,
		ImGuiWindowFlags_NoNav or 0,
		ImGuiWindowFlags_NoMove or 0)
	if ImGuiWindowFlags_AlwaysAutoResize then
		flags = bit.bor(flags, ImGuiWindowFlags_AlwaysAutoResize)
	end
	if imgui.Begin('##fc_menu_tr_status', true, flags) then
		imgui.Text(string.format(
			'%s  %s %.1f%s  (%d%s)',
			TXT_MENU, TXT_LEFT, left, TXT_SEC, waiting, TXT_CNT))
	end
	imgui.End()
end

function M.on_packet(e)
	if not enabled() then return end
	local data = e.data_modified or e.data
	if type(data) ~= 'string' or #data < 8 then return end

	if e.id == 0x017 then
		local new, names, wrote, pending, waiting = rewrite_custom_menu(data)
		if names and #names >= 2 then
			waiting = waiting or 0
			last_packet = string.format(
				'custom wrote=%d pending=%d waiting=%d lines=%s',
				wrote or 0, pending or 0, waiting, table.concat(names, ' | '))
			if injecting or e.injected then
				if new and #new <= #data then e.data_modified = new end
				dump_status(last_packet .. '\n')
				return
			end
			if waiting > 0 then
				if held then flush_held('next') end
				held = {
					id = e.id, data = data, t0 = os.clock(),
					waiting = waiting, wrote = wrote or 0,
				}
				e.blocked = true
				dump_status('holding waiting=' .. waiting .. '\n' .. last_packet .. '\n')
				dump_append('hold', last_packet)
				return
			end
			dump_status(last_packet .. '\n')
			if new then
				deliver_rewritten(e, data, new)
				local _, vis = hex_dump(new, 400)
				dump_append('custom', last_packet .. '\nvis=' .. vis)
			else
				dump_append('custom', last_packet)
			end
			return
		end
		-- Keep a dump only for other _CUSTOM_ chat (shop etc.).
		if data:find('_CUSTOM_', 1, true) then
			local runs = ascii_runs(data, 1)
			local hex, vis = hex_dump(data, 400)
			last_packet = string.format('id=0x%04X ascii=%s', e.id, table.concat(runs, ' | '))
			dump_append('packet', string.format(
				'id=0x%04X size=%d ascii=%s\nvis=%s\nhex=%s',
				e.id, #data, table.concat(runs, ' | '), vis, hex))
			dump_status('packet=' .. last_packet .. '\n')
		end
		return
	end

	if e.id == 0x000E or e.id == 0x000D or e.id == 0x0015 then return end
	if not INTEREST[e.id] then
		return
	end
	local runs = ascii_runs(data, 1)
	local hex, vis = hex_dump(data, 400)
	last_packet = string.format('id=0x%04X ascii=%s', e.id, table.concat(runs, ' | '))
	dump_append('packet', string.format(
		'id=0x%04X size=%d ascii=%s\nvis=%s\nhex=%s',
		e.id, #data, table.concat(runs, ' | '), vis, hex))
	dump_status('packet=' .. last_packet .. '\n')
end

function M.on_packet_out(e)
	if not enabled() then return end
	if e.id == 0x015 then return end
	local data = e.data_modified or e.data
	if type(data) ~= 'string' or #data < 4 then return end
	if out_injecting or e.injected then return end

	if e.id == 0x00B6 then
		local hex0, vis0 = hex_dump(data, 400)
		dump_append('out_b6', string.format(
			'before size=%d\nvis=%s\nhex=%s', #data, vis0, hex0))
		local rebuilt, n = rebuild_gmtell(data)
		if rebuilt and n and n > 0 then
			local hex1, vis1 = hex_dump(rebuilt, 400)
			dump_append('out_b6', string.format(
				'after n=%d size=%d\nvis=%s\nhex=%s', n, #rebuilt, vis1, hex1))
			-- English GMTELL is often longer than Japanese.  If it
			-- still fits, rewrite in place.  If it grew, inject and
			-- turn the original into a harmless 0x015 so a missed
			-- block cannot deliver a real tell to _CUSTOM_MENU
			-- ("recipient is zoning / not logged in").
			if #rebuilt <= #data then
				if #rebuilt < #data then
					rebuilt = rebuilt .. string.rep('\0', #data - #rebuilt)
				end
				e.data_modified = rebuilt
				last_packet = string.format('out b6 modify n=%d size=%d', n, #rebuilt)
				dump_status(last_packet .. '\n')
				dump_append('out_b6', last_packet)
				return
			end
			e.blocked = true
			e.data_modified = string.char(0x15, data:byte(2) or 0) .. data:sub(3)
			out_injecting = true
			local ok, err = pcall(inject_outgoing, 0x00B6, rebuilt)
			out_injecting = false
			last_packet = string.format('out b6 inject n=%d ok=%s', n, tostring(ok and err ~= false))
			dump_status(last_packet .. '\n')
			dump_append('out_b6', last_packet .. ' pcall=' .. tostring(ok) .. ' ret=' .. tostring(err))
			return
		end
	end

	local new, n = restore_originals(data)
	if n and n > 0 and new then
		e.data_modified = new
		last_packet = string.format('out restore id=0x%04X n=%d', e.id, n)
		dump_status(last_packet .. '\n')
		local _, vis = hex_dump(new, 300)
		dump_append('out_restore', last_packet .. '\nvis=' .. vis)
		return
	end

	if os.clock() - last_menu_t > 20 then return end
	if e.id ~= 0x05B and e.id ~= 0x01A and e.id ~= 0x05C
		and not data:find('_CUSTOM_', 1, true) then
		return
	end
	local hex, vis = hex_dump(data, 300)
	dump_append('out', string.format(
		'id=0x%04X size=%d\nvis=%s\nhex=%s',
		e.id, #data, vis, hex))
end

function M.on_text_out(e)
	if not enabled() then return end
	local raw = e.message_modified or e.message
	if type(raw) ~= 'string' or raw == '' then return end
	local new, n = restore_originals(raw)
	if n and n > 0 and new then
		e.message_modified = new
		dump_append('text_out_restore', string.format('n=%d vis=%s', n, new:sub(1, 120)))
	end
end

local function read_u8(addr)
	local ok, b = pcall(ashita.memory.read_uint8, addr)
	if not ok or type(b) ~= 'number' then return nil end
	return b % 256
end

local function read_u32(addr)
	local ok, n = pcall(ashita.memory.read_uint32, addr)
	if not ok or type(n) ~= 'number' then return nil end
	if n < 0 then n = n + 4294967296 end
	return n
end

local function is_ptr(n)
	return type(n) == 'number' and n >= 0x10000 and n < 0x80000000
end

-- Only the menu object's own bytes.  Do not follow pointers:
-- that walks into locale tables (Slovak, dddd, window ids).
local function region_blob(addr, size)
	local bytes = {}
	for i = 0, size - 1 do
		local b = read_u8(addr + i)
		if b == nil then break end
		bytes[#bytes + 1] = string.char(b)
	end
	return table.concat(bytes)
end

local function find_in_module(mod, text)
	local hex = {}
	for i = 1, #text do
		hex[#hex + 1] = string.format('%02X', text:byte(i))
	end
	local ok, addr = pcall(ashita.memory.find, mod, 0, table.concat(hex), 0, 0)
	if not ok or type(addr) ~= 'number' or addr == 0 then return nil end
	return addr
end

local function dump_around(addr)
	local bytes = {}
	local chars = {}
	for i = -16, 96 do
		local b = read_u8(addr + i)
		if b == nil then break end
		bytes[#bytes + 1] = string.format('%02X', b)
		if b >= 0x20 and b <= 0x7E then
			chars[#chars + 1] = string.char(b)
		elseif b == 0 then
			chars[#chars + 1] = '|'
		elseif b == 7 then
			chars[#chars + 1] = '#'
		else
			chars[#chars + 1] = '.'
		end
	end
	return table.concat(bytes, ' ') .. '\ntext=' .. table.concat(chars)
end

local function phrases_in_blob(blob)
	local names = {}
	local i = 1
	while i <= #blob do
		local b = blob:byte(i)
		if b and b >= 0x20 and b <= 0x7E then
			local j = i
			while j <= #blob do
				local c = blob:byte(j)
				if not c or c < 0x20 or c > 0x7E then break end
				j = j + 1
			end
			local s = blob:sub(i, j - 1)
			if is_option_line(s) and (s:find(' ', 1, true) or s:find(':', 1, true)) then
				names[#names + 1] = s
			end
			i = j + 1
		else
			i = i + 1
		end
	end
	return names
end

local MEM_COMMIT = 0x1000
local PAGE_GUARD = 0x100
local PAGE_NOACCESS = 0x01

local function readable_protect(p)
	if bit.band(p, PAGE_GUARD) ~= 0 then return false end
	if bit.band(p, PAGE_NOACCESS) ~= 0 then return false end
	return bit.band(p, 0xEE) ~= 0
end

local function search_region(base, size, needle)
	local chunk = 65536
	local overlap = #needle - 1
	if overlap < 0 then overlap = 0 end
	local prev = ''
	local off = 0
	while off < size do
		local n = size - off
		if n > chunk then n = chunk end
		local ok, s = pcall(function()
			local buf = ffi.new('char[?]', n)
			ffi.copy(buf, ffi.cast('void*', base + off), n)
			return ffi.string(buf, n)
		end)
		if ok and type(s) == 'string' then
			local hay = prev .. s
			local i = hay:find(needle, 1, true)
			if i then
				return base + off - #prev + i - 1
			end
			if overlap > 0 then
				prev = s:sub(#s - overlap + 1)
			else
				prev = ''
			end
		else
			prev = ''
		end
		off = off + n
	end
	return nil
end

local function process_find(needle)
	local info = ffi.new('MEM_BASIC_INFO32')
	local addr = 0x10000
	local scanned = 0
	while addr < 0x7FFF0000 and scanned < 192 * 1024 * 1024 do
		local got = ffi.C.VirtualQuery(ffi.cast('void*', addr), info, ffi.sizeof(info))
		if got == 0 then break end
		local size = tonumber(info.RegionSize)
		if size < 1 then size = 0x1000 end
		if tonumber(info.State) == MEM_COMMIT and readable_protect(tonumber(info.Protect)) and size <= 16 * 1024 * 1024 then
			local hit = search_region(tonumber(info.BaseAddress), size, needle)
			if hit then return hit end
			scanned = scanned + size
		end
		local next_addr = tonumber(info.BaseAddress) + size
		if next_addr <= addr then break end
		addr = next_addr
	end
	return nil
end

local function tick_inner(menu_name, in_event)
	if not enabled() then return end
	local name = menu_name or ''
	if name == '' then name = '(no name)' end
	if is_system_menu(menu_name) then
		dump_status('name=' .. name .. '\nsystem=yes\npacket=' .. last_packet .. '\n')
		return
	end

	local menu = read_u32(uiw.MenuPtr)
	local mem_lines = 'none'
	if is_ptr(menu) then
		local names = phrases_in_blob(region_blob(menu, 0x800))
		local header = read_u32(menu + 4)
		if is_ptr(header) then
			local extra = phrases_in_blob(region_blob(header, 0x400))
			for i = 1, #extra do names[#names + 1] = extra[i] end
		end
		if #names > 0 then
			mem_lines = table.concat(names, ' | ')
		end
	end

	if not probed[name] then
		probed[name] = true
		last_probe = 'probe=off'
	end

	dump_status(
		'name=' .. name
		.. '\nevent=' .. tostring(in_event)
		.. '\nmem=' .. mem_lines
		.. '\npacket=' .. last_packet
		.. '\n' .. last_probe .. '\n')
end

function M.tick(menu_name, in_event)
	local ok, err = pcall(tick_inner, menu_name, in_event)
	if not ok then
		dump_status('error=' .. tostring(err) .. '\n')
	end
end

if translate.set_silent_sink then
	translate.set_silent_sink(append_user_dict)
end

return M
