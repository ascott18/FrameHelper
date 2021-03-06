﻿

local LibOO = LibStub("LibOO-1.0")
local Classes = LibOO:GetNamespace("FrameHelper")


FrameHelper = CreateFrame("Frame")
FrameHelper.C = Classes


local E, M

local function get(value, ...)
	local type = type(value)
	if type == "function" then
		return value(...)
	elseif type == "table" then
		return value[...]
	else
		return value
	end
end


do	-- FrameHelper.safecall
	--[[
		xpcall safecall implementation
	]]
	local xpcall = xpcall

	local function errorhandler(err)
		return geterrorhandler()(err)
	end

	local function CreateDispatcher(argCount)
		local code = [[
			local xpcall, eh = ...
			local method, ARGS
			local function call() return method(ARGS) end
		
			local function dispatch(func, ...)
				method = func
				if not method then return end
				ARGS = ...
				return xpcall(call, eh)
			end
		
			return dispatch
		]]
		
		local ARGS = {}
		for i = 1, argCount do ARGS[i] = "arg"..i end
		ARGS = table.concat(ARGS, ", ")
		code = code:gsub("ARGS", ARGS)
		return assert(loadstring(code, "safecall Dispatcher["..argCount.."]"))(xpcall, errorhandler)
	end

	local Dispatchers = setmetatable({}, {__index=function(self, argCount)
		local dispatcher = CreateDispatcher(argCount)
		rawset(self, argCount, dispatcher)
		return dispatcher
	end})
	Dispatchers[0] = function(func)
		return xpcall(func, errorhandler)
	end

	function FrameHelper.safecall(func, ...)
		if func then
			return Dispatchers[select('#', ...)](func, ...)
		end
	end
end
local safecall = FrameHelper.safecall

local function safecallf(method, ...)
	return select(2, safecall(FrameHelper.CF[method], FrameHelper.CF, ...))
end


do	-- FrameHelper:GeneratePathFromString()
	-- Copied from ImprovedFrameStack, another addon of mine.

	local function insert(t, k)
		tinsert(t, 1, k)
	end

	local STR_UNKNOWN = "?"

	-- Format the path nicely for the tooltip. Make it look like an actual["table"]["lookup"]["chain"]
	local function fmt(t)
		local s = ""
		for i = 1, #t do
			local k = t[i]
			local str = tostring(k)
			
			if i == 1 then
				s = k
			else
				if type(k) == "number" then
					k = "[" .. k .. "]"
				elseif str == STR_UNKNOWN then
					k = "[" .. str .. "]"

				--elseif str:find("[^A-Za-z_0-9]") or str:find("^[0-9]") then
				else
					k = "[\"" .. str .. "\"]"

				--else
				--    k = "." .. str
				end

				s = s .. k
			end
		end
		
		return s
	end


	local searchResults = {}
	local fmtTable = {}

	-- Generate the path for a frame and store it in searchResults
	local function scanTables(parent, child, depth, maxDepth)
		depth = depth + 1
		for k, v in pairs(parent) do
			if v == child then
				insert(fmtTable, k)
				return true
			end
		end

		-- Breadth first. Limit the depth each time.
		for i = depth+1, maxDepth do
			for k, v in pairs(parent) do
				if type(v) == "table" and depth < maxDepth then
					local found = scanTables(v, child, depth, i)
					if found then
						insert(fmtTable, k)
						return true
					end
				end
			end
		end
	end

	function FrameHelper:GenerateFramePathString(frame)
		if frame:GetName() then
			return frame:GetName(), false
		end

		wipe(fmtTable)

		local parent = frame

		-- Edge case: no parent at all.
		if not frame:GetParent() then
			return "<No Parent>", true
		end
		
		local done = false
		while true do
			local child = parent
			parent = parent:GetParent()
			
			-- Might happen if a frame was orphaned on purpose.
			-- Accidental ophaning isn't possible in WoW as far as I know,
			-- with maybe exception of changing a scroll child and not re-parenting the old child
			if not parent then 
				break
			end
			
			local foundChildKey = scanTables(parent, child, 0, 4)


			if not foundChildKey then
				-- We didn't find a key so that parent[key] = child, so insert STR_UNKNOWN
				-- to show that there is no straightforward ref from parent to child.
				insert(fmtTable, STR_UNKNOWN)
			end

			if parent:GetName() then
				-- This parent is named, so we now have a path from a named ancestor to the current frame.
				-- This is what we want, so we are done.
				insert(fmtTable, parent:GetName())

				return fmt(fmtTable), true
			end
		end


		--insert(fmtTable, "<Unknown Parent>")

		return fmt(fmtTable), true
	end
end

do	-- FrameHelper:Vararg(...)
	local states = {}
	local function getstate(...)
		local state = wipe(tremove(states) or {})

		state.i = 0
		state.l = select("#", ...)

		for n = 1, state.l do
			state[n] = select(n, ...)
		end

		return state
	end

	local function iter(state)
		local i = state.i
		i = i + 1
		if i > state.l then
			tinsert(states, state)
			return
		end
		state.i = i

		return i, state[i], state.l
	end

	function FrameHelper:Vararg(...)
		return iter, getstate(...)
	end
end



Classes:NewClass("Config_Frame", "Frame"){
	XMLTemplate = "FrameHelper_BorderedFrame",

	NewWidget = function(self, Property)
		if M.frames[Property.name] then
			error("duplicate frame creation")
		end

		local parent = M
		local f = self:New(self.isFrameObject, M:GetName() .. Property.name, M, self.XMLTemplate, nil, Property)
		M.frames[Property.name] = f
		Property.frame = f

		if Property.init then
			Property:init(f)
		end

		return f
	end,

	-- Constructor
	OnNewInstance_Frame = function(self, Property)
		self.data = Property
	end,

	HandlePosition = function(self)
		local Property = self.data

		if Property.position then
			Property.positions = {Property.position}
			Property.position = nil
		end

		if Property.positions then
			for _, position in pairs(Property.positions) do
				local point, relTo, relPoint, x, y
				
				if type(position[1]) == "table" then -- This table was actually a list of points to try.
					for i, position in ipairs(position) do
						local relTo_test = position[2]

						if type(relTo_test) == "string" and type(M.frames[relTo_test]) == "table" then
							relTo_test = M.frames[relTo_test]
						end
						if type(relTo_test) == "table" and relTo_test:IsShown() then
							point, _, relPoint, x, y = unpack(position)
							relTo = relTo_test
							break
						end
					end
				else
					point, relTo, relPoint, x, y = unpack(position)

					if type(relTo) == "string" and type(M.frames[relTo]) == "table" then
						relTo = M.frames[relTo]
					end
				end



				if not relTo or (type(relTo) == "table" and not relTo:IsShown()) then
					-- do nothing
				else
					relPoint = relPoint or point

					pcall(self.SetPoint, self, point, relTo, relPoint, x, y)
				end
			end
		end
	end,

	IsEditing = function(self)
		if self:IsVisible() and self.isEditing then
			return true
		end
		
		for i, child in FrameHelper:Vararg(self:GetChildren()) do
			if child.IsEditing and child:IsEditing() then
				return true
			end
		end
	end,

	Refresh = function(self)
		if not self:IsEditing() then
			self:ReloadSetting()
		end
	end,

	TT = function(self, ...)
		FrameHelper:TT(self, ...)
	end,


	Set = function(self, ...)
		return self.data:Set(...)
	end,
	Get = function(self, ...)
		return self.data:Get(...)
	end,
}


local spacerInfo = {
	text = "",
	isTitle = true,
	notCheckable = true,
}
local function AddDropdownSpacer()
	UIDropDownMenu_AddButton_Scrolled(spacerInfo, UIDROPDOWNMENU_MENU_LEVEL)
end
Classes:NewClass("Config_DropDownMenu", "Config_Frame"){
	XMLTemplate = "UIDropDownMenuTemplate",
	noResize = 1,

	OnNewInstance_DropDownMenu = function(self, data)
	end,

	SetText = function(self, text)
		UIDropDownMenu_SetText(self, (self.textPrefix or "") .. text)
	end,
}

