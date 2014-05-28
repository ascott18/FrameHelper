

local MAJOR, MINOR = "ScrollableUIDropDownMenus-1.0", 1
local SUID, oldminor = LibStub:NewLibrary(MAJOR, MINOR)

if not SUID then return end



local DEFAULT_BUTTONS_MAX = 20
local OFFSETS = setmetatable({}, {__index = function() return 0 end})

local dummy = setmetatable({}, {__index = function() return 0 end})
local offsets = OFFSETS

local function RefreshLevel(level)
	level = level or UIDROPDOWNMENU_MENU_LEVEL
	local listFrame = _G["DropDownList"..level]
	if not listFrame:IsShown() then
		if level == 1 then
			return
		end
		
		level = level - 1
		listFrame = _G["DropDownList"..level]
	end
	
	
	-- if self.hasArrow then
	if listFrame and listFrame:IsShown() then
		
		local _, anchor, _, x, y = listFrame:GetPoint()
		
		-- Save things that are going to get reset when we hide the menu.
		-- We will restore them in a second.
		OFFSETS = dummy
		local width = listFrame.__scrollableWidth or 0
		
		CloseDropDownMenus(level)
		
		-- Restore things that got reset by hiding the dropdown menu.
		listFrame.__scrollableWidth = width
		OFFSETS = offsets
		
		listFrame.__scrollableShouldRunInitializeHook = true
		local wasNoResize = listFrame.noResize
		listFrame.noResize = true
		
		if level == 1 then
			ToggleDropDownMenu(level, nil, UIDROPDOWNMENU_OPEN_MENU, anchor, x, y, UIDROPDOWNMENU_OPEN_MENU.menuList, nil)
		else
			local button = anchor
			
			ToggleDropDownMenu(level, button.value, nil, nil, nil, nil, button.menuList, button)
		end
		
		listFrame.noResize = wasNoResize
		listFrame.__scrollableShouldRunInitializeHook = nil
	end
end

local function SetLevelWidth(level, width)
	for i=1, UIDROPDOWNMENU_MAXBUTTONS do
		button = _G["DropDownList"..level.."Button"..i]
		button:SetWidth(width)
	end
	_G["DropDownList"..level]:SetWidth(width + 25)
end



local function OnMouseWheel_Wrapper(self, delta)
	SUID.listFrame_OnMouseWheel(self:GetParent(), delta)
end
local function hookMouseWheel(button)
	if not button.__scrollableHookedMouseWheel then
		button:EnableMouseWheel(true)
		button:HookScript("OnMouseWheel", OnMouseWheel_Wrapper)
		button.__scrollableHookedMouseWheel = 1
	end    
end


local function MakeScrollBar(listFrame)
	local scrollBar = CreateFrame("Frame", "$parent__ScrollableScrollBar", listFrame, "ScrollableUIDropDownMenus_ScrollBarTemplate")
	listFrame.__scrollableScrollBar = scrollBar

	scrollBar.listFrame = listFrame

	scrollBar.Thumb.scrollBar = scrollBar
	scrollBar.Thumb.listFrame = listFrame

	-- There is a very deliberate reason that the thumb gets parented to UIParent.
	-- When the listFrame hides during an update, it will also hide the scrollbar and the thumb,
	-- which causes OnDragStop to never fire. If that happens,
	-- the slider is stuck to the user's cursor forever. And that's bad. So, what we do is very very hackish
	-- we parent the thumb to UIParent so that it does not hide automatically when the scrollbar hides.
	-- We set a flag, scrollBar.canHideThumb to determine if the thumb should be hidden in the scrollBar's OnHide script.
	-- This flag is set to false when calling RefreshLevel() from inside SetScroll() so that the thumb doesn't get hidden while scrolling.,
	-- The thumb should normally be properly hidden whenever the dropdown is hiding for normal reasons.
	scrollBar.Thumb:SetParent(UIParent)
	scrollBar.Thumb:SetFrameStrata("FULLSCREEN_DIALOG")

	return scrollBar
end

local function ShouldShowScrollBar(listFrame)
	if listFrame.__scrollableIndex and listFrame.__scrollableIndex > (UIDROPDOWNMENU_OPEN_MENU.maxButtons or DEFAULT_BUTTONS_MAX) then
		return true
	end
end


---------------------
-- Hooks/Scripts
---------------------

local function SetScroll(listFrame, offset)
	if not listFrame.__scrollableScrollBar then
		return
	end
	
	local level = listFrame:GetID()
	
	local maxButtons = (UIDROPDOWNMENU_OPEN_MENU.maxButtons or DEFAULT_BUTTONS_MAX)

	offset = max(offset, 0)
	offset = min(offset, (listFrame.__scrollableIndex or 0) - maxButtons)

	if OFFSETS[level] ~= offset then
		OFFSETS[level] = offset

		listFrame.__scrollableScrollBar.canHideThumb = false
		RefreshLevel(level)

		listFrame.__scrollableScrollBar.canHideThumb = true
	end
end

function SUID.listFrame_OnMouseWheel(listFrame, delta)
	local level = listFrame:GetID()

	local numButtonsVisible = (UIDROPDOWNMENU_OPEN_MENU.maxButtons or DEFAULT_BUTTONS_MAX)

	SetScroll(listFrame, OFFSETS[level] - delta*max(1, ceil(numButtonsVisible/3 - 1)))
end

function SUID.ScrollThumb_OnDragStart(self)
	local listFrame = self.listFrame

	local _
	self.IsScrolling = true
	self.scrollStartOffset = OFFSETS[listFrame:GetID()]
	_, self.startY = GetCursorPosition()
	self:SetButtonState("PUSHED")
	self:LockHighlight()
