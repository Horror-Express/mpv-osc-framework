-- osc framework
-- ver 1.3

-- # variables
-- player status for public access, generated by program
-- changing their values do not interfere the framework
player = {
	now = 0,		-- a copy of local now for public access
	geo = {width = 0, height = 0, aspect = 0},
	idle = true,	-- idle status
	}
-- user options, altering them may change osc behavior
opts = {
	scale = 1,			  -- osc render scale
	fixedHeight = false,	-- true means osc y resolution is fixed 480, all elements scale with player window height
	hideTimeout = 1,		-- seconds untile osc hides, negative means never
	fadeDuration = 0.5,	 -- seconds during fade out, negative means never
	}

-- local variables, users do not touch them
local elements = {}			-- all available elements
local elementsInUse = {}	-- an element added to a layout will be marked here
local layouts = {idle = {}, play = {}}  -- tow layouts: idle, play
local oscLayout = 'idle'	-- selected layout will be rendered
local activeAreas = {	   -- mouse in these rectangle areas avtivate osc and key bindings
	idle = {}, play = {}}   -- example: idle['name'] = {x1=n1, y1=n2, x2=n3, y2=n4, prop=''}
local active = false		-- true if mouse is in activeArea
local osd = mp.create_osd_overlay('ass-events')
local tickTimer = nil	   -- osc timer objects
local tickDelay = 0.03	  -- 33 fps limit
local now = 0			   -- now time, updated by tick()
local mouseScale = 1		-- mouse positon scale
local visible = false	   -- osc visiblility
local visualMode = 'out'	-- visual mode: in, out, always, hide 
local fadeLastTime = 0	  -- fade effect time base
local fadeFactor = 0		-- fade factor as transparency modifier

-- # basic osc functions
-- set osd display
-- text: in ASS format
local function setOsd(text)
	if text == osd.data then return end
	osd.data = text
	osd:update()
end

-- update visual effects, which deal with the fade out effect
local function updateVisual()
	if visualMode == 'in' then	  -- osc is shown
		visible = true
		fadeFactor = 0
		if opts.hideTimeout < 0 then return end
		if now - fadeLastTime >= opts.hideTimeout then
			visualMode = 'out'
			fadeLastTime = now
		end
	elseif visualMode == 'out' then -- fading out
		if opts.fadeDuration < 0 then return end
		local time = now - fadeLastTime
		local factor = time / opts.fadeDuration
		if factor > 1 then factor = 1 end
		fadeFactor = factor
		if time >= opts.fadeDuration then visible = false end
	elseif visualMode == 'always' then
		fadeFactor = 0
		visible = true
	elseif visualMode == 'hide' then
		visible = false
	end
end

function getVisibility()
	if visualMode == 'in' or visualMode == 'out' then
		return 'normal'
	elseif visualMode == 'always' then
		return 'always'
	elseif visualMode == 'hide' then
		return 'hide'
	else return 'unknown' end
end

-- set osc visibility
-- mode: 'normal', 'always', 'hide'
function setVisibility(mode)
	if mode == 'normal' then
		visualMode = 'in'
	elseif mode == 'always' then
		visualMode = 'always'
	elseif mode == 'hide' then
		visualMode = 'hide'
	end
end

-- show osc if it's faded out
function showOsc()
	if visualMode == 'in' or visualMode == 'out' then
		visualMode = 'in'
		fadeLastTime = now
	end
end

-- render a selected layout
local renderLayout = {
	idle = function()
		local text = {}
		for i, e in ipairs(layouts.idle) do
			text[i] = e.tick(e)
		end
		setOsd(table.concat(text, '\n'))
	end,
	play = function()
		local text = {}
		updateVisual()
		if visible then
			for i, e in ipairs(layouts.play) do
				e.setAlpha(e, fadeFactor)	   -- remix fade effect
				text[i] = e.tick(e)
			end 
		end
		setOsd(table.concat(text, '\n'))
	end
	}

-- called by mpv timer periodically
local function tick()
	now = mp.get_time()
	player.now = now
	if active then showOsc() end
	renderLayout[oscLayout]()
end

-- called on player resize
local function oscResize()
	local baseWidth, baseHeight = 720, 480
	local dispWidth, dispHeight, dispAspect = mp.get_osd_size()
	if dispAspect > 0 then	  -- in some cases osd size could be zero, need to check
		if opts.fixedHeight then	-- if true, baseWidth is calculated according to baseHeight
			baseWidth = baseHeight * dispAspect
		else					-- or else, use real window size
			baseWidth, baseHeight = dispWidth, dispHeight 
		end
	end
	local x = baseWidth / opts.scale
	local y = baseHeight / opts.scale
	player.geo = {
		width = x,
		height = y,
		aspect = dispAspect
		}
	-- set osd resolution
	osd.res_x = x
	osd.res_y = y
	-- display positon may not be actual mouse position. need scale
	if dispHeight > 0 then
		mouseScale = y / dispHeight
	else
		mouseScale = 0
	end