Classes:NewClass("Config_DropDownMenu_SimpleSelect", "Config_DropDownMenu"){
	noResize = 1,

	OnNewInstance_DropDownMenu = function(self, data)
		self.initialize = self.DD_Func
		if not data.values then
			error("values are required for simple select dropdowns")
		end
	end,

	DD_Func = function(self)
		for i, v in ipairs(self.data.values) do
			local info = UIDropDownMenu_CreateInfo()

			info.text = v
			info.checked = self:Get() == v
			info.func = self.DD_Click
			info.value = v
			info.arg1 = self
			info.arg2 = v

			UIDropDownMenu_AddButton_Scrolled(info, UIDROPDOWNMENU_MENU_LEVEL)
		end
	end,
	DD_Click = function(button, self, value)
		self:Set(value)
		self:SetText(value)

		FrameHelper:Refresh()
	end,

	ReloadSetting = function(self)
		self:SetText(self:Get() or "?")
	end,
}

Classes:NewClass("Config_DropDownMenu_FramePicker", "Config_DropDownMenu"){
	includeParent = false,

	OnNewInstance_DropDownMenu_FramePicker = function(self, data)
		self.initialize = self.DD_Func
		self.blacklist = {}
	end,

	SetIncludeParent = function(self, includeParent)
		self.includeParent = includeParent
	end,
	GetIncludeParent = function(self)
		return self.includeParent
	end,

	ShowForRootFrame = function(self, root, anchor)
		self.root = root
		wipe(self.blacklist)
		ToggleDropDownMenu(1, nil, self, anchor, 0, 0)
	end,

	DD_Func = function(self)
		local blacklist = self.blacklist
		local region = UIDROPDOWNMENU_MENU_VALUE or self.root

		if not region:IsObjectType("Frame") then
			return
		end

		blacklist[UIDROPDOWNMENU_MENU_LEVEL] = region
		for i = UIDROPDOWNMENU_MENU_LEVEL+1, #blacklist do
			blacklist[i] = nil
		end

		local regionName = FrameHelper:GenerateFramePathString(region)
		do
			local info = UIDropDownMenu_CreateInfo()

			info.text = regionName
			info.isTitle = true
			info.notCheckable = true
			info.notClickable = true

			UIDropDownMenu_AddButton_Scrolled(info, UIDROPDOWNMENU_MENU_LEVEL)
		end

		local parent = region:GetParent()
		if self.includeParent and parent and not tContains(blacklist, parent) then

			local info = UIDropDownMenu_CreateInfo()


			local name = FrameHelper:GenerateFramePathString(parent)
			info.text = name

			info.tooltipTitle = name
			info.tooltipText = "Parent of " .. regionName
			info.tooltipOnButton = true
			info.tooltipWhileDisabled = true

			info.disabled = tContains(blacklist, parent)
			info.func = self.DD_Click
			info.arg1 = parent
			info.value = parent
			info.hasArrow = not info.disabled
			info.notCheckable = true

			UIDropDownMenu_AddButton_Scrolled(info, UIDROPDOWNMENU_MENU_LEVEL)
			AddDropdownSpacer()
		end

		local regions = {region:GetChildren()}

		if (region:GetRegions() and #regions > 0) then
			local info = UIDropDownMenu_CreateInfo()
			info.text = "Frames"
			info.isTitle = true
			info.notCheckable = true
			UIDropDownMenu_AddButton_Scrolled(info, UIDROPDOWNMENU_MENU_LEVEL)

			tinsert(regions, true)
		end

		for i, region in FrameHelper:Vararg(region:GetRegions()) do
			tinsert(regions, region)
		end


		local offset = 0
		for i, region in pairs(regions) do
			if region == true then
				offset = i
				AddDropdownSpacer()

				local info = UIDropDownMenu_CreateInfo()
				info.text = "Layers"
				info.isTitle = true
				info.notCheckable = true
				UIDropDownMenu_AddButton_Scrolled(info, UIDROPDOWNMENU_MENU_LEVEL)
			else
				i = i - offset
				local info = UIDropDownMenu_CreateInfo()


				local name, wasUnnamed = FrameHelper:GenerateFramePathString(region)
				local generatedSpecialName
				local parent = region:GetParent()
				if parent then
					for _, method in FrameHelper:Vararg(
						"GetNormalTexture",
						"GetPushedTexture",
						"GetHighlightTexture",
						"GetCheckedTexture",
						"GetDisabledCheckedTexture",

						"GetFontString",

						"GetStatusBarTexture",
						"GetColorValueTexture",
						"GetColorValueThumbTexture",
						"GetColorWheelTexture",
						"GetColorWheelThumbTexture"
					) do
						if parent[method] and parent[method](parent) == region then
							name = "self:" .. method .. "()"
							generatedSpecialName = true
							break
						end
					end

					if region:GetParent():GetName() then
						name = gsub(name, region:GetParent():GetName(), "... ")
					end
				end

				info.text = "<" .. i .. " " .. region:GetObjectType() .. "> " .. name

				if wasUnnamed or generatedSpecialName then
					info.tooltipTitle = name
					info.tooltipText = "Generated path for " .. (region:GetName() or tostring(region))
					info.tooltipOnButton = true
					info.tooltipWhileDisabled = true
				end

				info.disabled = tContains(blacklist, region)
				info.func = self.DD_Click
				info.arg1 = region
				info.value = region
				info.hasArrow = not info.disabled and region:IsObjectType("Frame") and (region:GetChildren() or region:GetRegions())
				info.notCheckable = true

				UIDropDownMenu_AddButton_Scrolled(info, UIDROPDOWNMENU_MENU_LEVEL)
			end
		end
	end,

	DD_Click = function(button, region)
		FrameHelper:Load(region)
	end,
}



Classes:NewClass("Config_EditBox", "EditBox", "Config_Frame"){
	XMLTemplate = "FrameHelper_InputBoxTemplate",
	
	-- Constructor
	OnNewInstance_EditBox = function(self, data)
		self.BackgroundText:SetWidth(self:GetWidth())

		if data then
			self.text:SetText(data.name)
			self.label = data.name
		end
	end,
	

	-- Scripts
	OnEditFocusGained = function(self, button)
		self.isEditing = true
	end,

	OnEditFocusLost = function(self, button)
		self.isEditing = false
		self:SaveSetting()
		
		-- Cheater! (We arent getting anything)
		-- (I'm using get as a wrapper so I don't have to check if the function exists before calling it)
		get(self.data.OnEditFocusLost, self, button) 
	end,

	OnTextChanged = function(self, button)		
		-- Cheater! (We arent getting anything)
		-- (I'm using get as a wrapper so I don't have to check if the function exists before calling it)
		get(self.data.OnTextChanged, self, button) 
	end,

	METHOD_EXTENSIONS = {
		OnEnable = function(self)
			self:EnableMouse(true)
			self:EnableKeyboard(true)
		end,

		OnDisable = function(self)
			self:ClearFocus()
			self:EnableMouse(false)
			self:EnableKeyboard(false)
		end,
	},
	

	-- Methods
	SaveSetting = function(self)
		self:Set(self:GetText())

		FrameHelper:Refresh()
	end,

	ReloadSetting = function(self)
		self:SetText(tostring(self:Get() or ""))
	end,
}

Classes:NewClass("Config_EditBox_Frame", "Config_EditBox"){
	FrameMap = {},
	__noWrapTooltipText = 1,

	GetFrameMap = function(self)
		local frame
		local FrameMap = wipe(self.FrameMap)
		while true do
		    frame = EnumerateFrames(frame)
		    if not frame then
		        break
		    end
		    FrameMap[tostring(frame)] = frame
		end

		return FrameMap
	end,

	SetAllowRelativeParents = function(self, allow)
		self.relativeParents = allow
	end,

	SetFrame = function(self, frame)
		if self.lastFrameText and self.lastFrame == frame then
			return
		end
		
		self:TT(nil, nil)

		if not frame then
			self:SetText("nil")
		else
			local name = frame.GetName and frame:GetName()
			if name then
				self:SetText(name)
			else
				local gen = FrameHelper:GenerateFramePathString(frame)
				if gen:find("%[%?%]") then
					self:SetText(tostring(frame))
					self:TT("Generated Path:", gen:gsub("%[%?%]", "|cffff0000[?]|r"))
				else
					self:SetText(gen)
					self:TT("Address:", tostring(frame))
				end
			end
		end

		self.lastFrameText = self:GetText()
		self.lastFrame = frame
	end,

	GetFrame = function(self)
		if self.lastFrameText == self:GetText() then
			return self.lastFrame
		end

		local text = self:GetText()
		local frame = _G[text]
		if type(frame) == "table" and type(frame[0]) == "userdata" then
			return frame
		else
			local FrameMap = self:GetFrameMap()
			if FrameMap[text] then
				return FrameMap[text]
			end

			local func = loadstring("return " .. text)
			if func then
				local success, frame = pcall(func)
				if success and type(frame) == "table" and type(frame[0]) == "userdata" then
					return frame
				end
			end

			-- TODO
			return UIParent
		end
	end,

	SaveSetting = function(self)
		self:Set(self:GetFrame())

		FrameHelper:Refresh()
	end,

	ReloadSetting = function(self)
		self:SetFrame(self:Get())
	end,
}

Classes:NewClass("Config_Point", "Config_Frame"){
	XMLTemplate = "FrameHelper_PointTemplate",

	SaveSettingChildOverride = function(child)
		child:GetParent():GetParent():SaveSetting()
	end,

	OnNewInstance_Point = function(self, data)
		--Classes.Config_DropDownMenu:NewFromExisting(self.Point)
		self.Point.initialize = self.DD_Init
		UIDropDownMenu_SetWidth(self.Point, 110)

		--Classes.Config_DropDownMenu:NewFromExisting(self.RelativePoint)
		self.RelativePoint.initialize = self.DD_Init
		UIDropDownMenu_SetWidth(self.RelativePoint, 110)


		Classes.Config_EditBox_Frame:NewFromExisting(self.RelativeTo, {})
		self.RelativeTo.SaveSetting = self.SaveSettingChildOverride
		self.RelativeTo.label = "Relative To"
		self.RelativeTo.text:SetText("Relative To")
		self.RelativeTo:SetWidth(350)

		Classes.Config_Slider:NewFromExisting(self.X, {
			Get = function()
				local _, _, _, x = safecallf("GetPoint", self:GetID())
				return x
			end,
		})
		self.X:UseEditBox()
		--self.X.text:SetText("X")
		self.X.midLabel = "X: "
		self.X:SetMinMaxValues()
		self.X:SetMode(self.X.MODE_ADJUSTING)
		self.X:SetRange(50)
		self.X:SetValueStep(0.1)
		self.X:SetWheelStep(1)
		self.X.SaveSetting = self.SaveSettingChildOverride

		Classes.Config_Slider:NewFromExisting(self.Y, {
			Get = function()
				local _, _, _, _, y = safecallf("GetPoint", self:GetID())
				return y
			end,
		})
		self.Y:UseEditBox()
		--self.Y.text:SetText("Y")
		self.Y.midLabel = "Y: "
		self.Y:SetMinMaxValues()
		self.Y:SetMode(self.Y.MODE_ADJUSTING)
		self.Y:SetRange(50)
		self.Y:SetValueStep(0.1)
		self.Y:SetWheelStep(1)
		self.Y.SaveSetting = self.SaveSettingChildOverride
		

		self.Point:Show()
		self.RelativeTo:Show()
		self.RelativePoint:Show()
		self.X:Show()
		self.Y:Show()
	end,

	points = {
		"LEFT",
		"RIGHT",
		"TOP",
		"BOTTOM",
		"CENTER",
		"TOPLEFT",
		"TOPRIGHT",
		"BOTTOMLEFT",
		"BOTTOMRIGHT",
	},

	DD_Init = function(DDFrame)
		local self = DDFrame:GetParent()

		for i, point in ipairs(self.points) do
			local info = UIDropDownMenu_CreateInfo()
			info.func = self.DD_Click
			info.text = point
			info.value = point
			info.arg1 = self
			info.arg2 = point
			UIDropDownMenu_AddButton_Scrolled(info)
		end
	end,
	DD_Click = function(button, self, point)
		UIDROPDOWNMENU_OPEN_MENU.value = point
		UIDropDownMenu_SetText(UIDROPDOWNMENU_OPEN_MENU, point)

		self:GetParent():SaveSetting()
	end,

	RemoveAnchor = function(self)
		self:GetParent():SaveSetting(self:GetID())
	end,
}

Classes:NewClass("Config_SetPoint", "Config_Frame"){
	currentNumPoints = 0,

	OnNewInstance_SetPoint = function(self, data)
		self.Background:SetAlpha(0.01)
		self:HandlePosition()

		self.AddAnchor = CreateFrame("Frame", "$parentAddAnchor", self, "FrameHelper_AddAnchor")
		self.AddAnchor.Point.initialize = self.DD_AddPoint
		UIDropDownMenu_SetText(self.AddAnchor.Point, "Add Point")
	end,

	DD_AddPoint = function(DDFrame)
		local self = DDFrame:GetParent():GetParent()
		self.usedPoints = wipe(self.usedPoints or {})

		for i = 1, self.currentNumPoints do
			local point = safecallf("GetPoint", i)
			self.usedPoints[point] = 1
		end

		for i, point in ipairs(Classes.Config_Point.points) do
			if not self.usedPoints[point] then
				local info = UIDropDownMenu_CreateInfo()
				info.func = self.DD_AddPoint_Click
				info.text = point
				info.value = point
				info.arg1 = self
				info.arg2 = point
				UIDropDownMenu_AddButton_Scrolled(info)
			end
		end
	end,
	DD_AddPoint_Click = function(button, self, point)
		safecallf("SetPoint", point)
	end,

	SetupFrames = function(self)
		for i = #self+1, self.currentNumPoints do
			self[i] = Classes.Config_Point:New("Frame", "$parentP" .. i, self, "FrameHelper_PointTemplate", i)
		
			if i == 1 then
				self[i]:SetPoint("TOPLEFT", 3, -3)
			else
				self[i]:SetPoint("TOPLEFT", self[i-1], "BOTTOMLEFT", 0, -5)
			end

		end


		for i = 1, self.currentNumPoints do
			self[i]:Show()
		end

		for i = self.currentNumPoints+1, #self do
			self[i]:Hide()
		end

		if self.currentNumPoints == 0 then
			self.AddAnchor:SetPoint("TOPLEFT", 3, -3)
		else
			self.AddAnchor:SetPoint("TOPLEFT", self[self.currentNumPoints], "BOTTOMLEFT", 0, -5)
		end

		--[[if self.currentNumPoints == 1 then
			self[1].Remove:Hide()
		elseif self[1] then
			self[1].Remove:Show()
		end]]


		self:SetHeight(self.currentNumPoints * (self[1]:GetHeight() + 5) + self.AddAnchor:GetHeight() + 6)
	end,



	-- Methods
	SaveSetting = function(self, skipAt)
		safecallf("ClearAllPoints")

		for i = 1, self.currentNumPoints do
			if skipAt ~= i then
				local point = self[i].Point.value
				local relPoint = self[i].RelativePoint.value

				local relTo = self[i].RelativeTo:GetFrame()

				local x = self[i].X:GetValue()
				local y = self[i].Y:GetValue()

				safecallf("SetPoint", point, relTo, relPoint, x, y)
			end
		end

		FrameHelper:Refresh()
	end,

	ReloadSetting = function(self)
		self.currentNumPoints = safecallf("GetNumPoints")
		self:SetupFrames()

		for i = 1, self.currentNumPoints do
			self[i]:Show()
			local point, relTo, relPoint, x, y = safecallf("GetPoint", i)

			self[i].Point.value = point
			UIDropDownMenu_SetText(self[i].Point, point)

			self[i].RelativePoint.value = relPoint
			UIDropDownMenu_SetText(self[i].RelativePoint, relPoint)


			self[i].RelativeTo:SetFrame(relTo)

			self[i].X:SetValue(x)
			self[i].Y:SetValue(y)
		end
	end,
}

Classes:NewClass("Config_Slider", "Slider", "Config_Frame")
{
	-- Saving base methods.
	-- This is done in a separate call to make sure it happens before 
	-- new ones overwrite the base methods.

	Show_base = Classes.Config_Slider.Show,
	Hide_base = Classes.Config_Slider.Hide,

	SetValue_base = Classes.Config_Slider.SetValue,
	GetValue_base = Classes.Config_Slider.GetValue,

	GetValueStep_base = Classes.Config_Slider.GetValueStep,

	GetMinMaxValues_base = Classes.Config_Slider.GetMinMaxValues,
	SetMinMaxValues_base = Classes.Config_Slider.SetMinMaxValues,
}{
	XMLTemplate = "FrameHelper_SliderTemplate",

	Config_EditBox_Slider = Classes:NewClass("Config_EditBox_Slider", "Config_EditBox"){
		
		-- Constructor
		OnNewInstance_EditBox_Slider = function(self, data)
			self:EnableMouseWheel(true)
		end,
		

		-- Scripts
		OnEditFocusGained = function(self, button)
			self.Slider.isEditing = true
		end,

		OnEditFocusLost = function(self, button)
			self.Slider.isEditing = false

			local text = tonumber(self:GetText())
			if text then
				self.Slider:SetValue(text)
				self.Slider:SaveSetting()
			end

			self:SetText(self.Slider:GetValue())
		end,


		OnMouseDown = function(self, button)
			if button == "RightButton" and not self.Slider:ShouldForceEditBox() then
				self.Slider:UseSlider()
			end
		end,

		OnMouseWheel = function(self, ...)
			self.Slider:GetScript("OnMouseWheel")(self.Slider, ...)
		end,

		METHOD_EXTENSIONS = {
			OnEnable = function(self)
				self:EnableMouse(true)
				self:EnableKeyboard(true)
			end,

			OnDisable = function(self)
				self:ClearFocus()
				self:EnableMouse(false)
				self:EnableKeyboard(false)
			end,
		},
		

		-- Methods
		ReloadSetting = function(self)
			self:SetText(self.Slider:GetValue())
		end,
	},

	EditBoxShowing = false,

	MODE_STATIC = 1,
	MODE_ADJUSTING = 2,

	FORCE_EDITBOX_THRESHOLD = 10e5,

	range = 10,

	-- Constructor
	OnNewInstance_Slider = function(self, data)
		self.min, self.max = self:GetMinMaxValues()

		self:SetMode(self.MODE_STATIC)

		if data.min and data.max then
			self:SetMinMaxValues(data.min, data.max)
		end
		if data.range then
			self:SetRange(data.range)
		end

		self:SetValueStep(data.step or self:GetValueStep() or 1)
		self:SetWheelStep(data.wheelStep)
		
		self.text:SetText(data.name)
		
		self:EnableMouseWheel(true)
	end,

	-- Blizzard Overrides
	GetValue = function(self)
		if self.EditBoxShowing then
			local text = self.EditBox:GetText()
			text = tonumber(text)
			if text then
				return self:CalculateValueRoundedToStep(text)
			end
		end

		return self:CalculateValueRoundedToStep(self:GetValue_base())
	end,
	SetValue = function(self, value)
		if value < self.min then
			value = self.min
		elseif value > self.max then
			value = self.max
		end
		value = self:CalculateValueRoundedToStep(value)

		self:UpdateRange(value)
		self:SetValue_base(value)
		if self.EditBoxShowing then
			self.EditBox:SetText(value)
		end
	end,

	GetMinMaxValues = function(self)
		local min, max = self:GetMinMaxValues_base()

		min = self:CalculateValueRoundedToStep(min)
		max = self:CalculateValueRoundedToStep(max)

		return min, max
	end,
	SetMinMaxValues = function(self, min, max)
		min = min or -math.huge
		max = max or math.huge

		if min > max then
			error("min can't be bigger than max")
		end

		self.min = min
		self.max = max

		if self.mode == self.MODE_STATIC then
			self:SetMinMaxValues_base(min, max)
		elseif not self.EditBoxShowing then
			self:UpdateRange()
		end
	end,

	GetValueStep = function(self)
		local step = self:GetValueStep_base()
		return floor((step*10^5) + .5) / 10^5
	end,

	SetWheelStep = function(self, wheelStep)
		self.wheelStep = wheelStep
	end,
	GetWheelStep = function(self)
		return self.wheelStep or self:GetValueStep()
	end,



	Show = function(self)
		if self.EditBoxShowing then
			self.EditBox:Show()
		else
			self:Show_base()
		end
	end,
	Hide = function(self)
		self:Hide_base()
		if self.EditBoxShowing then
			self.EditBox:Hide()
		end
	end,

	-- Script Handlers
	OnMinMaxChanged = function(self)
		self:UpdateTexts()
	end,

	OnValueChanged = function(self)
		if not self.__fixingValueStep then
			self.__fixingValueStep = true
			self:SetValue_base(self:GetValue())
			self.__fixingValueStep = nil
		else
			return
		end

		if self.EditBox then
			self.EditBox:SetText(self:GetValue())
		end

		if self:ShouldForceEditBox() then
			self:UseEditBox()
		end

		self:UpdateTexts()

	end,

	OnMouseDown = function(self, button)
		if button == "RightButton" then
			self:UseEditBox()
		else
			self.isEditing = true
		end
	end,

	OnMouseUp = function(self)
		self.isEditing = false

		if self.mode == self.MODE_ADJUSTING then
			self:UpdateRange()
		end
		
		self:SaveSetting()
	end,
	
	OnMouseWheel = function(self, delta)
		if self:IsEnabled() then
			if IsShiftKeyDown() then
				delta = delta*10
			end
			if IsControlKeyDown() then
				delta = delta*60
			end
			if delta == 1 or delta == -1 then
				delta = delta*(self:GetWheelStep() or 1)
			end

			local level = self:GetValue() + delta

			self:SetValue(level)

			self:SaveSetting()
		end
	end,

	-- Methods
	SetRange = function(self, range)
		self.range = range
		self:UpdateRange()
	end,
	GetRange = function(self)
		return self.range
	end,

	CalculateValueRoundedToStep = function(self, value)
		local step = self:GetValueStep()

		return floor(value * (1/step) + 0.5) / (1/step)
	end,

	SetMode = function(self, mode)
		self.mode = mode

		if mode == self.MODE_STATIC then
			self:UseSlider()
		end

		self:UpdateRange()
	end,
	GetMode = function(self)
		return self.mode
	end,


	ShouldForceEditBox = function(self)
		if self:GetMode() == self.MODE_STATIC then
			return false
		elseif self:GetValue() > self.FORCE_EDITBOX_THRESHOLD then
			return true
		end
	end,

	UseEditBox = function(self)
		if self:GetMode() == self.MODE_STATIC then
			return
		end

		if not self.EditBox then
			local name = self:GetName() and self:GetName() .. "Box" or nil
			self.EditBox = self.Config_EditBox_Slider:New("EditBox", name, self:GetParent(), "FrameHelper_InputBoxTemplate", nil, {})
			self.EditBox.Slider = self

			self.EditBox:SetPoint("TOP", self, "TOP", 0, -4)
			self.EditBox:SetPoint("LEFT", self, "LEFT", 2, 0)
			self.EditBox:SetPoint("RIGHT", self)

			self.EditBox:SetText(self:GetValue())

			if self.ttData then
				self:SetTooltip(unpack(self.ttData))
			end
		end

		if not self.EditBoxShowing then
			self.EditBoxShowing = true
			if self.text:GetParent() == self then
				self.text:SetParent(self.EditBox)
			end

			self.EditBox:Show()
			self:Hide_base()

			self:ReloadSetting()
		end
	end,
	UseSlider = function(self)
		if self.EditBoxShowing then
			self.EditBoxShowing = false

			if self.text:GetParent() == self.EditBox then
				self.text:SetParent(self)
			end

			if self.EditBox:IsShown() then
				self:Show_base()
			end
			self.EditBox:Hide()
			self:UpdateRange()

			self:ReloadSetting()
		end
	end,

	TT_textFunc = function(self)
		local text = self.ttData[2]

		if not text then
			text = ""
		else
			text = text .. "\r\n\r\n"
		end

		if self:GetObjectType() == "Slider" then
			if self:GetMode() == self.MODE_ADJUSTING then
				text = text .. L["CNDT_SLIDER_DESC_CLICKSWAP_TOMANUAL"]
			else
				return self.ttData[2]
			end
		else -- EditBox
			if self.Slider:ShouldForceEditBox() then
				text = text .. L["CNDT_SLIDER_DESC_CLICKSWAP_TOSLIDER_DISALLOWED"]:format(self.Slider.FORCE_EDITBOX_THRESHOLD)
			else
				text = text .. L["CNDT_SLIDER_DESC_CLICKSWAP_TOSLIDER"]
			end
		end

		return text
	end,

	SetTooltip = function(self, title, text)
		self.ttData = {title, text}

		FrameHelper:TT(self, title, self.TT_textFunc)

		if self.EditBox then
			FrameHelper:TT(self.EditBox, title, self.TT_textFunc)
			self.EditBox.ttData = self.ttData
		end
	end,

	UpdateTexts = function(self)
		self.Mid:SetText((self.midLabel or "") .. self:GetValue())

		local minValue, maxValue = self:GetMinMaxValues()
		
		self.Low:SetText(minValue)
		self.High:SetText(maxValue)
	end,


	UpdateRange = function(self, value)
		if self.mode == self.MODE_ADJUSTING then
			local deviation = self.range/2
			local val = value or self:GetValue()

			local newmin = min(max(self.min, val - deviation), self.max)
			local newmax = max(min(self.max, val + deviation), self.min)
			--newmax = min(newmax, self.max)

			self:SetMinMaxValues_base(newmin, newmax)
		else
			self:SetMinMaxValues_base(self.min, self.max)
		end
	end,


	IsEditing = function(self)
		if (self:IsVisible() or (self.EditBox and self.EditBox:IsVisible()) ) and self.isEditing then
			return true
		end
	end,

	SaveSetting = function(self)
		self:Set(self:GetValue())

		FrameHelper:Refresh()
	end,

	ReloadSetting = function(self)
		self:SetValue(tonumber(self:Get() or 0))
	end,
}


Classes:NewClass("Config_CheckButton", "CheckButton", "Config_Frame"){
	XMLTemplate = "FrameHelper_CheckTemplate",

	-- Constructor
	OnNewInstance_CheckButton = function(self, data)
		self:SetMotionScriptsWhileDisabled(true)
		self.text:SetText(self.data.text or self.data.name)
		self.text:SetWidth(81)
		self.text:SetNonSpaceWrap(true)
	end,


	-- Script Handlers
	OnClick = function(self, button)
		self:SaveSetting()
		
		-- Cheater! (We arent getting anything)
		-- (I'm using get as a wrapper so I don't have to check if the function exists before calling it)
		get(self.data.OnClick, self, button)
	end,

	SaveSetting = function(self)
		local checked = not not self:GetChecked()
		self:Set(checked)

		FrameHelper:Refresh()
	end,

	ReloadSetting = function(self)
		self:SetChecked(self:Get())
	end,
}



Classes:NewClass("Resizer_Generic"){
	-- Copied from TMW


	tooltipTitle = "Resize",
	tooltipText = [[|cff7fffffClick-and-drag|r to resize]],

	MODE_SIZE = 1,
	MODE_SCALE = 2,

	-- Configuration. Set these on created instances.
	scale_min = 0.4,
	scale_max = math.huge,
	x_min = 0,
	x_max = math.huge,
	y_min = 0,
	y_max = math.huge,
	
	OnNewInstance_Resizer = function(self, parent)
		self.parent = parent
		
		self.mode_x = self.MODE_SIZE
		self.mode_y = self.MODE_SIZE

		self.resizeButton = CreateFrame("Button", nil, parent, "FrameHelper_ResizeButton")
		
		-- Default module state is disabled, but default frame state is shown,
		-- so initially we need to hide the button so that the two states agree with eachother.
		self.resizeButton:Hide()
		
		self.resizeButton.module = self
		
		self.resizeButton:SetScript("OnMouseDown", self.StartSizing)
		self.resizeButton:SetScript("OnMouseUp", self.OnMouseUp)
		
		-- A new function is requied for each resizeButton/parent combo because it has to be able to reference both.
		parent:HookScript("OnSizeChanged", function(parent)
			local scale = 1.6 / parent:GetEffectiveScale()
			scale = max(scale, 0.6)
			self.resizeButton:SetScale(scale)
		end)

		-- Initial value. Should be good enough.
		self.resizeButton:SetScale(2)

		self.resizeButton:HookScript("OnShow", function(self)
			self:SetFrameLevel(self:GetParent():GetFrameLevel() + 5)
		end)

		FrameHelper:TT(self.resizeButton, self.tooltipTitle, self.tooltipText)
	end,

	Show = function(self)
		self.resizeButton:Show()
	end,
	Hide = function(self)
		self.resizeButton:Hide()
	end,
	
	ShowTexture = function(self)
		self.resizeButton.texture:Show()
	end,
	HideTexture = function(self)
		self.resizeButton.texture:Hide()
	end,

	OnMouseUp = function(resizeButton)
		local self = resizeButton.module

		self.StopSizing(resizeButton)
		self:ShowTexture()
	end,

	SetModes = function(self, x, y)
		self.mode_x = x
		self.mode_y = y
	end,

	
	GetStandardizedCoordinates = function(self)
		local parent = self.parent
		local scale = parent:GetEffectiveScale()
		
		return
			parent:GetLeft()*scale,
			parent:GetRight()*scale,
			parent:GetTop()*scale,
			parent:GetBottom()*scale
	end,
	GetStandardizedCursorCoordinates = function(self)
		-- This method is rather pointless (its just a wrapper),
		-- but having consistency is nice so that I don't have to remember if the coords returned
		-- are comparable to other Standardized coordinates/sizes
		return GetCursorPosition()    
	end,
	GetStandardizedSize = function(self)
		local parent = self.parent
		local x, y = parent:GetSize()
		local scale = parent:GetEffectiveScale()
		
		return x*scale, y*scale
	end,
	
	StartSizing = function(resizeButton, button)
		local self = resizeButton.module
		local parent = self.parent
		
		self.std_oldLeft, self.std_oldRight, self.std_oldTop, self.std_oldBottom = self:GetStandardizedCoordinates()
		self.std_oldWidth, self.std_oldHeight = self:GetStandardizedSize()
		
		self.oldScale = parent:GetScale()
		self.oldUIScale = UIParent:GetScale()
		self.oldEffectiveScale = parent:GetEffectiveScale()
		
		self.oldX, self.oldY = parent:GetLeft(), parent:GetTop()

		self.button = button
		
		if button == "RightButton" and self.SizeUpdate_RightButton then
			resizeButton:SetScript("OnUpdate", self.SizeUpdate_RightButton)
		else
			resizeButton:SetScript("OnUpdate", self.SizeUpdate)
		end

		self:HideTexture()
	end,

	StopSizing = function(resizeButton)
		resizeButton:SetScript("OnUpdate", nil)

		local self = resizeButton.module
		self:ShowTexture()
	end,

	SizeUpdate = function(resizeButton)
		--[[ Notes:
		--	arg1 (self) is resizeButton
			
		--	The 'std_' that prefixes a lot of variables means that it is comparable with all other 'std_' variables.
			More specifically, it means that it does not depend on the scale of either the group nor UIParent.
		]]
		local self = resizeButton.module
		
		local parent = self.parent
		
		local std_cursorX, std_cursorY = self:GetStandardizedCursorCoordinates()
		

		-- Calculate new scale:
		--[[
			Holy shit. Look at this wicked sick dimensional analysis:
			
			std_newHeight	oldScale
			------------- X	-------- = newScale
			std_oldHeight	    1

			'std_Height' cancels out 'std_Height', and 'old' cancels out 'old', leaving us with 'new' and 'Scale'!
			I just wanted to make sure I explained why this shit works, because this code used to be confusing as hell
			(which is why I am rewriting it right now)
		]]
		local std_newWidth = std_cursorX - self.std_oldLeft
		local ratio_SizeChangeX = std_newWidth/self.std_oldWidth
		local newScaleX = ratio_SizeChangeX*self.oldScale
		
		local std_newHeight = self.std_oldTop - std_cursorY
		local ratio_SizeChangeY = std_newHeight/self.std_oldHeight
		local newScaleY = ratio_SizeChangeY*self.oldScale

		local newScale = self.oldScale


		-- Mode-dependent calculation
		if self.mode_x == self.MODE_SCALE and self.mode_y == self.MODE_SCALE then
			if IsControlKeyDown() then
				-- Uses the smaller of the two scales.
				newScale = min(newScaleX, newScaleY)
			else
				-- Uses the larger of the two scales.
				newScale = max(newScaleX, newScaleY)
			end

		elseif self.mode_y == self.MODE_SCALE then
			newScale = newScaleY
		elseif self.mode_x == self.MODE_SCALE then
			newScale = newScaleX
		end

		newScale = max(self.scale_min, newScale)
		newScale = min(self.scale_max, newScale)

		parent:SetScale(newScale)

		if self.mode_x == self.MODE_SIZE then
			-- Calculate new width
			local std_newFrameWidth = std_cursorX - self.std_oldLeft
			local newWidth = std_newFrameWidth/parent:GetEffectiveScale()
			newWidth = max(self.x_min, newWidth)
			newWidth = min(self.x_max, newWidth)

			parent:SetWidth(newWidth)
		end
		if self.mode_y == self.MODE_SIZE then
			-- Calculate new height
			local std_newFrameHeight = abs(std_cursorY - self.std_oldTop)
			local newHeight = std_newFrameHeight/parent:GetEffectiveScale()
			newHeight = max(self.y_min, newHeight)
			newHeight = min(self.y_max, newHeight)
			
			parent:SetHeight(newHeight)
		end

		-- We have all the data needed to find the new position of the parent.
		-- It must be recalculated because otherwise it will scale relative to where it is anchored to,
		-- instead of being relative to the parent's top left corner, which is what it is supposed to be.
		-- I don't remember why this calculation here works, so lets just leave it alone.
		-- Note that it will be re-re-calculated once we are done resizing.
		local newX = self.oldX * self.oldScale / newScale
		local newY = self.oldY * self.oldScale / newScale
		parent:ClearAllPoints()
		parent:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newX, newY)

		self:SizeUpdated()

	end,

	-- Override this to set settings, do updates, etc.
	SizeUpdated = function() end,
}






