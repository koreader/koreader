require "ui/geometry"
require "ui/device"
require "ui/inputevent"
require "ui/widget"
require "ui/screen"
require "settings" -- for DEBUG(), TODO: put DEBUG() somewhere else

-- initialize output module, this must be initialized before Input
Screen:init()
-- initialize the input handling
Input:init()


-- there is only one instance of this
UIManager = {
	-- change this to set refresh type for next refresh
	-- defaults to 1 initially and will be set to 1 after each refresh
	refresh_type = 1,
	-- force to repaint all the widget is stack, will be reset to false
	-- after each ui loop
	repaint_all = false,

	_running = true,
	_window_stack = {},
	_execution_stack = {},
	_dirty = {}
}

-- register & show a widget
function UIManager:show(widget, x, y)
	-- put widget on top of stack
	table.insert(self._window_stack, {x = x or 0, y = y or 0, widget = widget})
	-- and schedule it to be painted
	self:setDirty(widget)
	-- tell the widget that it is shown now
	widget:handleEvent(Event:new("Show"))
end

-- unregister a widget
function UIManager:close(widget)
	local dirty = false
	for i = #self._window_stack, 1, -1 do
		if self._window_stack[i].widget == widget then
			table.remove(self._window_stack, i)
			dirty = true
			break
		end
	end
	if dirty then
		-- schedule remaining widgets to be painted
		for i = 1, #self._window_stack do
			self:setDirty(self._window_stack[i].widget)
		end
	end
end

-- schedule an execution task
function UIManager:schedule(time, action)
	table.insert(self._execution_stack, { time = time, action = action })
end

-- schedule task in a certain amount of seconds (fractions allowed) from now
function UIManager:scheduleIn(seconds, action)
	local when = { util.gettime() }
	local s = math.floor(seconds)
	local usecs = (seconds - s) * 1000000
	when[1] = when[1] + s
	when[2] = when[2] + usecs
	if when[2] > 1000000 then
		when[1] = when[1] + 1
		when[2] = when[2] - 1000000
	end
	self:schedule(when, action)
end

-- register a widget to be repainted
function UIManager:setDirty(widget, refresh_type)
	if not refresh_type then
		refresh_type = "full"
	elseif refresh_type == 0 then
		refresh_type = "full"
	elseif refresh_type == 1 then
		refresh_type = "partial"
	end
	self._dirty[widget] = refresh_type
end

-- signal to quit
function UIManager:quit()
	self._running = false
end

-- transmit an event to registered widgets
function UIManager:sendEvent(event)
	-- top level widget has first access to the event
	local consumed = self._window_stack[#self._window_stack].widget:handleEvent(event)

	-- if the event is not consumed, always-active widgets can access it
	for _, widget in ipairs(self._window_stack) do
		if consumed then
			break
		end
		if widget.widget.is_always_active then
			consumed = widget.widget:handleEvent(event)
		end
	end
end

function UIManager:checkTasks()
	local now = { util.gettime() }

	-- check if we have timed events in our queue and search next one
	local wait_until = nil
	local all_tasks_checked
	repeat
		all_tasks_checked = true
		for i = #self._execution_stack, 1, -1 do
			local task = self._execution_stack[i]
			if not task.time
				or task.time[1] < now[1]
				or task.time[1] == now[1] and task.time[2] < now[2] then
				-- task is pending to be executed right now. do it.
				task.action()
				-- and remove from table
				table.remove(self._execution_stack, i)
				-- start loop again, since new tasks might be on the
				-- queue now
				all_tasks_checked = false
			elseif not wait_until
				or wait_until[1] > task.time[1]
				or wait_until[1] == task.time[1] and wait_until[2] > task.time[2] then
				-- task is to be run in the future _and_ is scheduled
				-- earlier than the tasks we looked at already
				-- so adjust to the currently examined task instead.
				wait_until = task.time
			end
		end
	until all_tasks_checked
	return wait_until
end

-- this is the main loop of the UI controller
-- it is intended to manage input events and delegate
-- them to dialogs
function UIManager:run()
	self._running = true
	while self._running do
		local now = { util.gettime() }
		local wait_until = self:checkTasks()
		
		--DEBUG("---------------------------------------------------")
		--DEBUG("exec stack", self._execution_stack)
		--DEBUG("window stack", self._window_stack)
		--DEBUG("dirty stack", self._dirty)
		--DEBUG("---------------------------------------------------")

		-- stop when we have no window to show
		if #self._window_stack == 0 then
			DEBUG("no dialog left to show, would loop endlessly")
			return nil
		end

		-- repaint dirty widgets
		local dirty = false
		for _, widget in ipairs(self._window_stack) do
			if self.repaint_all or self._dirty[widget.widget] then
				widget.widget:paintTo(Screen.bb, widget.x, widget.y)
				if self._dirty[widget.widget] == "full" then
					self.refresh_type = 0
				end
				-- and remove from list after painting
				self._dirty[widget.widget] = nil
				-- trigger repaint
				dirty = true
			end
		end
		self.repaint_all = false

		if dirty then
			-- refresh FB
			Screen:refresh(self.refresh_type) -- TODO: refresh explicitly only repainted area
			-- reset refresh_type
			self.refresh_type = 1
		end
		
		self:checkTasks()
		
		-- wait for next event
		-- note that we will skip that if in the meantime we have tasks that are ready to run
		local input_event = nil
		if not wait_until then
			-- no pending task, wait endlessly
			input_event = Input:waitEvent()
		elseif wait_until[1] > now[1]
		or wait_until[1] == now[1] and wait_until[2] > now[2] then
			local wait_for = { s = wait_until[1] - now[1], us = wait_until[2] - now[2] }
			if wait_for.us < 0 then
				wait_for.s = wait_for.s - 1
				wait_for.us = 1000000 + wait_for.us
			end
			-- wait until next task is pending
			input_event = Input:waitEvent(wait_for.us, wait_for.s)
		end

		-- delegate input_event to handler
		if input_event then
			--DEBUG("in ui.lua:", input_event)
			if input_event == "IntoSS" then
				Device:intoScreenSaver()
			elseif input_event == "OutOfSS" then
				Device:outofScreenSaver()
			elseif input_event == "Charging" then
				Device:usbPlugIn()
			elseif input_event == "NotCharging" then
				Device:usbPlugOut()
			else
				self:sendEvent(input_event)
			end
		end
	end
end