end
function SUID.ScrollThumb_OnDragStop(self)
	self.IsScrolling = false
	self:SetButtonState("NORMAL")
	self:UnlockHighlight()
end
function SUID.ScrollThumb_OnUpdate(self)
	local listFrame = self.listFrame

	local totalNumButtons = listFrame.__scrollableIndex


	local numButtonsVisible = (UIDROPDOWNMENU_OPEN_MENU.maxButtons or DEFAULT_BUTTONS_MAX)
	local pixelsPerButton = self.scrollBar:GetHeight() / numButtonsVisible

	local currentScroll = OFFSETS[listFrame:GetID()]
	if self.IsScrolling then
		local _, currentY = GetCursorPosition()
		local delta = -(currentY - self.startY) / (self.scrollBar:GetHeight() / totalNumButtons)  / self:GetEffectiveScale() 
		

		delta = floor(delta + 0.5)

		--currentScroll = currentScroll + delta
		
		SetScroll(listFrame, self.scrollStartOffset + delta)
		self.IsScrolling = true

		UIDropDownMenu_StopCounting(listFrame)
	end

	local currentScroll = OFFSETS[listFrame:GetID()]

	self.percentage = numButtonsVisible/totalNumButtons

	self:SetHeight(max(self.percentage*self.scrollBar:GetHeight(), 15))


	self:SetPoint("TOP", self.scrollBar, "TOP", 0, -(currentScroll*self.percentage*pixelsPerButton))
	self:SetFrameLevel(self.scrollBar:GetFrameLevel() + 1)
	self:SetScale(self.scrollBar:GetEffectiveScale()/self:GetEffectiveScale())
end

function SUID.ScrollBar_OnMouseWheel(self, delta)
	SUID.listFrame_OnMouseWheel(self.listFrame, delta)
end
function SUID.ScrollBar_OnMouseDown(self)
	local delta
	local _, y = GetCursorPosition()
	if self.Thumb:GetBottom()*self:GetEffectiveScale() > y then
		delta = -1
	elseif y > self.Thumb:GetTop()*self:GetEffectiveScale() then
		delta = 1
	end

	
	SUID.listFrame_OnMouseWheel(self, delta)
end




function SUID.UIDropDownMenu_OnHide(listFrame)
	OFFSETS[listFrame:GetID()] = 0
	listFrame.__scrollableIndex = 0
	listFrame.__scrollableWidth = 0
	if listFrame.__scrollableScrollBar then
		--listFrame.__scrollableScrollBar:Hide()
	end
end

function SUID.UIDropDownMenu_OnUpdate(listFrame)
	if listFrame:IsMouseOver() and ShouldShowScrollBar(listFrame) then
		(listFrame.__scrollableScrollBar or MakeScrollBar(listFrame)):Show()
	elseif listFrame.__scrollableScrollBar and not listFrame.__scrollableScrollBar.Thumb.IsScrolling then
		listFrame.__scrollableScrollBar:Hide()
	end
end

function SUID.UIDropDownMenu_Initialize(frame, initFunction, displayMode, level, menuList)
	if level then
		local listFrame = _G["DropDownList"..level];
		if listFrame.__scrollableShouldRunInitializeHook then
			SetLevelWidth(level, listFrame.__scrollableWidth)
			listFrame.shouldRefresh = false
		end
	end
end

function SUID.ToggleDropDownMenu(level)
	level = level or 1

	local listFrame = _G["DropDownList"..level]

	if listFrame.__scrollableQueueTest and not listFrame.__scrollableTestingWidth then
		listFrame.__scrollableQueueTest = nil
		listFrame.__scrollableTestingWidth = true
		listFrame.__scrollableAddedInvalidButtons = nil

		RefreshLevel(listFrame:GetID())

		listFrame.__scrollableTestingWidth = false
		
		if listFrame.__scrollableAddedInvalidButtons then
			listFrame.__scrollableAddedInvalidButtons = nil
			RefreshLevel(listFrame:GetID())
		end
	end
end

if not oldminor then
	hooksecurefunc("UIDropDownMenu_OnHide", function(...)
		SUID.UIDropDownMenu_OnHide(...)
	end)

	hooksecurefunc("UIDropDownMenu_OnUpdate", function(...)
		SUID.UIDropDownMenu_OnUpdate(...)
	end)

	hooksecurefunc("UIDropDownMenu_Initialize", function(...)
		SUID.UIDropDownMenu_Initialize(...)
	end)

	hooksecurefunc("ToggleDropDownMenu", function(...)
		SUID.ToggleDropDownMenu(...)
	end)
end


-- Public

function UIDropDownMenu_AddButton_Scrolled(info, level)
	if not level then
		level = 1
	end
	
	local listFrame = _G["DropDownList"..level]
	
	local index = listFrame.__scrollableIndex or 0
	listFrame.__scrollableIndex = index + 1
		
	local maxButtons = (UIDROPDOWNMENU_OPEN_MENU.maxButtons or DEFAULT_BUTTONS_MAX)
	local isOutOfRange = index < OFFSETS[level] or index >= OFFSETS[level] + maxButtons


	if not listFrame.__scrollableTestingWidth and isOutOfRange then
		return
	else
		if listFrame.__scrollableTestingWidth and isOutOfRange then
			listFrame.__scrollableAddedInvalidButtons = true
		end

		UIDropDownMenu_AddButton(info, level)
		local button = _G[listFrame:GetName().."Button"..listFrame.numButtons]
		hookMouseWheel(button)
		
		if button:IsShown() then
			width = UIDropDownMenu_GetButtonWidth(button)
			if (listFrame.__scrollableWidth or 0) == 0 then
				listFrame.__scrollableQueueTest = true
			end
			if width > (listFrame.__scrollableWidth or 0) then
				listFrame.__scrollableWidth = max(1, width)
			end
		end
	end
end