Classes:NewClass("FrameType")
{
	OnNewInstance = function(self, frameType)
		self.type = frameType
	end,

	InitializeConfig = function(self)
		for i, Property in ipairs(self.properties) do
			if not Property.frame then
				Classes[Property.cfgType]:NewWidget(Property)
			end
		end

		self.initializedConfig = true
	end,

	HideConfig = function(self)
		if not self.initializedConfig then
			return
		end

		for i, Property in ipairs(self.properties) do
			Property.frame:Hide()
		end
	end,

	ShowConfig = function(self)
		if not self.initializedConfig then
			error("not initialized")
		end

		for i, Property in ipairs(self.properties) do
			Property.frame:ClearAllPoints()

			if Property.width then
				Property.frame:SetWidth(Property.width)
			end

			Property.frame:HandlePosition()

			Property.frame:Show()

		end
	end,

	Refresh = function(self)
		if not self.initializedConfig then
			error("not initialized")
		end

		for i, Property in ipairs(self.properties) do
			Property.frame:Refresh()
		end
	end,
}


Classes:NewClass("Property")
{
	Get = function(self, ...)
		if self.get and FrameHelper.CF[self.get] then
			return safecallf(self.get, ...)
		end
	end,
	Set = function(self, ...)
		if self.set and FrameHelper.CF[self.set] then
			return safecallf(self.set, ...)
		end
	end,
}