end

-- initialize
local function init()
	-- init osd params
	osd.res_x = 0
	osd.res_y = 0
	osd.z = 10
	-- init timer
	tickTimer = mp.add_periodic_timer(tickDelay, tick)
	-- disable internal osc
	mp.commandv('set', 'osc', 'no')
end

-- osc starts here
init()

-- # element management
-- creat a default element as a template
elements['default'] = {
	-- z order
	layer = 0,
	-- geometry, left, right, width, height, alignmet
	geo = {x = 0, y = 0, w = 0, h = 0, an = 7},
	-- global transparency modifier
	trans = 0,
	-- render style, each property can be optional
	style = {
		-- primary, secondary, outline, back colors in BGR format
		color = {'ffffff', 'ffffff', 'ffffff', 'ffffff'},
		-- transparency, 0~255, 255 is invisible
		alpha = {0, 0, 0, 0},
		-- border size, decimal
		border = nil,
		-- blur size, decimal
		blur = nil,
		-- shadow size, decimal
		shadow = nil,
		-- font name, string
		font = nil,
		-- fontsize, decimal
		fontsize = nil,
		-- 0-auto, 1-end wrap, 2-no wrap, 3-auto2
		wrap = nil,
		},
	visible = true,
	-- pack[1] - position codes
	-- pack[2] - alpha codes
	-- pack[3] - other style codes
	-- pack[4] - other contents
	-- pack[>4] also works if you like 
	pack = {'', '', '', ''},
	-- initialize the element
	init = function(self)
			self:setPos()
			self:setStyle()
			self:render()
		end,
	-- set positon codes
	setPos = function(self)
			if not self.geo then return end
			self.pack[1] = string.format('{\\pos(%f,%f)\\an%d}', self.geo.x, self.geo.y, self.geo.an)
		end,
	-- set alpha codes, usually called by oscf
	-- trans: transparency modifier, 0~1, 1 for invisible
	setAlpha = function(self, trans)
			if not self.style then return end
			self.trans = trans
			local alpha = {0, 0, 0, 0}
			if self.style.alpha then
				for i = 1, 4 do
					alpha[i] = 255 - (((1-(self.style.alpha[i]/255)) * (1-trans)) * 255)
				end
			else
				alpha = {trans*255, trans*255, trans*255, trans*255}
			end
			self.pack[2] = string.format('{\\1a&H%x&\\2a&H%x&\\3a&H%x&\\4a&H%x&}',
											alpha[1], alpha[2], alpha[3], alpha[4])
		end,
	-- set style codes, including alpha codes
	setStyle = function(self)
			if not self.style then return end
			self:setAlpha(self.trans)
			local fmt = {'{'}
			if self.style.color then
				table.insert(fmt, 
					string.format('\\1c&H%s&\\2c&H%s&\\3c&H%s&\\4c&H%s&',
						self.style.color[1], self.style.color[2], self.style.color[3], self.style.color[4]))
			end
			if self.style.border then
				table.insert(fmt, string.format('\\bord%.2f', self.style.border)) end
			if self.style.blur then
				table.insert(fmt, string.format('\\blur%.2f', self.style.blur)) end
			if self.style.shadow then
				table.insert(fmt, string.format('\\shad%.2f', self.style.shadow)) end
			if self.style.font then
				table.insert(fmt, string.format('\\fn%s', self.style.font)) end
			if self.style.fontsize then
				table.insert(fmt, string.format('\\fs%d', self.style.fontsize)) end
			if self.style.wrap then
				table.insert(fmt, string.format('\\q%d', self.style.wrap)) end
			table.insert(fmt, '}')
			self.pack[3] = table.concat(fmt)
		end,
	-- update other contents
	render = function(self) end,
	-- called by function tick(), return the pack as a string for further render
	-- it MUST return a string, or the osc will halt
	tick = function(self)
			if self.visible then return table.concat(self.pack)
				else return ''
			end
		end,
--[[responders are functions called by dispatchEvents(), the format is like
	responder['event'] = function(self, arg)
			...
			return true/false
		end
	return true will prevent this event from other responders, useful in overlaped elements that only one is allowed to respond.]]--
		responder = {},
	}

-- create a new element, either from 'default', or from an existing source
-- name: name string of the new element
-- source: OPTIONAL name string of an element as a template
-- return: table of the new element
function newElement(name, source)
	local ne, lookup = {}, {}
	if source == nil then source = 'default' end
	local function clone(e) -- deep clone
		if type(e) ~= 'table' then return e end
		if lookup[e] then return lookup[e] end  --keep reference relations
		local copy = {}
		lookup[e] = copy
		for k, v in pairs(e) do
			copy[k] = clone(v)
		end
		return setmetatable(copy, getmetatable(e))
	end
	ne = clone(elements[source])
	elements[name] = ne
	return ne
end

-- get the table of an element
-- name: name string of the element
function getElement(name)
	return elements[name]
end

