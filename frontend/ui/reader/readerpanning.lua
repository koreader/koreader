ReaderPanning = InputContainer:new{
	key_events = {
		-- these will all generate the same event, just with different arguments
		MoveUp = { {"Up"}, doc = "move visible area up", event = "Panning", args = {0, -1} },
		MoveDown = { {"Down"}, doc = "move visible area down", event = "Panning", args = {0,  1} },
		MoveLeft = { {"Left"}, doc = "move visible area left", event = "Panning", args = {-1, 0} },
		MoveRight = { {"Right"}, doc = "move visible area right", event = "Panning", args = {1,  0} },
	},

	-- defaults
	panning_steps = {
		normal = 50,
		alt = 25,
		shift = 10,
		altshift = 5
	},
}

function ReaderPanning:onSetDimensions(dimensions)
	self.dimen = dimensions
end

function ReaderPanning:onPanning(args, key)
	local dx, dy = unpack(args)
	DEBUG("key =", key)
	-- for now, bounds checking/calculation is done in the view
	self.view:PanningUpdate(
		dx * self.panning_steps.normal * self.dimen.w / 100,
		dy * self.panning_steps.normal * self.dimen.h / 100)
	return true
end