FrameHelper.compositeTypes = {
	FontInstance = {
		EditBox = true,
		MessageFrame = true,
		ScrollingMessageFrame = true,
		FontString = true,
	},
	LayeredRegion = {
		FontString = true,
		Texture = true,
	},
	TextSettable = {
		FontString = true,
		EditBox = true,
		GameTooltip = true,
		Button = true,
	},
}

FrameHelper.properties = {

Region = {
	{	-- Parent
		name = "Parent",
		cfgType = "Config_EditBox_Frame",

		positions = {
			{"TOPLEFT", "$parent", "TOPLEFT", 15, -15},
			{"RIGHT", "$parent", "RIGHT", -15, 0},
		},

		width = 620,
		get = "GetParent",
		set = "SetParent",
	},

	{	-- Shown
		name = "Shown",
		position = {"TOPLEFT", "Parent", "BOTTOMLEFT", -7, -10},

		cfgType = "Config_CheckButton",
		get = "IsShown",
		set = "SetShown",
	},
	{	-- Alpha
		name = "Alpha",

		position = {"LEFT", "Shown", "RIGHT", 50, 0},
		width = 110,

		cfgType = "Config_Slider",
		get = "GetAlpha",
		set = "SetAlpha",

		min = 0,
		max = 1,
		step = 0.01,
	},

	{	-- Width
		name = "Width",
		cfgType = "Config_Slider",
		get = "GetWidth",
		set = "SetWidth",

		position = {"TOPLEFT", "Shown", "BOTTOMLEFT", 7, -19},
		width = 195,

		min = -math.huge,
		max = math.huge,
		step = 0.5,
		wheelStep = 1,
		init = function(self, frame)
			frame:SetMode(frame.MODE_ADJUSTING)
			frame:SetRange(50)
		end,
	},
	{	-- Height
		name = "Height",
		cfgType = "Config_Slider",
		get = "GetHeight",
		set = "SetHeight",

		position = {"LEFT", "Width", "RIGHT", 20, 0},
		width = 195,

		min = -math.huge,
		max = math.huge,
		step = 0.5,
		wheelStep = 1,
		init = function(self, frame)
			frame:SetMode(frame.MODE_ADJUSTING)
			frame:SetRange(50)
		end,
	},




	{	-- SetPoint
		name = "SetPoint",

		positions = {
			{"LEFT", "$parent", "LEFT", 5, 0},
			{"RIGHT", "$parent", "RIGHT", -5, 0},
			{"TOP", "Width", "BOTTOM", 0, -12},
		},

		cfgType = "Config_SetPoint",
	},
},

Frame = {
	--Attribute
	--Backdrop
	--BackdropBorderColor
	--BackdropColor
	--ClampRectInsets

	--DisableDrawLayer
	--EnableDrawLayer

	--"FrameStrata;",
	--HitRectInsets
	--"MaxResize;Config_Slider",
	--"MinResize;Config_Slider",
	--Depth





	{	-- Movable
		name = "Movable",
		
		positions = {
			{"LEFT", "$parent", "LEFT", 5, 0},
			{	-- Anchor to the first of these that is shown
				{"TOP", "JustifyH", "BOTTOM", 0, 3},
				{"TOP", "Text", "BOTTOM", 0, -5},
				{"TOP", "SetPoint", "BOTTOM", 0, -5},
			},
		},

		cfgType = "Config_CheckButton",
		get = "IsMovable",
		set = "SetMovable",
	},
	{	-- Resizable
		name = "Resizable",

		position = {"LEFT", "Movable", "RIGHT", 80, 0},

		cfgType = "Config_CheckButton",
		get = "IsResizable",
		set = "SetResizable",
	},
	{	-- ClampedToScreen
		name = "ClampedToScreen",
		text = "ClampedTo Screen",

		position = {"LEFT", "Resizable", "RIGHT", 80, 0},

		cfgType = "Config_CheckButton",
		get = "IsClampedToScreen",
		set = "SetClampedToScreen",
	},
	{	-- UserPlaced
		name = "UserPlaced",

		position = {"LEFT", "ClampedToScreen", "RIGHT", 80, 0},

		cfgType = "Config_CheckButton",
		get = "IsUserPlaced",
		set = "UserPlaced",
	},
	{	-- DontSavePosition
		name = "DontSavePosition",
		text = "DontSave Position",

		position = {"LEFT", "UserPlaced", "RIGHT", 80, 0},

		cfgType = "Config_CheckButton",
		get = "GetDontSavePosition",
		set = "SetDontSavePosition",
	},


	{	-- EnableKeyboard
		name = "EnableKeyboard",
		text = "Enable Keyboard",

		position = {"TOPLEFT", "Movable", "BOTTOMLEFT", 0, 0},

		cfgType = "Config_CheckButton",
		get = "IsKeyboardEnabled",
		set = "EnableKeyboard",
	},


	{	-- PropagateKeyboardInput
		name = "PropagateKeyboardInput",
		text = "Propagate KeyboardInput",

		position = {"LEFT", "EnableKeyboard", "RIGHT", 80, 0},

		cfgType = "Config_CheckButton",
		get = "GetPropagateKeyboardInput",
		set = "SetPropagateKeyboardInput",
	},

	{	-- EnableMouse
		name = "EnableMouse",
		
		position = {"LEFT", "PropagateKeyboardInput", "RIGHT", 80, 0},

		cfgType = "Config_CheckButton",
		get = "IsMouseEnabled",
		set = "EnableMouse",
	},
	{	-- EnableMouseWheel
		name = "EnableMouseWheel",
		text = "Enable MouseWheel",
		
		position = {"LEFT", "EnableMouse", "RIGHT", 80, 0},

		cfgType = "Config_CheckButton",
		get = "IsMouseWheelEnabled",
		set = "EnableMouseWheel",
	},
	{	-- EnableJoystick
		name = "EnableJoystick",
		text = "Enable Joystick",
		
		position = {"LEFT", "EnableMouseWheel", "RIGHT", 80, 0},

		cfgType = "Config_CheckButton",
		get = "IsJoystickEnabled",
		set = "EnableJoystick",
	},








	{	-- FrameLevel
		name = "FrameLevel",
		cfgType = "Config_Slider",
		get = "GetFrameLevel",
		set = "SetFrameLevel",

		position = {"LEFT", "Alpha", "RIGHT", 20, 0},
		width = 120,

		min = 0,
		max = math.huge,
		step = 1,
		init = function(self, frame)
			frame:SetMode(frame.MODE_ADJUSTING)
			frame:SetRange(10)
		end,
	},

	{	-- FrameStrata
		name = "FrameStrata",
		cfgType = "Config_DropDownMenu_SimpleSelect",
		get = "GetFrameStrata",
		set = "SetFrameStrata",

		position = {"LEFT", "Toplevel", "RIGHT", 46, -3},

		values = {
			"WORLD",
			"BACKGROUND",
			"LOW",
			"MEDIUM",
			"HIGH",
			"DIALOG",
			"FULLSCREEN_DIALOG",
			"TOOLTIP",
			"BLIZZARD",
		},
		init = function(self, frame)
			UIDropDownMenu_SetWidth(frame, 130)
		end,

		Set = function(self, strata)
			local f = FrameHelper.CF
			if f == WorldFrame then
				print("Changing WorldFrame's strata is generally a Very Bad Idea. So I won't let you.")
			else
				safecallf("SetFrameStrata", strata)
			end
		end,
	},


	--[[{	-- ID
		name = "ID",
		cfgType = "Config_Slider",
		get = "GetID",
		set = "SetID",

		min = -math.huge,
		max = math.huge,
		step = 1,
		init = function(self, frame)
			frame:SetMode(frame.MODE_ADJUSTING)
			frame:SetRange(10)
		end,
	},]]



	{	-- Toplevel
		name = "Toplevel",

		position = {"LEFT", "FrameLevel", "RIGHT", 10, 0},

		cfgType = "Config_CheckButton",
		get = "IsToplevel",
		set = "SetToplevel",
	},


	{	-- Scale
		name = "Scale",
		cfgType = "Config_Slider",
		get = "GetScale",
		set = "SetScale",

		position = {"LEFT", "Height", "RIGHT", 20, 0},
		width = 160,

		min = 0.01,
		max = math.huge,
		step = 0.001,
		wheelStep = 0.01,
		init = function(self, frame)
			frame:SetMode(frame.MODE_ADJUSTING)
			frame:SetRange(1)
		end,
	},
},

Button = {	
},

CheckButton = {	
},

Cooldown = {	
},

EditBox = {
},

TextSettable = {	-- Composite type
	{	-- Text
		name = "Text",
		get = "GetText",
		set = "SetText",
		cfgType = "Config_EditBox",
		positions = {
			{"LEFT", "$parent", "LEFT", 15, 0},
			{"RIGHT", "$parent", "RIGHT", -15, 0},
			{"TOP", "SetPoint", "BOTTOM", 0, -15},
		},
		init = function(self, frame)
			frame:SetMultiLine(true)
			frame:TT("Fontstring Text", "Press CTRL+Enter to insert a newline", 1, 1)
		end,
	},	
},

FontInstance = {	-- Composite type

	{
		name = "JustifyH",
		cfgType = "Config_DropDownMenu_SimpleSelect",
		get = "GetJustifyH",
		set = "SetJustifyH",

		positions = {
			{
				{"TOP", "Text", "BOTTOM", 0, -7},
				{"TOP", "SetPoint", "BOTTOM", 0, -7},
			},
			{"LEFT", "$parent", "LEFT", -3, 0},
		},

		values = {
			"LEFT",
			"CENTER",
			"RIGHT",
		},

		init = function(self, frame)
			frame.textPrefix = self.name .. ": "
			UIDropDownMenu_SetWidth(frame, 130)
		end,
	},

	{
		name = "JustifyV",
		cfgType = "Config_DropDownMenu_SimpleSelect",
		get = "GetJustifyV",
		set = "SetJustifyV",

		positions = {
			{"LEFT", "JustifyH", "RIGHT", -23, 0},
		},

		values = {
			"TOP",
			"MIDDLE",
			"BOTTOM",
		},

		init = function(self, frame)
			frame.textPrefix = self.name .. ": "
			UIDropDownMenu_SetWidth(frame, 130)
		end,
	},
},

LayeredRegion = {	-- Composite type
},

FontString = {

	{	-- WordWrap
		name = "WordWrap",
		
		positions = {
			{"LEFT", "JustifyV", "RIGHT", -10, 2},
		},

		cfgType = "Config_CheckButton",
		get = "CanWordWrap",
		set = "SetWordWrap",
	},

	{	-- NonSpaceWrap
		name = "NonSpaceWrap",
		text = "NonSpace Wrap",
		
		positions = {
			{"LEFT", "WordWrap", "RIGHT", 60, 0},
		},

		cfgType = "Config_CheckButton",
		get = "CanNonSpaceWrap",
		set = "SetNonSpaceWrap",
	},

	{	-- IndentedWordWrap
		name = "IndentedWordWrap",
		text = "Indented WordWrap",
		
		positions = {
			{"LEFT", "NonSpaceWrap", "RIGHT", 60, 0},
		},

		cfgType = "Config_CheckButton",
		get = "GetIndentedWordWrap",
		set = "SetIndentedWordWrap",

		init = function(self, frame)
			-- BUG ALERT:
			-- Blizzard's GetIndentedWordWrap and SetIndentedWordWrap are backwards.
			-- I submitted a bug report, so hopefully they will fix it soon.

			-- This code is here to detect if the bug has not yet been fixed,
			-- and if it hasn't, then switch the two methods around.
			-- We perform experiments on this button's label since it is an easy
			-- fontstring that we have access to that we don't care much about.

			-- if SetIndentedWordWrap is returning values, that means it is still bugged.
			if select("#", frame.text:SetIndentedWordWrap(false)) == 1  then
				self.get, self.set = self.set, self.get
			end
		end,
	},

},

GameTooltip = {
},

MessageFrame = {
},

ScriptObject = {
},

ScrollFrame = {
},

ScrollingMessageFrame = {
},

Slider = {	
},

StatusBar = {
},

Texture = {
	{
		name = "Texture",
		get = "GetTexture",
		set = "SetTexture",
		cfgType = "Config_EditBox",
		positions = {
			{"LEFT", "Alpha", "RIGHT", 10, 0},
			{"RIGHT", "$parent", "RIGHT", -15, 0}
		},
	},
},
}