-- sort element order
local function lowerFirst (a, b)
	return a.layer < b.layer
end

local function higherFirst (a, b)
	return a.layer > b.layer
end

-- add an element to idle layout
-- name: name string of the element
-- return: element table
function addToIdleLayout(name)
	return addToLayout('idle', name)
end

-- add an element to play layout
-- name: name string of the element
-- return: element table
function addToPlayLayout(name)
	return addToLayout('play', name)
end

-- add an element ot a layout
-- layout: 'idle', 'play', or something you like
-- name: name string
-- return: element table
function addToLayout(layout, name)
	local e = elements[name]
	if e then
		table.insert(layouts[layout], e)
		table.sort(layouts[layout], lowerFirst)
		-- elementsInUse require unique values
		local check = true
		local n = #elementsInUse
		for i = 1, n do
			if e == elementsInUse[i] then
				check = false
				break
			end
		end
		if check then
			elementsInUse[n+1] = e
		end
		table.sort(elementsInUse, higherFirst)
	end
	return e
end

-- # event management
-- dispatch event to elements in current layout
-- event: string of event name
-- arg: OPTIONAL arguments
function dispatchEvent(event, arg)
	for _, v in ipairs(elementsInUse) do
		if v.responder[event] and 
			v.responder[event](v, arg) then
			-- a responder return true can terminate this event
				break end
	end
end

-- property observers to generate events
-- these are minimum events for osc framework
mp.observe_property('osd-dimensions', 'native',
	function(name, val)
		oscResize()
		dispatchEvent('resize')
	end)
mp.observe_property('idle-active', 'bool',
	function(name, val)
		player.idle = val
		if not player.idle then oscLayout = 'play'
			else oscLayout = 'idle'
				end
		dispatchEvent('idle')
	end)
-- set an active area for idle layout
-- name: string of area name
function setIdleActiveArea(name, x1, y1, x2, y2, prop)
	setActiveArea('idle', name, x1, y1, x2, y2, prop)
end
-- set an active area for play layout
-- name: string of area name
function setPlayActiveArea(name, x1, y1, x2, y2, prop)
	setActiveArea('play', name, x1, y1, x2, y2, prop)
end
-- a general function to set active area
-- layout: 'idle', 'play', or else
function setActiveArea(layout, name, x1, y1, x2, y2, prop)
	local area = {x1 = x1, y1 = y1, x2 = x2, y2 = y2, prop = prop}
	activeAreas[layout][name] = area
end

-- get mouse position scaled by display factor
function getMousePos()
	local x, y = mp.get_mouse_pos()
	return x*mouseScale, y*mouseScale
end

-- mouse move event handler
local function eventMove()
	local x, y = getMousePos()
	local check = false
	local areas = activeAreas[oscLayout]
	for _, v in pairs(areas) do
		if v.x1 <= x and x <= v.x2 and v.y1 <= y and y <= v.y2 then
			if v.prop == 'show_hide' then
				showOsc()
				goto next
			else
				-- default
				check = true
				if not active then
					mp.enable_key_bindings('_button_')
					active = true
				end
			end
			dispatchEvent('mouse_move', {x, y})
		end
		::next::
	end
	if not check and active then 
		mp.disable_key_bindings('_button_')
		active = false
		dispatchEvent('mouse_leave')
	end
end
-- mouse leave player window
local function eventLeave()
	if active then
		mp.disable_key_bindings('_button_')
		active = false
	end
	dispatchEvent('mouse_leave')
end
-- mouse button event handler
local function eventButton(event)
	local x, y = getMousePos()
	dispatchEvent(event, {x, y})
end

-- mouse move bindings
mp.set_key_bindings({
		{'mouse_move', eventMove},
		{'mouse_leave', eventLeave},
	}, '_move_', 'force')
mp.enable_key_bindings('_move_', 'allow-vo-dragging+allow-hide-cursor')

--mouse input bindings
mp.set_key_bindings({
		{'mbtn_left', function() eventButton('mbtn_left_up') end, function() eventButton('mbtn_left_down')  end},
		{'mbtn_right', function() eventButton('mbtn_right_up') end, function() eventButton('mbtn_right_down')  end},
		{'mbtn_mid', function() eventButton('mbtn_mid_up') end, function() eventButton('mbtn_mid_down')  end},
		{'wheel_up', function() eventButton('wheel_up') end},
		{'wheel_down', function() eventButton('wheel_down') end},
		{'mbtn_left_dbl', function() eventButton('mbtn_left_dbl') end},
		{'mbtn_right_dbl', function() eventButton('mbtn_right_dbl') end},
		{'mbtn_mid_dbl', function() eventButton('mbtn_mid_dbl') end},
	}, '_button_', 'force')

-- mouse button events control for user scripts
-- enable mouse button events
function enableMouseButtonEvents()
	mp.enable_key_binding('_button_')
end
-- disable mouse button events
function disableMouseButtonEvents()
	mp.mp.disable_key_bindings('_button_')
end
