-- lib/input.lua — xinput_button / key_state / mouse callbacks.

require('common')
local ffi   = require('ffi')
local utils = require('utils')
local state = require('lib.state')

local fcw            = state.fcw
local tab            = state.tab
local gamepadButtons = state.gamepadButtons
local allSettings    = state.allSettings
local set            = state.set

local M = {}

function M.register()

	-- XInput digital press is 1; DirectInput (DualShock etc.) is 128
	-- (some drivers use 255).  Analog axes fire the same events with
	-- other values and must not be treated as button clicks.
	local function pad_down(api, state)
		if api == 'dinput' then return state == 128 or state == 255 end
		return state == 1
	end

	-- DirectInput D-pad is POV hat button 32 only.  State is hundredths
	-- of a degree: 0 up, 9000 right, 18000 down, 27000 left.  Centered
	-- is -1.  Other high indexes (L2 = 54, analog axes, extra buttons)
	-- also use values in 0..36000 and must NOT be treated as the hat.
	local DINPUT_HAT_BUTTON = 32
	local function dinput_hat_dir(api, button, state)
		if api ~= 'dinput' or button ~= DINPUT_HAT_BUTTON then return nil end
		if type(state) ~= 'number' then return nil end
		if state < 0 or state > 36000 then return nil end
		-- Digital press values; a real POV never reports these.
		if state == 128 or state == 255 then return nil end
		local nearest = math.floor((state + 2250) / 4500) * 4500
		if nearest >= 36000 then nearest = 0 end
		if math.abs(state - nearest) > 500 then return nil end
		if nearest == 0 or nearest == 31500 then return 'up' end
		if nearest == 4500 or nearest == 9000 or nearest == 13500 then return 'right' end
		if nearest == 18000 then return 'down' end
		return 'left'
	end

	local function hat_binding(dir)
		if not dir then return nil end
		return 'hat_' .. dir
	end

	local function hat_dir_of(binding)
		if type(binding) ~= 'string' then return nil end
		return binding:match('^hat_(.+)$')
	end

	-- True when this event is a press of the stored binding (digital
	-- button index, or 'hat_left' / 'hat_right' / 'hat_up' / 'hat_down').
	local function binding_down(binding, api, e, hat)
		local dir = hat_dir_of(binding)
		if dir then return hat == dir end
		return e.button == binding and pad_down(api, e.state)
	end

	local function binding_release(binding, api, e, hat)
		local dir = hat_dir_of(binding)
		if dir then
			-- Only the POV centered event (button 32, state -1) is a hat
			-- release.  L2 / extra buttons are also index >= 32.
			return e.button == DINPUT_HAT_BUTTON and hat == nil
		end
		return e.button == binding and not pad_down(api, e.state)
	end

	-- Value written into GamepadBindings while the Settings tab is
	-- listening.  Hats become 'hat_left' etc. because all four
	-- directions share DirectInput button 32.
	local function capture_binding(api, e, hat)
		if hat then return hat_binding(hat) end
		if api == 'xinput' then
			if e.state ~= 1 then return nil end
			if e.button == 18 or e.button == 19 or e.button == 20 or e.button == 21 then return nil end
			if allSettings.XboxController[1]
			   and not utils.findIndexOfValue(utils.gamepadButtonList, e.button) then
				return nil
			end
			return e.button
		end
		-- Button 32 with a POV angle is already handled as hat_*.
		-- L2 and other high-index digital buttons (54, ...) bind as
		-- their raw index, same as buttons 0-31.
		if type(e.button) ~= 'number' then return nil end
		if e.button == DINPUT_HAT_BUTTON then return nil end
		if e.state == 1 or e.state == 128 or e.state == 255 then return e.button end
		return nil
	end

	local function on_pad(e, api)
		if api == 'xinput' then
			gamepadButtons.lastXinput = os.clock()
		elseif (gamepadButtons.lastXinput or 0) > 0
			and os.clock() - gamepadButtons.lastXinput < 0.05 then
			-- Same physical pad is often hooked as both APIs.  Prefer
			-- XInput when both fire so actions do not double-trigger.
			return
		end

		-- Remember the last event so the Gamepad settings tab can show
		-- whether Ashita is seeing this pad at all (XInput vs DirectInput).
		gamepadButtons.lastApi    = api
		gamepadButtons.lastButton = e.button
		gamepadButtons.lastState  = e.state
		gamepadButtons.lastClock  = os.clock()

		local hat = dinput_hat_dir(api, e.button, e.state)
		gamepadButtons.lastHatDir = hat

		-- Listen-for-rebind path.  Activated from the Settings -> Gamepad
		-- tab; captures the very next digital press or POV direction and
		-- writes it into GamepadBindings, then exits listen mode.  Runs
		-- BEFORE the analog filter and the GamepadNav gate so DInput hats
		-- (state 9000 / 27000) and non-128 button values can still be bound.
		if gamepadButtons.listenKey ~= nil then
			e.blocked = true             -- swallow all gamepad input while listening
			local btn = capture_binding(api, e, hat)
			if btn == nil then return end
			gamepadButtons.lastBindApi = api
			local target_key = gamepadButtons.listenKey
			local old_id     = allSettings.GamepadBindings[target_key]
			-- If the captured button is already bound to some OTHER
			-- action, swap them - no orphan slots, no need to manually
			-- un-bind first.
			for k, v in pairs(allSettings.GamepadBindings) do
				if k ~= target_key and v == btn then
					allSettings.GamepadBindings[k] = old_id
					break
				end
			end
			allSettings.GamepadBindings[target_key] = btn
			SaveSettings()
			gamepadButtons.listenKey = nil
			return
		end

		-- DirectInput analog axes send values other than 0 / 128.
		-- POV hats also do, but those are decoded above and must pass.
		if api == 'dinput' and e.state ~= 0 and e.state ~= 128 and e.state ~= 255 and hat == nil then
			return
		end

		if not allSettings.GamepadNav[1] then return end

		gamepadButtons.buttonsCDready = os.clock() - gamepadButtons.buttonsCD > 0.15
		gamepadButtons.analogCDready  = os.clock() - gamepadButtons.analogCD  > 0.02

		if gamepadButtons.pressedEnter and gamepadButtons.buttonsCDready then
			gamepadButtons.pressedEnter = false
			AshitaCore:GetChatManager():QueueCommand(1, '/sendkey enter up')
		end

		-- Snapshot bindings once per event so each `e.button == X` test
		-- uses a stable value (and one fewer table lookup per branch).
		local GB = allSettings.GamepadBindings
		-- D-pad: XInput uses digital buttons 0-3; DirectInput uses the
		-- POV hat decoded above.  Unbound hats still map left/right/up/down
		-- onto presetPrev / presetNext / historyPrev / historyNext.  A
		-- stored 'hat_*' binding is also honoured for every action.
		local press_left  = (hat == 'left')  or binding_down(GB.presetPrev,  api, e, hat)
		local press_right = (hat == 'right') or binding_down(GB.presetNext,  api, e, hat)
		local press_up    = (hat == 'up')    or binding_down(GB.historyPrev, api, e, hat)
		local press_down  = (hat == 'down')  or binding_down(GB.historyNext, api, e, hat)

		-- Modifier button (default LB) hold enables gamepad navigation
		-- mode.  All other bindings only fire while the modifier is held.
		if binding_down(GB.modifier, api, e, hat) then
			ResetAutoHideTimer()
			gamepadButtons.enabled = true
			e.blocked = true
			return
		end
		if binding_release(GB.modifier, api, e, hat) then
			gamepadButtons.enabled = false
			return
		end

		if not gamepadButtons.enabled then return end

		-- Block all other gamepad input while navigation is active,
		-- except button-up events for the analog scroll buttons
		-- (which we still need to read so scrollN reverts to 0).
		if api ~= 'xinput' or (not (e.button == 18 and e.state == 0)
			and not (e.button == 19 and e.state == 0)
			and not (e.button == 20 and e.state == 0)
			and not (e.button == 21 and e.state == 0)) then
			e.blocked = true
		end

		-- Cycle primary chat's tab.
		if binding_down(GB.cyclePrimaryTab, api, e, hat) and not fcw[1].BufferBusy and gamepadButtons.buttonsCDready then
			local tab_id = utils.FindInTable(tab.Tabs, allSettings.SelectedTab)
			if tab_id then
				if tab_id == #tab.Tabs then
					tab.NextTab = tab.Tabs[1]
				else
					tab.NextTab = tab.Tabs[tab_id + 1]
				end
			end
			gamepadButtons.buttonsCD = os.clock()
			return
		end

		-- Cycle secondary chat's tab.
		if allSettings.SecondChat[1] and binding_down(GB.cycleSecondaryTab, api, e, hat) and not fcw[1].BufferBusy and gamepadButtons.buttonsCDready then
			local tab_id = utils.FindInTable(tab.Tabs, allSettings.SelectedTab2)
			if tab_id then
				if tab_id == #tab.Tabs then
					tab.NextTab2 = tab.Tabs[1]
				else
					tab.NextTab2 = tab.Tabs[tab_id + 1]
				end
			end
			gamepadButtons.buttonsCD = os.clock()
			return
		end

		-- Buttons 19 / 21: analog stick scroll for primary / secondary.
		-- (Not user-remappable - these are stick axes, not digital buttons.)
		if api == 'xinput' then
			if e.button == 19 then
				gamepadButtons.scroll1 = (e.state ~= 0) and (e.state / math.abs(e.state)) or 0
			end
			if e.button == 21 then
				gamepadButtons.scroll2 = (e.state ~= 0) and (e.state / math.abs(e.state)) or 0
			end
		end

		if gamepadButtons.scroll1 ~= 0 and gamepadButtons.analogCDready then
			fcw[1].ScrollDelta = gamepadButtons.scroll1
			fcw[3].ScrollDelta = gamepadButtons.scroll1
			gamepadButtons.analogCD = os.clock()
			return
		end
		if gamepadButtons.scroll2 ~= 0 and gamepadButtons.analogCDready then
			fcw[2].ScrollDelta = gamepadButtons.scroll2
			gamepadButtons.analogCD = os.clock()
			return
		end

		-- Snap-to-bottom on every visible chat.
		if binding_down(GB.snapToBottom, api, e, hat) then
			if fcw[1].ScrolledBack > 0 then ResetScrolling(1) end
			if fcw[2].ScrolledBack > 0 then ResetScrolling(2) end
			if fcw[3].ScrolledBack > 0 then ResetScrolling(3, fcw[3].ChatLines) end
			return
		end

		-- Toggle BigMode.
		if binding_down(GB.toggleBigMode, api, e, hat) and gamepadButtons.buttonsCDready then
			fcw[3].BigMode = not fcw[3].BigMode
			gamepadButtons.buttonsCD = os.clock()
			return
		end

		-- Open the FFXI chat input box.
		if binding_down(GB.openChatInput, api, e, hat)
			and AshitaCore:GetChatManager():IsInputOpen() == 0x00
			and gamepadButtons.buttonsCDready then
			AshitaCore:GetChatManager():QueueCommand(-1, '/sendkey space down')
			AshitaCore:GetChatManager():QueueCommand(-1, '/sendkey space up')
			gamepadButtons.buttonsCD = os.clock()
			return
		end

		-- Submit current input as a command.
		if binding_down(GB.submitInput, api, e, hat)
			and AshitaCore:GetChatManager():IsInputOpen() == 0x11
			and gamepadButtons.buttonsCDready then
			AshitaCore:GetChatManager():QueueCommand(-1, '/sendkey enter down')
			local cmd = AshitaCore:GetChatManager():GetInputTextRaw()
			if #cmd > 0 and not cmd:find('^%s*$') then
				-- Push the submitted command to typed-history slot [1].
				-- (Replaces the old updateCommandList() call from the
				-- now-removed debug window.)  Prepend so the most
				-- recent entry is at index 1, matching the cycling code
				-- which steps idx 0 -> 1 -> 2 ... for "Prev".  Skip if
				-- identical to the current head (debounces the case
				-- where the keyboard path also fires for the same line).
				local hist = fcw[1].LastCommands[1]
				if hist[1] ~= cmd then
					table.insert(hist, 1, cmd)
					while #hist > 30 do hist[#hist] = nil end
				end
			end
			gamepadButtons.pressedEnter = true
			gamepadButtons.buttonsCD = os.clock()
			return
		end

		-- Cycle through user-typed command history.
		if #fcw[1].LastCommands[1] > 0 then
			if press_up
				and AshitaCore:GetChatManager():IsInputOpen() == 0x11
				and gamepadButtons.buttonsCDready then
				local nextCommandIdx = fcw[1].LastCommands[2] + 1
				if nextCommandIdx > #fcw[1].LastCommands[1] then nextCommandIdx = 1 end
				if not fcw[1].LastCommands[1][nextCommandIdx] then
					nextCommandIdx = 1
					fcw[1].LastCommands[2] = 1
				end
				AshitaCore:GetChatManager():SetInputText(fcw[1].LastCommands[1][nextCommandIdx])
				fcw[1].LastCommands[2] = nextCommandIdx
				gamepadButtons.buttonsCD = os.clock()
				return
			end
			if press_down
				and AshitaCore:GetChatManager():IsInputOpen() == 0x11
				and gamepadButtons.buttonsCDready then
				local nextCommandIdx = fcw[1].LastCommands[2] - 1
				if nextCommandIdx < 1 then nextCommandIdx = #fcw[1].LastCommands[1] end
				if not fcw[1].LastCommands[1][nextCommandIdx] then
					nextCommandIdx = 1
					fcw[1].LastCommands[2] = 1
				end
				AshitaCore:GetChatManager():SetInputText(fcw[1].LastCommands[1][nextCommandIdx])
				fcw[1].LastCommands[2] = nextCommandIdx
				gamepadButtons.buttonsCD = os.clock()
				return
			end
		end

		-- BigMode: modifier + left/right switches window 1 / 2
		-- (only when the second chat window is enabled and the FFXI
		-- input box is closed — otherwise left/right keep cycling
		-- preset commands).
		if fcw[3].BigMode and allSettings.SecondChat[1]
			and AshitaCore:GetChatManager():IsInputOpen() == 0x00
			and gamepadButtons.buttonsCDready then
			if press_left then
				set_bigmode_source(1)
				gamepadButtons.buttonsCD = os.clock()
				return
			end
			if press_right then
				set_bigmode_source(2)
				gamepadButtons.buttonsCD = os.clock()
				return
			end
		end

		-- Cycle through preset (`!mog`, `!chef`, ...) commands.
		if press_right
			and AshitaCore:GetChatManager():IsInputOpen() == 0x11
			and gamepadButtons.buttonsCDready then
			local nextCommandIdx = fcw[1].LastCommands[4] + 1
			if nextCommandIdx > #fcw[1].LastCommands[3] then nextCommandIdx = 1 end
			AshitaCore:GetChatManager():SetInputText(fcw[1].LastCommands[3][nextCommandIdx])
			fcw[1].LastCommands[4] = nextCommandIdx
			gamepadButtons.buttonsCD = os.clock()
			return
		end
		if press_left
			and AshitaCore:GetChatManager():IsInputOpen() == 0x11
			and gamepadButtons.buttonsCDready then
			local nextCommandIdx = fcw[1].LastCommands[4] - 1
			if nextCommandIdx < 1 then nextCommandIdx = #fcw[1].LastCommands[3] end
			AshitaCore:GetChatManager():SetInputText(fcw[1].LastCommands[3][nextCommandIdx])
			fcw[1].LastCommands[4] = nextCommandIdx
			gamepadButtons.buttonsCD = os.clock()
			return
		end
	end

	ashita.events.register('xinput_button', 'xinput_button_callback1', function (e)
		on_pad(e, 'xinput')
	end)

	ashita.events.register('dinput_button', 'dinput_button_callback1', function (e)
		on_pad(e, 'dinput')
	end)

	ashita.events.register('key_state', 'key_state_callback1', function (e)
		if gamepadButtons.enabled then return end

		local keyptr = ffi.cast('uint8_t*', e.data_raw)

		-- Escape closes the zone-search popup.  Done in this callback
		-- (rather than only via imgui.GetIO().KeysDown inside the popup
		-- draw block) because the popup can be dismissed even when
		-- it doesn't currently have ImGui keyboard focus — DI scancode
		-- 1 is Escape and is read directly out of the raw key-state
		-- buffer, bypassing ImGui's input routing entirely.
		if set.zoneTip.visible and keyptr[1] ~= 0 then
			set.zoneTip.visible = false
		end

		-- Escape also cancels an in-progress gamepad-binding listen
		-- (Settings -> Gamepad tab).  Rising edge only: a stuck or
		-- noisy DIK_ESCAPE bit would otherwise clear listenKey every
		-- frame and make button capture impossible.
		local esc_down = keyptr[1] ~= 0
		if gamepadButtons.listenKey ~= nil and esc_down and not gamepadButtons.listenEscDown then
			gamepadButtons.listenKey = nil
		end
		gamepadButtons.listenEscDown = esc_down

		-- Pressing Enter while typing in the chat input commits the line
		-- to the per-character command history.  Block runs every frame
		-- Enter is held, so the de-dup (hist[1] ~= cmd) keeps the list
		-- clean of repeated pushes for a single key-down.
		if AshitaCore:GetChatManager():IsInputOpen() == 0x11
			and (keyptr[28] ~= 0 or keyptr[156] ~= 0) then
			local cmd = AshitaCore:GetChatManager():GetInputTextRaw()
			if #cmd > 0 and not cmd:find('^%s*$') then
				local hist = fcw[1].LastCommands[1]
				if hist[1] ~= cmd then
					table.insert(hist, 1, cmd)
					while #hist > 30 do hist[#hist] = nil end
				end
			end
		end

		-- Hide-chat shortcut.
		if allSettings.shortcutHideEnabled[1]
			and keyptr[allSettings.shortcutHide] ~= 0
			and keyptr[allSettings.shortcutHideS] ~= 0
			and not fcw[1].Keydown
			and AshitaCore:GetChatManager():IsInputOpen() == 0x00 then
			fcw[1].HideChat = not fcw[1].HideChat
			ResetAutoHideTimer()
			SetChatOpacity(1, 1)
			if allSettings.SecondChat[1] then SetChatOpacity(1, 2) end
			fcw[1].Keydown = true
		elseif keyptr[allSettings.shortcutHide] == 0 then
			fcw[1].Keydown = false
		end

		-- BigMode shortcut.
		if allSettings.shortcutBigEnabled[1]
			and keyptr[allSettings.shortcutBig] ~= 0
			and keyptr[allSettings.shortcutBigS] ~= 0
			and not fcw[3].Keydown
			and AshitaCore:GetChatManager():IsInputOpen() == 0x00 then
			fcw[3].BigMode = not fcw[3].BigMode
			ResetAutoHideTimer()
			fcw[3].Keydown = true
		elseif keyptr[allSettings.shortcutBig] == 0 then
			fcw[3].Keydown = false
		end

		if fcw[1].BufferBusy then return end

		-- Tab-cycle shortcut for primary chat.
		if allSettings.shortcutTabEnabled[1]
			and keyptr[allSettings.shortcutTab] ~= 0
			and keyptr[allSettings.shortcutTabS] ~= 0
			and not fcw[1].Keydown2
			and AshitaCore:GetChatManager():IsInputOpen() == 0x00 then
			local tab_id = utils.FindInTable(tab.Tabs, allSettings.SelectedTab)
			fcw[1].Keydown2 = true
			if tab_id then
				if tab_id == #tab.Tabs then
					tab.NextTab = tab.Tabs[1]
				else
					tab.NextTab = tab.Tabs[tab_id + 1]
				end
				ResetAutoHideTimer()
			end
		elseif keyptr[allSettings.shortcutTab] == 0 then
			fcw[1].Keydown2 = false
		end

		-- Tab-cycle shortcut for secondary chat.
		if allSettings.SecondChat[1] then
			if allSettings.shortcutTab2Enabled[1]
				and keyptr[allSettings.shortcutTab2] ~= 0
				and keyptr[allSettings.shortcutTab2S] ~= 0
				and not fcw[1].Keydown3
				and AshitaCore:GetChatManager():IsInputOpen() == 0x00 then
				local tab_id = utils.FindInTable(tab.Tabs, allSettings.SelectedTab2)
				fcw[1].Keydown3 = true
				if tab_id then
					if tab_id == #tab.Tabs then
						tab.NextTab2 = tab.Tabs[1]
					else
						tab.NextTab2 = tab.Tabs[tab_id + 1]
					end
					ResetAutoHideTimer()
				end
			elseif keyptr[allSettings.shortcutTab2] == 0 then
				fcw[1].Keydown3 = false
			end
		end
	end)

	ashita.events.register('mouse', 'mouse_callback1', function (e)
		if e.delta ~= 0 then
			fcw[1].ScrollDelta = e.delta
			fcw[2].ScrollDelta = e.delta
			fcw[3].ScrollDelta = e.delta
		end
	end)

end

return M