for frameType, properties in pairs(FrameHelper.properties) do
	FrameHelper.properties[frameType] = Classes.FrameType:New(frameType)

	FrameHelper.properties[frameType].properties = properties

	for i, setting in pairs(properties) do
		if type(setting) == "string" then
			local setting, cfgType = strsplit(";", setting)
			properties[i] = {
				name = setting,
				cfgType = cfgType,
				get = "Get" .. setting,
				set = "Set" .. setting,
			}
		end

		properties[i] = Classes.Property:NewFromExisting(properties[i])
	end
end

for compositeType, types in pairs(FrameHelper.compositeTypes) do
	for frameType in pairs(types) do
		for k, v in ipairs(FrameHelper.properties[compositeType].properties) do 
			tinsert(FrameHelper.properties[frameType].properties, v)
		end
	end
end


local ScrollContainerHook_Hide = function(c) c.ScrollFrame:Hide() end
local ScrollContainerHook_Show = function(c) c.ScrollFrame:Show() end
local ScrollContainerHook_OnSizeChanged = function(c) c.ScrollFrame:Show() end
function FrameHelper:ConvertContainerToScrollFrame(container, exteriorScrollBarPosition, scrollBarXOffs, scrollBarSizeX)
    
    
    local ScrollFrame = CreateFrame("ScrollFrame", container:GetName() .. "ScrollFrame", container:GetParent(), "FrameHelper_ScrollFrameTemplate")
    
    -- Make the ScrollFrame clone the container's position and size
    local x, y = container:GetSize()
    ScrollFrame:SetSize(x, y)
    for i = 1, container:GetNumPoints() do
        ScrollFrame:SetPoint(container:GetPoint(i))
    end
    

    -- Make the container be the ScrollFrame's ScrollChild.
    -- Fix its size to take the full width.
    container:ClearAllPoints()
    ScrollFrame:SetScrollChild(container)
    container:SetSize(x, 1)
	
	if exteriorScrollBarPosition then
		ScrollFrame.ScrollBar:SetPoint("LEFT", ScrollFrame, "RIGHT", scrollBarXOffs or 0, 0)
	else
		ScrollFrame.ScrollBar:SetPoint("RIGHT", ScrollFrame, "RIGHT", scrollBarXOffs or 0, 0)
	end
	
	if scrollBarSizeX then
		ScrollFrame.ScrollBar:SetWidth(scrollBarSizeX)
	end
    
    container.ScrollFrame = ScrollFrame
    ScrollFrame.container = container

    hooksecurefunc(container, "Hide", ScrollContainerHook_Hide)
   	hooksecurefunc(container, "Show", ScrollContainerHook_Show)   
end

function FrameHelper:Load(frame)
	if frame:IsForbidden() then
		print("FrameHelper: Tried to load forbidden frame")
		return
	end

	FrameHelper_Editor:Show()

	E = FrameHelper_Editor
	M = E.Main
	M.frames = M.frames or {}

	self.CF = frame

	E.title:SetText(FrameHelper:GenerateFramePathString(frame))

	if self.CF then
		for _, FrameType in pairs(self.properties) do
			FrameType:HideConfig()
		end

		for _, FrameType in pairs(self.properties) do
			if frame:IsObjectType(FrameType.type) then
				FrameType:InitializeConfig()
				FrameType:ShowConfig()
			end
		end

		-- We do this again so that positioning gets handled correctly because
		-- the position of some frames depends on shown state of other frames
		for _, FrameType in pairs(self.properties) do
			if frame:IsObjectType(FrameType.type) then
				FrameType:ShowConfig()
				FrameType:Refresh()
			end
		end
	end
end


function FrameHelper.DD_LoadChild(DDframe)
	local region = UIDROPDOWNMENU_MENU_VALUE or FrameHelper.CF

	if type(region) == "table" then
		local regions = region

		if type(region[0]) == "userdata" then
			if not region:IsObjectType("Frame") then
				return
			end

			regions = {region:GetChildren()}

			if (region:GetRegions() and #regions > 0) then
				tinsert(regions, true)
			end

			for i, region in FrameHelper:Vararg(region:GetRegions()) do
				tinsert(regions, region)
			end
		end

		local offset = 0
		for i, region in pairs(regions) do
			if region == true then
				offset = i
				AddDropdownSpacer()
			else
				i = i - offset
				local info = UIDropDownMenu_CreateInfo()

				info.func = FrameHelper.DD_LoadChild_Click
				info.arg1 = region

				local name
				if region:GetName() then
					name = region:GetName()
				else
					name = FrameHelper:GenerateFramePathString(region)
				end
				local parent = region:GetParent()
				if parent then
					for _, method in FrameHelper:Vararg(
						"GetNormalTexture",
						"GetPushedTexture",
						"GetHighlightTexture",
						"GetCheckedTexture",
						"GetDisabledCheckedTexture",

						"GetFontString",

						"GetStatusBarTexture",
						"GetColorValueTexture",
						"GetColorValueThumbTexture",
						"GetColorWheelTexture",
						"GetColorWheelThumbTexture"
					) do
						if parent[method] and parent[method](parent) == region then
							name = "$parent:" .. method .. "()"
							break
						end
					end

					if region:GetParent():GetName() then
						name = gsub(name, region:GetParent():GetName(), "$parent")
					end
				end

				info.text = "<" .. i .. " " .. region:GetObjectType() .. "> " .. name
				info.value = region
				info.hasArrow = region:IsObjectType("Frame") and (region:GetChildren() or region:GetRegions())
				info.notCheckable = true

				UIDropDownMenu_AddButton_Scrolled(info, UIDROPDOWNMENU_MENU_LEVEL)
			end
		end
	end
end

function FrameHelper.DD_LoadChild_Click(button, region)
	FrameHelper:Load(region)
end


function FrameHelper:Refresh()

	for _, FrameType in pairs(self.properties) do
		if self.CF:IsObjectType(FrameType.type) then
			FrameType:Refresh()
		end
	end
end

FrameHelper:SetScript("OnUpdate", function()
	if E and E:IsVisible() and FrameHelper.CF then
		FrameHelper:Refresh()
	end
end)






---------------------------------
-- Tooltips
---------------------------------

local function TTOnEnter(self)
	if (self.__title or self.__text) then
		FrameHelper:TT_Anchor(self)
		if self.__ttMinWidth then
			GameTooltip:SetMinimumWidth(self.__ttMinWidth)
		end
		GameTooltip:AddLine(get(self.__title, self), HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, false)
		local text = get(self.__text, self)
		if text then
			GameTooltip:AddLine(text, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, not self.__noWrapTooltipText)
		end
		GameTooltip:Show()
	end
end
local function TTOnLeave(self)
	GameTooltip:Hide()
end

function FrameHelper:TT_Anchor(f)
	GameTooltip:SetOwner(f, "ANCHOR_NONE")
	GameTooltip:SetPoint("TOPLEFT", f, "BOTTOMRIGHT", 0, 0)
end

function FrameHelper:TT(f, title, text, actualtitle, actualtext, showchecker)
	-- setting actualtitle or actualtext true cause it to use exactly what is passed in for title or text as the text in the tooltip
	-- if these variables arent set, then it will attempt to see if the string is a global variable (e.g. "MAXIMUM")
		
	f.__title = title
	f.__text = text
	
	f.__ttshowchecker = showchecker

	if not f.__ttHooked then
		f.__ttHooked = 1
		f:HookScript("OnEnter", TTOnEnter)
		f:HookScript("OnLeave", TTOnLeave)
	else
		if not f:GetScript("OnEnter") then
			f:HookScript("OnEnter", TTOnEnter)
		end
		if not f:GetScript("OnLeave") then
			f:HookScript("OnLeave", TTOnLeave)
		end
	end
end

function FrameHelper:TT_Copy(src, dest)
	FrameHelper:TT(dest, src.__title, src.__text, 1, 1, src.__ttshowchecker)
end

function FrameHelper:TT_Update(f)
	if f:IsMouseOver() and f:IsVisible() then
		f:GetScript("OnLeave")(f)
		if not f.IsEnabled or f:IsEnabled() or f:GetMotionScriptsWhileDisabled() then
			f:GetScript("OnEnter")(f)
		end
	end
end



SLASH_FRAMEHELPER1 = "/fh"
SLASH_FRAMEHELPER2 = "/framehelper"
function SlashCmdList.FRAMEHELPER()
	if GetMouseFocus() then
		FrameHelper:Load(GetMouseFocus())
	end
end 