-- Addon originally named DailyChecklist by astoll and goofdad, renamed DailyToDo by Ærixalimar, continued by Eltreum using fixes by Maaggel

-- Create main object and load AceConsole so we can use console commands
DailyToDo = LibStub("AceAddon-3.0"):NewAddon("DailyToDo", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

-- Create empty table for localization data
DailyToDo.localize = {}
DailyToDo.data = {}

-- Create our addon message prefix
local PREFIX = "[DailyToDo]"

-- Use variables for numberic weekdays, matches return from date(%w) + 1
local SUNDAY = 1
local MONDAY = 2
local TUESDAY = 3
local WEDNESDAY = 4
local THURSDAY = 5
local FRIDAY = 6
local SATURDAY = 7

local expandNormalTexture = "Interface\\BUTTONS\\UI-PlusButton-Up.blp"
local expandPushedTexture = "Interface\\BUTTONS\\UI-PlusButton-Down.blp"
local contractNormalTexture = "Interface\\BUTTONS\\UI-MinusButton-Up.blp"
local contractPushedTexture = "Interface\\BUTTONS\\UI-MinusButton-Down.blp"
local expandHighlightTexture = "Interface\\BUTTONS\\UI-PlusButton-Hilight.png"

local intervalConverter = {600, 1200, 1800, 3600}

-- Create stack/pools for unused, previously created interface objects
DailyToDo.checklistFrameCheckboxPool = {}
DailyToDo.checklistFrameTextPool = {}
DailyToDo.checklistFrameHeaderExpandPool = {}
DailyToDo.checklistFrameHeaderTextPool = {}
DailyToDo.checklistFrameHeaderCheckboxPool = {}

-- Create color variables
DailyToDo.selectedEntryColor = "|cffFFB90F"
DailyToDo.managerPanelHeight = 300

DailyToDo.timerId = nil
DailyToDo.currentDay = nil
DailyToDo.selectedManagerFrameText = nil
DailyToDo.selectedManagerFrameList = nil
DailyToDo.ShowObjectivesWindow = nil

-- Create our minimap icon
DailyToDo.DailyToDoLDB = LibStub("LibDataBroker-1.1"):NewDataObject("DailyToDoDO", {
										 type = "data source",
										 text = "DailyToDo",
										 icon = "Interface\\RAIDFRAME\\ReadyCheck-Ready.blp",
										 OnTooltipShow = function(tt)
										    tt:AddLine("DailyToDo Continued")
											tt:AddLine(" ")
										    tt:AddLine("Left Click to toggle frame")
										    tt:AddLine("Right Click to open options, or type /todo")
										 end,
										 OnClick = function(self, button) DailyToDo:HandleIconClick(button) end,
									     })
DailyToDo.icon = LibStub("LibDBIcon-1.0")
LibDBIcon = LibStub("LibDBIcon-1.0")


-- Set our database default values
DailyToDo.defaults = {
   profile = {
      version = "1.0",
      icon = {
	 hide = false,
      },
      framePosition = {
	 x = 0,
	 y = 0,
	 anchor = "CENTER",
	 hidden = false,
      },
      locked = false,
      hideObjectives = false,
      showListHeaders = true,
      hideCompleted = false,
      timestamp = nil,
      dailyResetTime = 1,
      weeklyResetDay = 3,
      resetPollInterval = 5,
      lists = {
	 [1] = {
	    name = "Default",
	    expanded = true,
	    entries = {
	    },
	 }
      },
   },
}

-- Initialize addon, called directly after the addon is fully loaded
function DailyToDo:OnInitialize()
   -- Create our database with default values
   self.db = LibStub("AceDB-3.0"):New("DailyToDoDB", self.defaults);
   self.db.RegisterCallback(self, "OnProfileChanged", "RefreshEverything")
   self.db.RegisterCallback(self, "OnProfileCopied", "RefreshEverything")
   self.db.RegisterCallback(self, "OnProfileReset", "RefreshEverything")
   
   -- Register our minimap icon
   self.icon:Register("DailyToDoDO", self.DailyToDoLDB, self.db.profile.icon)
   
   -- Register our addon message prefix
   C_ChatInfo.RegisterAddonMessagePrefix ("PREFIX")
   
   -- Register chat commands
   self:RegisterChatCommand("todo", "HandleChatMessageCommands")
   self:RegisterChatCommand("DailyToDo", "HandleChatMessageCommands")
end

function DailyToDo:UpdateVisibility()
   self:UpdateVisibilityOnChecklistFrame(self.db.profile.hideCompleted)
   self:UpdateEntryPositionsOnChecklistFrame()
   self:UpdateVisibilityForChecklistFrame()
   self:UpdateVisibilityForIcon(self.db.profile.icon.hide)
end

function DailyToDo:HandleChatMessageCommands(msg)
   local command, text = msg:match("(%S+)%s*(%S*)") 
   if command == "show" then
      if text == "icon" then
	 self.db.profile.icon.hide = false
      else 
	 if text == "completed" then
	    self.db.profile.hideCompleted = false
	 else
	    self.db.profile.framePosition.hidden = false
	 end
      end
      self:UpdateVisibility()
   elseif command == "hide" then
      if text == "icon" then
	 self.db.profile.icon.hide = true
      else
	 if text == "completed" then
	    self.db.profile.hideCompleted = true
	 else
	    self.db.profile.framePosition.hidden = true
	 end
      end
      self:UpdateVisibility()
   elseif command == "toggle" then
      if text == "icon" then
	 self.db.profile.icon.hide = not self.db.profile.icon.hide
      else
	 if text == "completed" then
	    self.db.profile.hideCompleted = not self.db.profile.hideCompleted
	 else
	    self.db.profile.framePosition.hidden = not self.db.profile.framePosition.hidden
	 end
      end
      self:UpdateVisibility()
   elseif command == "lock" then
      self.db.profile.locked = true
   elseif command == "unlock" then
      self.db.profile.locked = false
   elseif command == "check" and text == "time" then
      self:UpdateForNewDateAndTime()
   elseif command == "options" then
      InterfaceOptionsFrame_OpenToCategory(self.checklistOptionsFrame)
	  InterfaceOptionsFrame_OpenToCategory(self.checklistOptionsFrame)
   elseif command == "manager" then
      InterfaceOptionsFrame_OpenToCategory(self.checklistManagerFrame)
	  InterfaceOptionsFrame_OpenToCategory(self.checklistManagerFrame)
   elseif command == "profiles" then
      InterfaceOptionsFrame_OpenToCategory(self.checklistProfilesFrame)
	  InterfaceOptionsFrame_OpenToCategory(self.checklistProfilesFrame)
   elseif command == "help" then
      self:Print("\"/todo show\" : shows checklist")
      self:Print("\"/todo hide\" : hides checklist")
      self:Print("\"/todo show icon\" : shows minimap icon (requires ui restart to take effect)")
      self:Print("\"/todo hide icon\" : hides minimap icon (requires ui restart to take effect)")
      self:Print("\"/todo lock\" : locks checklist position")
      self:Print("\"/todo unlock\" : unlocks checklist position")
      self:Print("\"/todo check time\" : check if entries should be reset")
      self:Print("\"/todo show completed\" : show completed entries")
      self:Print("\"/todo hide completed\" : hide completed entries")
      self:Print("\"/todo options\" : opens options dialog")
      self:Print("\"/todo profiles\" : opens profiles dialog")
      self:Print("\"/todo manager\" : opens manager dialog")
   else
      self:Print("Usage: \"/todo <command> <identifier>\"")
      self:Print("Type: \"/todo help\" for a list of commands")
   end
end

-- Called when the addon is enabled
function DailyToDo:OnEnable()

	--check if its retail or classic
   if select(4,GetBuildInfo()) > 90000 then
	self.ShowObjectivesWindow = ObjectiveTrackerFrame.Show
	ObjectiveTrackerFrame.Show = self.ObjectiveTrackerFrameShow
   end
   
   self:CheckCurrentDateAndTime(true)
   
   self:ResetTimer()
   
   -- Initialize number of entries that will fit in interface options panel
   self.maxEntries = math.floor((InterfaceOptionsFramePanelContainer:GetHeight() - self.managerPanelHeight) / 25)
   
   -- Create options frame
   self:CreateManagerFrame()
   
   -- Create checklist frame
   self:CreateChecklistFrame()

--   ObjectiveTrackerFrame.Show=function() end
end

-- Called when timer interval changes
function DailyToDo:ResetTimer()
   -- Remove old timer
   if self.timerId then
      self:CancelTimer(self.timerId)
      self.timerId = nil
   end
   
   if self.db.profile.resetPollInterval ~= 1 then
      self.timerId = self:ScheduleRepeatingTimer("UpdateForNewDateAndTime", intervalConverter[self.db.profile.resetPollInterval - 1])
   end
end

-- Updates checklist entries based on new time and/or day
function DailyToDo:UpdateForNewDateAndTime()
   if DailyToDo:CheckCurrentDateAndTime(false) then
      DailyToDo:UpdateEntryPositionsOnChecklistFrame()
   end
   DailyToDo:UpdateEntryCompletedOnChecklistFrame()
   DailyToDo:UpdateVisibilityOnChecklistFrame(self.db.profile.hideCompleted)
end

-- Resets completed quests given the current day and time
function DailyToDo:CheckCurrentDateAndTime(firstTime)
   -- Save current weekday
   local oldDay = self.currentDay
   local entriesChanged = false
   self.currentDay = tonumber(date("%w")) + 1
   local currentListReset = false
   local currentTime = tonumber(date("%Y%m%d%H%M%S"))
   
   -- If first time starting application
   if not self.db.profile.timestamp then
      self.db.profile.timestamp = tonumber(date("%Y%m%d")) * 1000000
   end
   
   -- Set reset time to user selected time on current day
   local resetTime = tonumber(date("%Y%m%d")) * 1000000 + (self.db.profile.dailyResetTime - 1) * 10000
   
   -- Check if we have completed quests for the current day on this character
   if self.db.profile.timestamp <  resetTime and (currentTime > resetTime or (currentTime - 1000000) > self.db.profile.timestamp) then
      -- Has not been opened yet today, should reset completed quests 
      for listId, list in ipairs(self.db.profile.lists) do
	 for entryId, entry in ipairs(list.entries) do
	    if not entry.manual then
	       if not entry.weekly then
		  entry.completed = false
		  if not firstTime and self.checklistFrame.lists[listId] and self.checklistFrame.lists[listId].entries[entryId] and self.checklistFrame.lists[listId].entries[entryId].checkbox then
		     self.checklistFrame.lists[listId].entries[entryId].checkbox:SetChecked(false)
		  end
		  currentListReset = true
	       else 
		  if self.db.profile.weeklyResetDay == self.currentDay then
		     entry.completed = false
		     if not firstTime and self.checklistFrame.lists[listId] and self.checklistFrame.lists[listId].entries[entryId] and self.checklistFrame.lists[listId].entries[entryId].checkbox then
			self.checklistFrame.lists[listId].entries[entryId].checkbox:SetChecked(false)
		     end
		     currentListReset = true
		  end
	       end
	    end
	 end
	 if currentListReset then
	    list.completed = false
	    if not firstTime and self.checklistFrame.lists[listId] and self.checklistFrame.lists[listId].checkbox then
	       self.checklistFrame.lists[listId].checkbox:SetChecked(false)
	    end
	    currentListReset = false
	 end
      end
      -- Update timestamp to future, we already updated today
      self.db.profile.timestamp = resetTime
   end
   
   -- Check if entries should be removed or added due to day change
   if not firstTime and oldDay ~= self.currentDay then
      for listId, list in ipairs(self.db.profile.lists) do
	 for entryId, entry in ipairs(list.entries) do
	    if entry.days[oldDay] ~= entry.days[self.currentDay] then
	       self:UpdateEntryOnChecklistFrame(listId, entryId, entry.checked)
	       entriesChanged = true
	    end
	 end
      end
   end
   
   return entriesChanged
end

-- Create the main checklist frame 
function DailyToDo:CreateChecklistFrame()
   self.checklistFrame = CreateFrame("Frame","ChecklistFrame",UIParent)
   self.checklistFrame:SetMovable(true)
   self.checklistFrame:EnableMouse(true)
   self.checklistFrame:SetClampedToScreen(true)
   self.checklistFrame:RegisterForDrag("LeftButton")
   self.checklistFrame:SetScript("OnDragStart", function(frame)
				    if not DailyToDo.db.profile.locked then 
				       frame:StartMoving() 
				    end
   end)
   self.checklistFrame:SetScript("OnDragStop", function(frame)
				    frame:StopMovingOrSizing()
				    DailyToDo.db.profile.framePosition.anchor, _, _, DailyToDo.db.profile.framePosition.x, DailyToDo.db.profile.framePosition.y = frame:GetPoint()
   end)
   self.checklistFrame:SetHeight(200)
   self.checklistFrame:SetWidth(200)
   self.checklistFrame:SetAlpha(1.0)
   
   
   DailyToDo:UpdateVisibilityForChecklistFrame()
   
   -- Create empty array to store quest list buttons
   self.checklistFrame.lists = {}
   
   -- Create the title text
   local title = self.checklistFrame:CreateFontString("TitleText", nil, "GameFontNormalLarge")
   title:SetText("|cffFFB90FThings To Do|r")
   title:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", -4, 0)
   title:Show()
   
   self:CreateChecklistFrameElements()
   
   self.checklistFrame:SetHeight(32)
   self.checklistFrame:SetPoint(self.db.profile.framePosition.anchor, nil, self.db.profile.framePosition.anchor, self.db.profile.framePosition.x, self.db.profile.framePosition.y-16)
   
end

function DailyToDo:RemoveChecklistFrameElements()
   local listId = table.getn(self.checklistFrame.lists)
   while listId > 0 do
      self:RemoveListFromChecklistFrame(listId)
      listId = listId - 1
   end
end

function DailyToDo:CreateChecklistFrameElements()
   
   -- Adjust offset for beginning of list
   local offset = 18
   
   -- Create entry tracking frame contents
   for listId, list in pairs(self.db.profile.lists) do
      
      -- Create empty table for list
      self.checklistFrame.lists[listId] = {}
      self.checklistFrame.lists[listId].entries = {}
      
      -- Determine if we should show list elements
      local show = true
      
      if self.db.profile.showListHeaders then
	 
	 if not list.completed or not self.db.profile.hideCompleted then
	    -- Create header expand button
	    if table.getn(self.checklistFrameHeaderExpandPool) > 0 then
	       self.checklistFrame.lists[listId].expand = self.checklistFrameHeaderExpandPool[1]
	       table.remove(self.checklistFrameHeaderExpandPool, 1)
	    else
	       self.checklistFrame.lists[listId].expand = CreateFrame("Button", nil, self.checklistFrame, "UICheckButtonTemplate")
	       self.checklistFrame.lists[listId].expand:SetWidth(12)
	       self.checklistFrame.lists[listId].expand:SetHeight(12)
	       self.checklistFrame.lists[listId].expand:SetScript("OnClick", function(self)
								     DailyToDo:ToggleChecklistFrameListExpand(self)
								 end)
	       self.checklistFrame.lists[listId].expand:SetHighlightTexture(expandHighlightTexture)
	    end
	    
	    if self.db.profile.lists[listId].expanded then
	       self.checklistFrame.lists[listId].expand:SetNormalTexture(contractNormalTexture)
	       self.checklistFrame.lists[listId].expand:SetPushedTexture(contractPushedTexture)
	    else
	       self.checklistFrame.lists[listId].expand:SetNormalTexture(expandNormalTexture)
	       self.checklistFrame.lists[listId].expand:SetPushedTexture(expandPushedTexture)
	    end
	    
	    self.checklistFrame.lists[listId].expand:SetPoint("TOPLEFT", 1, -offset - 1)
	    self.checklistFrame.lists[listId].expand.listId = listId
	    self.checklistFrame.lists[listId].expand:Show()
	    
	    -- Create header checkbox
	    if table.getn(self.checklistFrameHeaderCheckboxPool) > 0 then
	       self.checklistFrame.lists[listId].checkbox = self.checklistFrameHeaderCheckboxPool[1]
	       table.remove(self.checklistFrameHeaderCheckboxPool, 1)
	    else
	       -- Create checkbox for list
	       self.checklistFrame.lists[listId].checkbox = CreateFrame("CheckButton", nil, self.checklistFrame, "UICheckButtonTemplate")
	       self.checklistFrame.lists[listId].checkbox:SetWidth(16)
	       self.checklistFrame.lists[listId].checkbox:SetHeight(16)
	       self.checklistFrame.lists[listId].checkbox:SetChecked(false)
	       self.checklistFrame.lists[listId].checkbox:SetScript("OnClick", function(self)
								       DailyToDo:ToggleChecklistFrameListCheckbox(self)
								   end)
	    end
	    
	    -- Change checkbox properties to match the new list
	    self.checklistFrame.lists[listId].checkbox:SetPoint("TOPLEFT", 12, -offset + 1)
	    self.checklistFrame.lists[listId].checkbox.listId = listId
	    self.checklistFrame.lists[listId].checkbox:SetChecked(self.db.profile.lists[listId].completed)
	    self.checklistFrame.lists[listId].checkbox:Show()
	    
	    -- Check if we can reuse a label
	    if table.getn(self.checklistFrameHeaderTextPool) > 0 then
	       self.checklistFrame.lists[listId].headerText = self.checklistFrameHeaderTextPool[1]
	       table.remove(self.checklistFrameHeaderTextPool, 1)
	    else
	       self.checklistFrame.lists[listId].headerText = self.checklistFrame:CreateFontString("ListHeader"..listId, nil, "GameFontNormal")
	    end
	    
	    -- Change header text for new entry
	    self.checklistFrame.lists[listId].headerText:SetText(self.db.profile.lists[listId].name)
	    self.checklistFrame.lists[listId].headerText:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", 30, -offset - 1)
	    self.checklistFrame.lists[listId].headerText:Show()
	    
	    offset = offset + 18
	    
	    if not self.db.profile.lists[listId].expanded then
	       show = false
	    end
	 else
	    show = false
	 end
      end
      
      for entryId, entry in pairs(list.entries) do
	 
	 if entry.checked and entry.days[self.currentDay] then
	    self:CreateEntryInChecklistFrame(listId, entryId, offset)
	    
	    if not show or (entry.completed and self.db.profile.hideCompleted) then
	       self.checklistFrame.lists[listId].entries[entryId].checkbox:Hide()
	       self.checklistFrame.lists[listId].entries[entryId].headerText:Hide()
	    else
	       offset = offset + 16
	    end
	 end
      end
   end
end

function DailyToDo:CreateEntryInChecklistFrame(listId, entryId, offset)
   -- Create empty table for new entry
   self.checklistFrame.lists[listId].entries[entryId] = {}
   
   local horizontalOffset = 7
   
   if self.db.profile.showListHeaders then
      horizontalOffset = horizontalOffset + 12
   end
   
   -- Check if we can reuse a checkbox
   if table.getn(self.checklistFrameCheckboxPool) > 0 then
      self.checklistFrame.lists[listId].entries[entryId].checkbox = self.checklistFrameCheckboxPool[1]
      table.remove(self.checklistFrameCheckboxPool, 1)
   else
      -- Create checkbox for quest
      self.checklistFrame.lists[listId].entries[entryId].checkbox = CreateFrame("CheckButton", nil, self.checklistFrame, "UICheckButtonTemplate")
      self.checklistFrame.lists[listId].entries[entryId].checkbox:SetWidth(16)
      self.checklistFrame.lists[listId].entries[entryId].checkbox:SetHeight(16)
      self.checklistFrame.lists[listId].entries[entryId].checkbox:SetChecked(false)
      self.checklistFrame.lists[listId].entries[entryId].checkbox:SetScript("OnClick", function(self)
									       DailyToDo:ToggleSingleChecklistFrameCheckbox(self)
									   end)
   end
   
   -- Change checkbox properties to match the new quest
   self.checklistFrame.lists[listId].entries[entryId].checkbox:SetPoint("TOPLEFT", horizontalOffset, -offset + 1)
   self.checklistFrame.lists[listId].entries[entryId].checkbox.entryId = entryId
   self.checklistFrame.lists[listId].entries[entryId].checkbox.listId = listId
   self.checklistFrame.lists[listId].entries[entryId].checkbox:SetChecked(self.db.profile.lists[listId].entries[entryId].completed)
   self.checklistFrame.lists[listId].entries[entryId].checkbox:Show()
   
   -- Check if we can reuse a label
   if table.getn(self.checklistFrameTextPool) > 0 then
      self.checklistFrame.lists[listId].entries[entryId].headerText = self.checklistFrameTextPool[1]
      table.remove(self.checklistFrameTextPool, 1)
   else
      self.checklistFrame.lists[listId].entries[entryId].headerText = self.checklistFrame:CreateFontString("QuestHeader"..entryId, nil, "ChatFontNormal")
   end
   
   -- Change header text for new entry
   self.checklistFrame.lists[listId].entries[entryId].headerText:SetText(self.db.profile.lists[listId].entries[entryId].text)
   self.checklistFrame.lists[listId].entries[entryId].headerText:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", horizontalOffset + 16, -offset)
   self.checklistFrame.lists[listId].entries[entryId].headerText:Show()
   
end

-- Creates the UI elements of a list on the Checklist Frame
function DailyToDo:CreateListOnChecklistFrame(listId, offset)
   -- Create header expand button
   if table.getn(self.checklistFrameHeaderExpandPool) > 0 then
      self.checklistFrame.lists[listId].expand = self.checklistFrameHeaderExpandPool[1]
      table.remove(self.checklistFrameHeaderExpandPool, 1)
   else
      self.checklistFrame.lists[listId].expand = CreateFrame("Button", nil, self.checklistFrame, "UICheckButtonTemplate")
      self.checklistFrame.lists[listId].expand:SetWidth(12)
      self.checklistFrame.lists[listId].expand:SetHeight(12)
      self.checklistFrame.lists[listId].expand:SetScript("OnClick", function(self)
							    DailyToDo:ToggleChecklistFrameListExpand(self)
							end)
      self.checklistFrame.lists[listId].expand:SetHighlightTexture(expandHighlightTexture)
   end
   
   if self.db.profile.lists[listId].expanded then
      self.checklistFrame.lists[listId].expand:SetNormalTexture(contractNormalTexture)
      self.checklistFrame.lists[listId].expand:SetPushedTexture(contractPushedTexture)
   else
      self.checklistFrame.lists[listId].expand:SetNormalTexture(expandNormalTexture)
      self.checklistFrame.lists[listId].expand:SetPushedTexture(expandPushedTexture)
   end
   
   self.checklistFrame.lists[listId].expand:SetPoint("TOPLEFT", 1, -offset - 1)
   self.checklistFrame.lists[listId].expand.listId = listId
   self.checklistFrame.lists[listId].expand:Show()
   
   -- Create header checkbox
   if table.getn(self.checklistFrameHeaderCheckboxPool) > 0 then
      self.checklistFrame.lists[listId].checkbox = self.checklistFrameHeaderCheckboxPool[1]
      table.remove(self.checklistFrameHeaderCheckboxPool, 1)
   else
      -- Create checkbox for list
      self.checklistFrame.lists[listId].checkbox = CreateFrame("CheckButton", nil, self.checklistFrame, "UICheckButtonTemplate")
      self.checklistFrame.lists[listId].checkbox:SetWidth(16)
      self.checklistFrame.lists[listId].checkbox:SetHeight(16)
      self.checklistFrame.lists[listId].checkbox:SetChecked(false)
      self.checklistFrame.lists[listId].checkbox:SetScript("OnClick", function(self)
							      DailyToDo:ToggleChecklistFrameListCheckbox(self)
							  end)
   end
   
   -- Change checkbox properties to match the new list
   self.checklistFrame.lists[listId].checkbox:SetPoint("TOPLEFT", 12, -offset + 1)
   self.checklistFrame.lists[listId].checkbox.listId = listId
   self.checklistFrame.lists[listId].checkbox:SetChecked(self.db.profile.lists[listId].completed)
   self.checklistFrame.lists[listId].checkbox:Show()
   
   -- Check if we can reuse a label
   if table.getn(self.checklistFrameHeaderTextPool) > 0 then
      self.checklistFrame.lists[listId].headerText = self.checklistFrameHeaderTextPool[1]
      table.remove(self.checklistFrameHeaderTextPool, 1)
   else
      self.checklistFrame.lists[listId].headerText = self.checklistFrame:CreateFontString("ListHeader"..listId, nil, "GameFontNormal")
   end
   
   -- Change header text for new entry
   self.checklistFrame.lists[listId].headerText:SetText(self.db.profile.lists[listId].name)
   self.checklistFrame.lists[listId].headerText:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", 30, -offset - 1)
   self.checklistFrame.lists[listId].headerText:Show()
end

-- Updates a list header in the Checklist Frame
function DailyToDo:UpdateListOnChecklistFrame(listId)
   -- Check if list is already represented on checklist frame, if not, create it
   if not self.checklistFrame.lists[listId] then
      self.checklistFrame.lists[listId] = {}
      self.checklistFrame.lists[listId].entries = {}
   end
   
   -- Check if UI elements have been created on checklist frame, if not, create them
   if not self.checklistFrame.lists[listId].checkbox then
      self:CreateListOnChecklistFrame(listId, 0)
   end
   
   self.checklistFrame.lists[listId].checkbox:Show()
   self.checklistFrame.lists[listId].headerText:Show()
   self.checklistFrame.lists[listId].expand:Show()
end

-- Updates a single entry in the Checklist Frame
function DailyToDo:UpdateEntryOnChecklistFrame(listId, entryId, checked)
   
   -- Show the requested entry if it is checked	
   if checked and self.db.profile.lists[listId].entries[entryId].days[self.currentDay] then
      -- Check if list is already represented on checklist frame, if not, create it
      if not self.checklistFrame.lists[listId] then
	 self.checklistFrame.lists[listId] = {}
	 self.checklistFrame.lists[listId].entries = {}
      end
      
      -- Check if entry has been created on checklist frame, if not, create it
      if not self.checklistFrame.lists[listId].entries[entryId] then
	 self:CreateEntryInChecklistFrame(listId, entryId, 0)
      end
      
      self.checklistFrame.lists[listId].entries[entryId].checkbox:Show()
      self.checklistFrame.lists[listId].entries[entryId].headerText:Show()
   else
      -- If it is unchecked, hide the entry if it exists
      --if not checked then
      if self.checklistFrame.lists[listId] and self.checklistFrame.lists[listId].entries[entryId] then
	 self.checklistFrame.lists[listId].entries[entryId].checkbox:Hide()
	 self.checklistFrame.lists[listId].entries[entryId].headerText:Hide()
      end
      --[elseif self.db.profile.lists[listId].entries[entryId].days[self.currentDay] then
      if self.checklistFrame.lists[listId] and self.checklistFrame.lists[listId].entries[entryId] then
	 self.checklistFrame.lists[listId].entries[entryId].checkbox:Hide()
	 self.checklistFrame.lists[listId].entries[entryId].headerText:Hide()
      end
      --end
   end
end

-- Moves all entries to their correct position in the checklist frame
function DailyToDo:UpdateEntryPositionsOnChecklistFrame()

   -- Calculate offset
   local offset = 18
   
   local horizontalOffset = 7
   
   if self.db.profile.showListHeaders then
      horizontalOffset = horizontalOffset + 12
   end
   
   -- Move all remaining entries to the new correct position
   for listId, list in pairs(self.checklistFrame.lists) do
      if self.db.profile.showListHeaders then
	 if not self.db.profile.lists[listId].completed or not self.db.profile.hideCompleted then
	    if not list.expand then
	       self:CreateListOnChecklistFrame(listId, offset)
	    else
	       list.checkbox:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", 12, -offset + 1)
	       list.checkbox.listId = listId
	       list.expand:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", 1, -offset - 1)
	       list.expand.listId = listId
	       list.headerText:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", 30, -offset - 1)
	    end
	    offset = offset + 18
	 else
	    if list.expand then
	       list.expand:Hide()
	       list.checkbox:Hide()
	       list.headerText:Hide()
	    end
	 end
      end
      if not self.db.profile.showListHeaders or self.db.profile.lists[listId].expanded then
	 for entryId, entry in pairs(list.entries) do
	    if entry and (self.db.profile.lists[listId].entries[entryId].checked and self.db.profile.lists[listId].expanded) and (not self.db.profile.lists[listId].entries[entryId].completed or not self.db.profile.hideCompleted) then
	       entry.checkbox:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", horizontalOffset, -offset + 1)
	       entry.checkbox.listId = listId
	       entry.checkbox.entryId = entryId
	       entry.checkbox:Show()
	       entry.headerText:SetPoint("TOPLEFT", self.checklistFrame, "TOPLEFT", horizontalOffset + 16, -offset)
	       entry.headerText:Show()
	       offset = offset + 16
	    else
	       if entry.checkbox then
		  entry.checkbox:Hide()
		  entry.headerText:Hide()
	       end
	    end
	 end
      else
	 for entryId, entry in pairs(list.entries) do
	    if entry then
	       entry.checkbox:Hide()
	       entry.headerText:Hide()
	    end
	 end
      end
   end
end

-- Updates all checkboxes on the checklist frame
function DailyToDo:UpdateEntryCompletedOnChecklistFrame()
   for listId, list in pairs(self.checklistFrame.lists) do
      local allCompleted = true
      for entryId, entry in pairs(list.entries) do
	 if self.db.profile.lists[listId].entries[entryId].completed then
	    entry.checkbox:SetChecked(true)
	 else
	    allCompleted = false
	 end
      end
      if self.db.profile.lists[listId].completed ~= allCompleted then
	 self.db.profile.lists[listId].completed = allCompleted
      end
      if list.checkbox then
	 list.checkbox:SetChecked(allCompleted)
      end
   end
end

-- Removes only the list header from the Checklist Frame
function DailyToDo:RemoveListHeaderFromChecklistFrame(listId)
   -- Check if list exists
   if not self.checklistFrame.lists[listId] then
      return
   end
   
   -- Check if UI objects exist, if they do, recycle them
   if self.checklistFrame.lists[listId].checkbox then
      self.checklistFrame.lists[listId].checkbox:Hide()
      self.checklistFrame.lists[listId].headerText:Hide()
      self.checklistFrame.lists[listId].expand:Hide()
      
      -- Store interface elements in respective pools for potential reuse
      table.insert(self.checklistFrameHeaderCheckboxPool, self.checklistFrame.lists[listId].checkbox)
      table.insert(self.checklistFrameHeaderTextPool, self.checklistFrame.lists[listId].headerText)
      table.insert(self.checklistFrameHeaderExpandPool, self.checklistFrame.lists[listId].expand)

      -- Nil out entries so they no longer exist in the frame
      self.checklistFrame.lists[listId].checkbox = nil
      self.checklistFrame.lists[listId].headerText = nil
      self.checklistFrame.lists[listId].expand = nil
   end
end

-- Removes a whole list from the Checklist Frame
function DailyToDo:RemoveListFromChecklistFrame(listId)
   
   -- Check if list has been created on checklist frame, if not, do nothing
   if not self.checklistFrame.lists[listId] then
      return
   end
   
   -- Remove all list entries from checklist frame
   local entryId = table.getn(self.checklistFrame.lists[listId].entries)
   while entryId > 0 do
      self:RemoveEntryFromChecklistFrame(listId, entryId)
      entryId = entryId - 1
   end
   
   -- Remove the header UI elements if they exist
   self:RemoveListHeaderFromChecklistFrame(listId)
   
   -- Remove list from table
   table.remove(self.checklistFrame.lists, listId)
end

-- Removes a single entry from the Checklist Frame
function DailyToDo:RemoveEntryFromChecklistFrame(listId, entryId)
   -- Check if entry has been created on checklist frame, if not, do nothing
   if not self.checklistFrame.lists[listId] or not self.checklistFrame.lists[listId].entries[entryId] then
      return
   end
   
   -- Hide interface elements for entry
   --DEBUG self:Print("Hiding and removing quest: "..entryId)
   self.checklistFrame.lists[listId].entries[entryId].checkbox:Hide()
   self.checklistFrame.lists[listId].entries[entryId].headerText:Hide()
   
   -- Store interface elements in respective pools for potential reuse
   table.insert(self.checklistFrameCheckboxPool, self.checklistFrame.lists[listId].entries[entryId].checkbox)
   table.insert(self.checklistFrameTextPool, self.checklistFrame.lists[listId].entries[entryId].headerText)

   -- Nil out entries so they no longer exist in the frame
   self.checklistFrame.lists[listId].entries[entryId].checkbox = nil
   self.checklistFrame.lists[listId].entries[entryId].headerText = nil
   
   table.remove(self.checklistFrame.lists[listId].entries, entryId)
   
   if table.getn(self.checklistFrame.lists[listId].entries) <= 0 and not self.db.profile.showListHeaders then
      self:RemoveListHeaderFromChecklistFrame(listId)
      -- Remove list from table
      table.remove(self.checklistFrame.lists, listId)
   end
   --DEBUG self:Print("Frame table size: "..table.getn(self.checklistFrame.quests))
end

-- Create the options frame under the WoW interface->addons menu
function DailyToDo:CreateManagerFrame()
   -- Create addon options frame
   self.checklistManagerFrame = CreateFrame("Frame", "ChecklistManagerFrame", InterfaceOptionsFramePanelContainer)
   self.checklistManagerFrame.name = "DailyToDo"
   self.checklistManagerFrame:SetAllPoints(InterfaceOptionsFramePanelContainer)
   self.checklistManagerFrame:Hide()
   InterfaceOptions_AddCategory(self.checklistManagerFrame)
   
   -- Create addon profiles options frame
   self.checklistProfilesOptions = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
   LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("DailyToDo: "..self.checklistProfilesOptions.name, self.checklistProfilesOptions)
   self.checklistProfilesFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("DailyToDo: "..self.checklistProfilesOptions.name, self.checklistProfilesOptions.name, "DailyToDo")  
   
   local function getOpt(info)
      return DailyToDo.db.profile[info[#info]]
   end
   
   local function setOpt(info, value)
      DailyToDo.db.profile[info[#info]] = value
      return DailyToDo.db.profile[info[#info]]
   end
   
   -- Create options frame
   LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable(
      "DailyToDo: Options", {
	 type = "group",
	 name = "Options",
	 args = {
	    general = {
	       type = "group",
	       inline = true,
	       name = "",
	       args = {
		  all = {						
		     type = "group",
		     inline = true,
		     name = "Resets",
		     order = 10,
		     args = {
			weeklyResetDayLabel = {
			   type = "description",
			   name = "Weekly reset day:",
			   order = 10
			},
			weeklyResetDay = {
			   type = "select",
			   name = "",
			   values = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"},
			   order = 20,
			   style = "dropdown",
			   get = getOpt,
			   set = function(info, value)
			      DailyToDo.db.profile.weeklyResetDay = value
			      DailyToDo:UpdateForNewDateAndTime()
			   end,
			},
			dailyResetTimeLabel = {
			   type = "description",
			   name = "Daily reset time (in local time):",
			   order = 30
			},
			dailyResetTime = {
			   type = "select",
			   name = "",
			   values = {"00:00", "01:00", "02:00", "03:00", "04:00", "05:00", "06:00", "07:00", "08:00", "09:00", "10:00", "11:00", "12:00", 
				     "13:00", "14:00", "15:00", "16:00", "17:00", "18:00", "19:00", "20:00", "21:00", "22:00", "23:00"},
			   order = 40,
			   width = "half",
			   get = getOpt,
			   set = function(info, value)
			      DailyToDo.db.profile.dailyResetTime = value
			      DailyToDo:UpdateForNewDateAndTime()
			   end,								
			},
			resetPollIntervalLabel = {
			   type = "description",
			   name = "Interval for checking if entries should be reset due to new time or day",
			   order = 50,
			},
			resetPollInterval = {
			   type = "select",
			   name = "",
			   values = {"Never", "10 Minutes", "20 Minutes", "30 Minutes", "1 Hour"},
			   order = 60,
			   get = getOpt,
			   set = function(info, value)
			      DailyToDo.db.profile.resetPollInterval = value
			      DailyToDo:ResetTimer()
			   end,
			},
			checkTimeLabel = {
			   type = "description",
			   order = 70,
			   name = "Use this to manually check if entries should be reset"
			},
			checkTime = {
			   type = "execute",
			   order = 80,
			   name = "Check Time",
			   func = function()  
			      DailyToDo:UpdateForNewDateAndTime()
			   end,
			}
		     },
		  }, 
		  frames = {
		     type = "group",
		     inline = true,
		     name = "Checklist Frame Options",
		     order = 20,
		     args = {
			locked = {
			   type = "toggle",
			   name = "Lock Frame",
			   order = 10,
			   get = getOpt,
			   set = setOpt,
			},
			hidden = {
			   type = "toggle",
			   name = "Hide Frame",
			   order = 20,
			   get = function(info) return DailyToDo.db.profile.framePosition.hidden end,
			   set = function(info, value)
			      DailyToDo.db.profile.framePosition.hidden = value
			      DailyToDo:UpdateVisibilityForChecklistFrame()
			   end,
			},
			showListHeaders = {
			   type = "toggle",
			   name = "Show list headers",
			   order = 30,
			   get = getOpt,
			   set = function(info, value)
			      DailyToDo.db.profile.showListHeaders = value
			      if value then
				 for listId, _ in pairs(DailyToDo.db.profile.lists) do
				    DailyToDo:UpdateListOnChecklistFrame(listId)
				 end
			      else
				 for listId, _ in pairs(DailyToDo.db.profile.lists) do
				    DailyToDo:RemoveListHeaderFromChecklistFrame(listId)
				 end
			      end
			      -- Update positions because of visibility change
			      DailyToDo:UpdateEntryPositionsOnChecklistFrame()
			   end,
			},
			hideCompleted = {
			   type = "toggle",
			   name = "Hide Completed",
			   order = 40,
			   get = getOpt,
			   set = function(info, value)
			      DailyToDo.db.profile.hideCompleted = value
			      DailyToDo:UpdateVisibilityOnChecklistFrame(value)
			      DailyToDo:UpdateEntryPositionsOnChecklistFrame()
			   end,
			},
			hideObjectives = {
			   type = "toggle",
			   name = "Hide Objectives Frame",
			   order = 50,
			   get = getOpt,
			   set = setOpt,
			},
		     },
		  },
		  minimap = {
		     type = "group",
		     inline = true,
		     name = "Minimap Icon",
		     order = 30,
		     args = {
			iconLabel = {
			   type = "description",
			   name = "Requires UI restart to take effect",
			   order = 10
			},
			icon = {
			   type = "toggle",
			   name = "Hide Minimap Icon",
			   order = 20,
			   get = function(info) return DailyToDo.db.profile.icon.hide end,
			   set = function(info, value)
			      DailyToDo.db.profile.icon.hide = value
			   end,
			}
		     },
		  },
		  utilities = {
		     type = "group",
		     inline = true,
		     name = "Utilities",
		     order = 40,
		     args = {
			resetLabel = {
			   type = "description",
			   name = "Requires UI restart to take effect",
			   order = 10
			},
			resetPosition = {
			   type = "execute",
			   order = 20,
			   name = "Reset Position",
			   func = function() 
			      DailyToDo.db.profile.framePosition = DailyToDo.defaults.profile.framePosition
			      DailyToDo.checklistFrame:SetPoint(DailyToDo.db.profile.framePosition.anchor, nil, DailyToDo.db.profile.framePosition.anchor, DailyToDo.db.profile.framePosition.x, DailyToDo.db.profile.framePosition.y-16)
			   end,
			},
			memoryLabel = {
			   type = "description",
			   name = "Use this when you have significantly changed the daily checklist to free up memory",
			   order = 30,
			},
			memory = {
			   type = "execute",
			   order = 40,
			   name = "Clear Trash",
			   func = function() collectgarbage("collect") end,
			}
		     }
		  }
	       },
	    },
	 },
							})
   self.checklistOptionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("DailyToDo: Options", "Options", "DailyToDo")
   
   local checklistManagerListLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   checklistManagerListLabel:SetPoint("TOPLEFT", 10, -10)
   checklistManagerListLabel:SetPoint("TOPRIGHT", 0, -10)
   checklistManagerListLabel:SetJustifyH("CENTER")
   checklistManagerListLabel:SetHeight(12)
   checklistManagerListLabel:SetText("DailyToDo Continued")

   
   local checklistManagerListLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   checklistManagerListLabel:SetPoint("TOPLEFT", 10, -30)
   checklistManagerListLabel:SetPoint("TOPRIGHT", 0, -30)
   checklistManagerListLabel:SetJustifyH("CENTER")
   checklistManagerListLabel:SetHeight(12)
   checklistManagerListLabel:SetText("Originally made by Ærixalimar, continued by Eltreum using fixes by Maaggel")
   
   
   local checklistManagerListLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   checklistManagerListLabel:SetPoint("TOPLEFT", 10, -50)
   checklistManagerListLabel:SetPoint("TOPRIGHT", 0, -50)
   checklistManagerListLabel:SetJustifyH("LEFT")
   checklistManagerListLabel:SetHeight(18)
   checklistManagerListLabel:SetText("New List")
   
   local checklistManagerListTextFieldLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   checklistManagerListTextFieldLabel:SetPoint("TOPLEFT", 10, -70)
   checklistManagerListTextFieldLabel:SetPoint("TOPRIGHT", 0, -70)
   checklistManagerListTextFieldLabel:SetJustifyH("LEFT")
   checklistManagerListTextFieldLabel:SetHeight(18)
   checklistManagerListTextFieldLabel:SetText("Create a new checklist by typing the list name in the editbox")
   
   -- Add entry creation form to options frame
   self.checklistManagerListTextField = CreateFrame("EditBox", "ChecklistManagerListTextField", self.checklistManagerFrame, "InputBoxTemplate")
   self.checklistManagerListTextField:SetSize(450, 28)
   self.checklistManagerListTextField:SetPoint("TOPLEFT", 20, -84)
   self.checklistManagerListTextField:SetMaxLetters(255)
   self.checklistManagerListTextField:SetMultiLine(false)
   self.checklistManagerListTextField:SetAutoFocus(false) 
   self.checklistManagerListTextField:SetScript("OnEnterPressed", function(self)
						   DailyToDo:CreateChecklistList()
   end)
   
   self.checklistManagerListTextFieldButton = CreateFrame("Button",  nil, self.checklistManagerFrame, "UIPanelButtonTemplate")
   self.checklistManagerListTextFieldButton:SetSize(100, 24)
   self.checklistManagerListTextFieldButton:SetPoint("TOPLEFT", 500, -86)
   self.checklistManagerListTextFieldButton:SetText("Create")
   self.checklistManagerListTextFieldButton:SetScript("OnClick", function(frame)
							 DailyToDo:CreateChecklistList()
   end)
   
   local checklistManagerEntryLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   checklistManagerEntryLabel:SetPoint("TOPLEFT", 10, -116)
   checklistManagerEntryLabel:SetPoint("TOPRIGHT", 0, -116)
   checklistManagerEntryLabel:SetJustifyH("LEFT")
   checklistManagerEntryLabel:SetHeight(18)
   checklistManagerEntryLabel:SetText("New Entry")
   
   local checklistManagerTextFieldLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   checklistManagerTextFieldLabel:SetPoint("TOPLEFT", 10, -135)
   checklistManagerTextFieldLabel:SetPoint("TOPRIGHT", 0, -135)
   checklistManagerTextFieldLabel:SetJustifyH("LEFT")
   checklistManagerTextFieldLabel:SetHeight(18)
   checklistManagerTextFieldLabel:SetText("Create a new checklist entry and add it to the currently selected list")
   
   -- Add entry creation form to options frame
   self.checklistManagerTextField = CreateFrame("EditBox", "ChecklistManagerTextField", self.checklistManagerFrame, "InputBoxTemplate")
   self.checklistManagerTextField:SetSize(355, 28)
   self.checklistManagerTextField:SetPoint("TOPLEFT", 20, -149)
   self.checklistManagerTextField:SetMaxLetters(255)
   self.checklistManagerTextField:SetMultiLine(false)
   self.checklistManagerTextField:SetAutoFocus(false) 
   self.checklistManagerTextField:SetScript("OnEnterPressed", function(self)
					       DailyToDo:CreateChecklistEntry()
   end)
   
   self.checklistManagerTextFieldButton = CreateFrame("Button",  nil, self.checklistManagerFrame, "UIPanelButtonTemplate")
   self.checklistManagerTextFieldButton:SetSize(100, 24)
   self.checklistManagerTextFieldButton:SetPoint("TOPLEFT", 500, -215)
   self.checklistManagerTextFieldButton:SetText("Create")
   self.checklistManagerTextFieldButton:SetScript("OnClick", function(frame)
						     DailyToDo:CreateChecklistEntry()
   end)
   
   local checklistManagerWeeklyLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   checklistManagerWeeklyLabel:SetPoint("TOPLEFT", 425, -135)
   checklistManagerWeeklyLabel:SetPoint("TOPRIGHT", 0, -135)
   checklistManagerWeeklyLabel:SetJustifyH("LEFT")
   checklistManagerWeeklyLabel:SetHeight(18)
   checklistManagerWeeklyLabel:SetText("Reset interval, defaults to daily")
   
   self.checklistManagerWeeklyCheckbox = CreateFrame("CheckButton", nil,  self.checklistManagerFrame, "UICheckButtonTemplate")
   self.checklistManagerWeeklyCheckbox:SetPoint("TOPLEFT", 425, -150)
   self.checklistManagerWeeklyCheckbox:SetWidth(25)
   self.checklistManagerWeeklyCheckbox:SetHeight(25)
   self.checklistManagerWeeklyCheckbox:SetScript("OnClick", function(frame)
						    DailyToDo.checklistManagerManualCheckbox:SetChecked(false)
   end)
   
   local checklistManagerWeeklyText = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
   checklistManagerWeeklyText:SetPoint("TOPLEFT", 450, -155)
   checklistManagerWeeklyText:SetHeight(18)
   checklistManagerWeeklyText:SetText("Weekly")
   
   self.checklistManagerManualCheckbox = CreateFrame("CheckButton", nil,  self.checklistManagerFrame, "UICheckButtonTemplate")
   self.checklistManagerManualCheckbox:SetPoint("TOPLEFT", 525, -150)
   self.checklistManagerManualCheckbox:SetWidth(25)
   self.checklistManagerManualCheckbox:SetHeight(25)
   self.checklistManagerManualCheckbox:SetScript("OnClick", function(frame)
						    DailyToDo.checklistManagerWeeklyCheckbox:SetChecked(false)
   end)
   
   local checklistManagerManualText = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
   checklistManagerManualText:SetPoint("TOPLEFT", 550, -155)
   checklistManagerManualText:SetHeight(18)
   checklistManagerManualText:SetText("Manual")
   
   local checklistManagerCheckboxesLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   checklistManagerCheckboxesLabel:SetPoint("TOPLEFT", 10, -180)
   checklistManagerCheckboxesLabel:SetPoint("TOPRIGHT", 0, -180)
   checklistManagerCheckboxesLabel:SetJustifyH("LEFT")
   checklistManagerCheckboxesLabel:SetHeight(18)
   checklistManagerCheckboxesLabel:SetText("Choose which days you would like the new entry to appear, defaults to all")
   
   -- Make checkboxes for entry reset properties
   self.checklistManagerSundayCheckbox = CreateFrame("CheckButton", nil,  self.checklistManagerFrame, "UICheckButtonTemplate")
   self.checklistManagerSundayCheckbox:SetPoint("TOPLEFT", 10, -195)
   self.checklistManagerSundayCheckbox:SetWidth(25)
   self.checklistManagerSundayCheckbox:SetHeight(25)
   
   local checklistManagerSundayText = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
   checklistManagerSundayText:SetPoint("TOPLEFT", 35, -200)
   checklistManagerSundayText:SetHeight(18)
   checklistManagerSundayText:SetText("Sunday")
   
   self.checklistManagerMondayCheckbox = CreateFrame("CheckButton", nil,  self.checklistManagerFrame, "UICheckButtonTemplate")
   self.checklistManagerMondayCheckbox:SetPoint("TOPLEFT", 125, -195)
   self.checklistManagerMondayCheckbox:SetWidth(25)
   self.checklistManagerMondayCheckbox:SetHeight(25)
   
   local checklistManagerMondayText = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
   checklistManagerMondayText:SetPoint("TOPLEFT", 150, -200)
   checklistManagerMondayText:SetHeight(18)
   checklistManagerMondayText:SetText("Monday")
   
   self.checklistManagerTuesdayCheckbox = CreateFrame("CheckButton", nil,  self.checklistManagerFrame, "UICheckButtonTemplate")
   self.checklistManagerTuesdayCheckbox:SetPoint("TOPLEFT", 250, -195)
   self.checklistManagerTuesdayCheckbox:SetWidth(25)
   self.checklistManagerTuesdayCheckbox:SetHeight(25)
   
   local checklistManagerTuesdayText = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
   checklistManagerTuesdayText:SetPoint("TOPLEFT", 275, -200)
   checklistManagerTuesdayText:SetHeight(18)
   checklistManagerTuesdayText:SetText("Tuesday")
   
   self.checklistManagerWednesdayCheckbox = CreateFrame("CheckButton", nil,  self.checklistManagerFrame, "UICheckButtonTemplate")
   self.checklistManagerWednesdayCheckbox:SetPoint("TOPLEFT", 375, -195)
   self.checklistManagerWednesdayCheckbox:SetWidth(25)
   self.checklistManagerWednesdayCheckbox:SetHeight(25)
   
   local checklistManagerWednesdayText = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
   checklistManagerWednesdayText:SetPoint("TOPLEFT", 400, -200)
   checklistManagerWednesdayText:SetHeight(18)
   checklistManagerWednesdayText:SetText("Wednesday")
   
   self.checklistManagerThursdayCheckbox = CreateFrame("CheckButton", nil,  self.checklistManagerFrame, "UICheckButtonTemplate")
   self.checklistManagerThursdayCheckbox:SetPoint("TOPLEFT", 10, -215)
   self.checklistManagerThursdayCheckbox:SetWidth(25)
   self.checklistManagerThursdayCheckbox:SetHeight(25)
   
   local checklistManagerThursdayText = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
   checklistManagerThursdayText:SetPoint("TOPLEFT", 35, -220)
   checklistManagerThursdayText:SetHeight(18)
   checklistManagerThursdayText:SetText("Thursday")
   
   self.checklistManagerFridayCheckbox = CreateFrame("CheckButton", nil,  self.checklistManagerFrame, "UICheckButtonTemplate")
   self.checklistManagerFridayCheckbox:SetPoint("TOPLEFT", 125, -215)
   self.checklistManagerFridayCheckbox:SetWidth(25)
   self.checklistManagerFridayCheckbox:SetHeight(25)
   
   local checklistManagerFridayText = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
   checklistManagerFridayText:SetPoint("TOPLEFT", 150, -220)
   checklistManagerFridayText:SetHeight(18)
   checklistManagerFridayText:SetText("Friday")
   
   self.checklistManagerSaturdayCheckbox = CreateFrame("CheckButton", nil,  self.checklistManagerFrame, "UICheckButtonTemplate")
   self.checklistManagerSaturdayCheckbox:SetPoint("TOPLEFT", 250, -215)
   self.checklistManagerSaturdayCheckbox:SetWidth(25)
   self.checklistManagerSaturdayCheckbox:SetHeight(25)
   
   local checklistManagerSaturdayText = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
   checklistManagerSaturdayText:SetPoint("TOPLEFT", 275, -220)
   checklistManagerSaturdayText:SetHeight(18)
   checklistManagerSaturdayText:SetText("Saturday")
   
   -- Add checklist title
   local checklistManagerTitle = self.checklistManagerFrame:CreateFontString("ManagerTitleText", nil, "GameFontNormalLarge")
   checklistManagerTitle:SetText("|cffFFB90FDaily Checklist Manager   -|r")
   checklistManagerTitle:SetPoint("TOPLEFT", self.checklistManagerFrame, "TOPLEFT", 10, -255)
   checklistManagerTitle:Show()
   
   -- Add checklist list dropdown
   self.checklistManagerListDropDown = CreateFrame("Button",  "ChecklistManagerListDropDown", self.checklistManagerFrame, "UIDropDownMenuTemplate")
   self.checklistManagerListDropDown:SetPoint("TOPLEFT", self.checklistManagerFrame, "TOPLEFT", 220, -250)
   self.checklistManagerListDropDown:Show()
   
   -- Initialize drop down
   UIDropDownMenu_Initialize(self.checklistManagerListDropDown, 
			     function(self, level)
				-- Gather list of names
				local listNames = {}
				
				for _, list in pairs(DailyToDo.db.profile.lists) do
				   table.insert(listNames, list.name)
				end
				
				local info = UIDropDownMenu_CreateInfo()
				for k,v in pairs(listNames) do
				   info = UIDropDownMenu_CreateInfo()
				   info.text = v
				   info.value = v
				   info.func = function(self)
				      DailyToDo.selectedManagerFrameList = self:GetID()
				      UIDropDownMenu_SetSelectedID(DailyToDo.checklistManagerListDropDown, self:GetID())
				      DailyToDo:UpdateEntriesForScrollFrame()
				   end
				   UIDropDownMenu_AddButton(info, level)
				end
			     end
   )
   UIDropDownMenu_SetWidth(self.checklistManagerListDropDown, 160);
   UIDropDownMenu_SetButtonWidth(self.checklistManagerListDropDown, 224)
   UIDropDownMenu_SetSelectedID(self.checklistManagerListDropDown, 1)
   UIDropDownMenu_JustifyText(self.checklistManagerListDropDown, "LEFT")
   
   -- Set initial selected list
   if table.getn(self.db.profile.lists) > 0 then
      self.selectedManagerFrameList = self.selectedManagerFrameList or 1
   end
   
   local checklistManagerTitleLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   checklistManagerTitleLabel:SetPoint("TOPLEFT", 40, -285)
   checklistManagerTitleLabel:SetPoint("TOPRIGHT", 0, -285)
   checklistManagerTitleLabel:SetJustifyH("LEFT")
   checklistManagerTitleLabel:SetHeight(18)
   checklistManagerTitleLabel:SetText("Check the entries that you would like to appear in your UI checklist")
   
   -- Create scrollable frame
   self.checklistManagerFrameScroll = CreateFrame("ScrollFrame", "checklistManagerFrameScroll", self.checklistManagerFrame, "FauxScrollFrameTemplate")
   local sizeX, sizeY = self.checklistManagerFrame:GetSize()
   self.checklistManagerFrameScroll:SetSize(sizeX, sizeY - self.managerPanelHeight )
   self.checklistManagerFrameScroll:SetPoint("CENTER", -30, -95)
   self.checklistManagerFrameScroll:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, 20, function()  
															     DailyToDo:UpdateEntriesForScrollFrame()
															 end) 
   end)
   self.checklistManagerFrameScroll:SetScript("OnShow", function()  
						 DailyToDo:UpdateEntriesForScrollFrame()
   end)
   
   -- Create empty tables
   self.checklistManagerFrameCheckboxes = {}
   self.checklistManagerFrameText = {}
   self.checklistManagerFrameClickable = {}
   
   -- Set up vertical offset for checkbox list
   local offset = self.managerPanelHeight - 0
   
   -- Create a set amount of checkboxes and labels for reuse on the scrollable frame
   for i=1,self.maxEntries do
      self.checklistManagerFrameCheckboxes[i] = CreateFrame("CheckButton", nil,  self.checklistManagerFrame, "UICheckButtonTemplate")
      self.checklistManagerFrameCheckboxes[i]:SetPoint("TOPLEFT", 40, -offset)
      self.checklistManagerFrameCheckboxes[i]:SetWidth(25)
      self.checklistManagerFrameCheckboxes[i]:SetHeight(25)
      self.checklistManagerFrameCheckboxes[i]:SetChecked(false)
      self.checklistManagerFrameCheckboxes[i]:SetScript("OnClick", function(self)
							   DailyToDo:ToggleSingleChecklistManagerCheckbox(self)
						       end)
      self.checklistManagerFrameCheckboxes[i]:Hide()
      
      self.checklistManagerFrameClickable[i] = CreateFrame("Frame", "ClickableFrame"..i, self.checklistManagerFrame)
      self.checklistManagerFrameClickable[i]:SetPoint("TOPLEFT", 70, -offset)
      self.checklistManagerFrameClickable[i]:SetWidth(255)
      self.checklistManagerFrameClickable[i]:SetHeight(25)
      self.checklistManagerFrameClickable[i]:SetScript("OnEnter", function(self)
							  self.inside = true
						      end)
      self.checklistManagerFrameClickable[i]:SetScript("OnLeave", function(self)
							  self.inside = false
						      end)
      self.checklistManagerFrameClickable[i]:SetScript("OnMouseUp", function(self)
							  if self.inside then
							     if DailyToDo.checklistManagerFrameText[i]:IsShown() then
								DailyToDo.checklistManagerFrameText[i]:SetText(DailyToDo.selectedEntryColor..DailyToDo.checklistManagerFrameText[i]:GetText())
								DailyToDo:ResetSelectedManagerFrameText()
								DailyToDo.selectedManagerFrameText = i
							     end
							  end
						      end)
      
      self.checklistManagerFrameText[i] = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
      self.checklistManagerFrameText[i]:SetPoint("TOPLEFT", 70, -offset - 5)
      self.checklistManagerFrameText[i]:SetText("")
      self.checklistManagerFrameText[i]:Hide()

      offset = offset + 20
   end
   
   local checklistManagerDeleteLabel = self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   checklistManagerDeleteLabel:SetPoint("BOTTOMLEFT", 40, 35)
   checklistManagerDeleteLabel:SetPoint("BOTTOMRIGHT", 0, 35)
   checklistManagerDeleteLabel:SetJustifyH("LEFT")
   checklistManagerDeleteLabel:SetHeight(18)
   checklistManagerDeleteLabel:SetText("Select an entry from the list by clicking the white text and use the corresponding button to delete or move it")
   
   -- Lock checkbox
   self.checklistManagerDeleteListButton = CreateFrame("Button", nil,  self.checklistManagerFrame, "UIPanelButtonTemplate")
   self.checklistManagerDeleteListButton:SetPoint("BOTTOMLEFT", 10, 10)
   self.checklistManagerDeleteListButton:SetSize(100, 24)
   self.checklistManagerDeleteListButton:SetText("Delete List")
   self.checklistManagerDeleteListButton:SetScript("OnClick", function(self)
						      DailyToDo:DeleteSelectedList()
   end)

   -- Lock frame text
   self.checklistManagerLockText =  self.checklistManagerFrame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
   self.checklistManagerLockText:SetPoint("BOTTOMLEFT", 35, 12)
   self.checklistManagerLockText:SetJustifyH("LEFT")
   self.checklistManagerLockText:SetHeight(18)
   self.checklistManagerLockText:SetText(" ")
   
   -- Create delete button
   self.checklistManagerFrameDelete = CreateFrame("Button",  nil, self.checklistManagerFrame, "UIPanelButtonTemplate")
   self.checklistManagerFrameDelete:SetPoint("BOTTOMRIGHT", -160, 10)
   self.checklistManagerFrameDelete:SetSize(70, 24)
   self.checklistManagerFrameDelete:SetText("Delete")
   self.checklistManagerFrameDelete:SetScript("OnClick", function(self) 
						 DailyToDo:DeleteSelectedEntry()
   end)
   
   -- Create move up button
   self.checklistManagerFrameUp = CreateFrame("Button",  nil, self.checklistManagerFrame, "UIPanelButtonTemplate")
   self.checklistManagerFrameUp:SetPoint("BOTTOMRIGHT", -70, 10)
   self.checklistManagerFrameUp:SetSize(60, 24)
   self.checklistManagerFrameUp:SetText("Up")
   self.checklistManagerFrameUp:SetScript("OnClick", function(self) 
					     DailyToDo:MoveSelectedEntryUp()
   end)
   
   -- Create move down button
   self.checklistManagerFrameDown = CreateFrame("Button",  nil, self.checklistManagerFrame, "UIPanelButtonTemplate")
   self.checklistManagerFrameDown:SetPoint("BOTTOMRIGHT", -10, 10)
   self.checklistManagerFrameDown:SetSize(60, 24)
   self.checklistManagerFrameDown:SetText("Down")
   self.checklistManagerFrameDown:SetScript("OnClick", function(self) 
					       DailyToDo:MoveSelectedEntryDown()
   end)
end

-- Removes the selected list from the manager frame and database
function DailyToDo:DeleteSelectedList()

   local listId = self.selectedManagerFrameList
   
   -- If nothing is selected, do nothing
   if not listId then
      return 
   end
   
   -- Remove all entries from checklist frame
   self:RemoveListFromChecklistFrame(listId)
   
   -- Remove list from database
   table.remove(self.db.profile.lists, listId)
   
   -- Add default list if we deleted all others
   if table.getn(self.db.profile.lists) <= 0 then
      self.db.profile.lists[1] = {
	 name = "Default",
	 entries = {},
      }
      if self.db.profile.showListHeaders then
	 self:UpdateListOnChecklistFrame(1)
      end
   end
   
   -- Reload list dropdown
   ToggleDropDownMenu(1, nil, self.checklistManagerListDropDown)
   
   CloseDropDownMenus()
   
   -- Reset dropdown selection
   UIDropDownMenu_SetSelectedID(self.checklistManagerListDropDown, 1)
   self.selectedManagerFrameList = 1
   
   -- Reload list manager
   self:UpdateEntriesForScrollFrame()
   
   self:UpdateEntryPositionsOnChecklistFrame()
end

-- Removes the selected entry from the manager frame and database
function DailyToDo:DeleteSelectedEntry()

   -- If nothing is selected, do nothing
   if not self.selectedManagerFrameList or not self.selectedManagerFrameText then
      return 
   end
   
   local listId = self.selectedManagerFrameList
   local entryId = self.checklistManagerFrameCheckboxes[self.selectedManagerFrameText].entryId
   --DEBUG self:Print("Deleted entry: "..entryId)
   --local allTableSize = table.getn(self.db.profile.lists[listId].entries)
   --DEBUG self:Print("All Quests Table Size: "..allTableSize)
   
   self:RemoveEntryFromChecklistFrame(listId, entryId)
   
   table.remove(self.db.profile.lists[listId].entries, entryId)
   
   self:UpdateEntriesForScrollFrame()
   self:UpdateEntryPositionsOnChecklistFrame()
end

-- Moves the selected entry up in the options frame and database
function DailyToDo:MoveSelectedEntryUp()

   -- If nothing is selected, do nothing
   if not self.selectedManagerFrameList or not self.selectedManagerFrameText then
      return 
   end
   
   local listId = self.selectedManagerFrameList
   local entryId = self.checklistManagerFrameCheckboxes[self.selectedManagerFrameText].entryId
   --DEBUG self:Print("Moving up entry: "..entryId)
   --local tableSize = table.getn(self.db.profile.lists[listId].entries)
   --DEBUG self:Print("All Quests Table Size: "..tableSize)
   
   -- If the selected entry is already at the top of the list, do nothing
   if entryId <= 1 then
      return
   end
   
   -- Swap the selected entry and the one directly above
   local prevQuest = self.db.profile.lists[listId].entries[entryId-1]
   self.db.profile.lists[listId].entries[entryId-1] = self.db.profile.lists[listId].entries[entryId]
   self.db.profile.lists[listId].entries[entryId] = prevQuest
   
   if self.checklistFrame.lists[listId] then
      prevQuest = self.checklistFrame.lists[listId].entries[entryId-1]
      self.checklistFrame.lists[listId].entries[entryId-1] = self.checklistFrame.lists[listId].entries[entryId]
      self.checklistFrame.lists[listId].entries[entryId] = prevQuest
   end
   
   self:UpdateEntriesForScrollFrame()
   self:UpdateEntryPositionsOnChecklistFrame()
   
   self.checklistManagerFrameText[entryId-1]:SetText(self.selectedEntryColor..self.checklistManagerFrameText[entryId-1]:GetText())
   self.selectedManagerFrameText = entryId-1
end

-- Moves the selected entry down in the options frame and database
function DailyToDo:MoveSelectedEntryDown()

   -- If nothing is selected, do nothing
   if not self.selectedManagerFrameList or not self.selectedManagerFrameText then
      return 
   end
   
   local listId = self.selectedManagerFrameList
   local entryId = self.checklistManagerFrameCheckboxes[self.selectedManagerFrameText].entryId
   --DEBUG self:Print("Moving down entry: "..entryId)
   local tableSize = table.getn(self.db.profile.lists[listId].entries)
   --DEBUG self:Print("All Quests Table Size: "..tableSize)
   
   -- If the selected entry is already at the bottom of the list, do nothing
   if entryId >= tableSize then
      return
   end
   
   -- Swap the selected entry and the one directly above
   local nextQuest = self.db.profile.lists[listId].entries[entryId+1]
   self.db.profile.lists[listId].entries[entryId+1] = self.db.profile.lists[listId].entries[entryId]
   self.db.profile.lists[listId].entries[entryId] = nextQuest
   
   if self.checklistFrame.lists[listId] then
      nextQuest = self.checklistFrame.lists[listId].entries[entryId+1]
      self.checklistFrame.lists[listId].entries[entryId+1] = self.checklistFrame.lists[listId].entries[entryId]
      self.checklistFrame.lists[listId].entries[entryId] = nextQuest
   end
   
   self:UpdateEntriesForScrollFrame()
   self:UpdateEntryPositionsOnChecklistFrame()
   
   self.checklistManagerFrameText[entryId+1]:SetText(self.selectedEntryColor..self.checklistManagerFrameText[entryId+1]:GetText())
   self.selectedManagerFrameText = entryId+1
end

-- Resets the color of the previously selected options text
function DailyToDo:ResetSelectedManagerFrameText()
   if self.selectedManagerFrameText then
      local text = self.checklistManagerFrameText[self.selectedManagerFrameText]:GetText()
      if string.find(text, self.selectedEntryColor) then
	 self.checklistManagerFrameText[self.selectedManagerFrameText]:SetText(string.sub(text, 11))
      end
   end
   self.selectedManagerFrameText = nil
end

-- Create new list if it does not exist and update checklist frame
function DailyToDo:CreateChecklistList() 
   
   -- Grab text from editbox
   local newList = strtrim(self.checklistManagerListTextField:GetText())
   
   -- Discard if text was empty
   if newList == "" then
      return
   end
   
   -- Check if list exists already
   for listId, list in ipairs(self.db.profile.lists) do
      if list.name == newList then
	 return
      end
   end
   
   -- Add new quest to database
   local tableSize = table.getn(self.db.profile.lists)+1
   self.db.profile.lists[tableSize] = {}
   self.db.profile.lists[tableSize].name = newList
   self.db.profile.lists[tableSize].entries = {}
   self.db.profile.lists[tableSize].expanded = true
   
   -- Update selected list
   self.selectedManagerFrameList = tableSize
   
   ToggleDropDownMenu(1, nil, self.checklistManagerListDropDown)
   
   CloseDropDownMenus()
   
   UIDropDownMenu_SetSelectedID(self.checklistManagerListDropDown, tableSize)
   
   -- Update scroll frame
   self:UpdateEntriesForScrollFrame()
   
   -- Update UI Checklist
   if self.db.profile.showListHeaders then
      self:UpdateListOnChecklistFrame(tableSize)
      -- Update positions because of visibility change
      self:UpdateEntryPositionsOnChecklistFrame()
   end
   
   -- Reset text for editbox
   self.checklistManagerListTextField:SetText("")
   
end

-- Create new entry if it does not exist and update checklist frame
function DailyToDo:CreateChecklistEntry()

   if not self.selectedManagerFrameList then
      return
   end
   
   local listId = self.selectedManagerFrameList
   
   -- Grab text from editbox
   local newEntry = strtrim(self.checklistManagerTextField:GetText())
   
   -- Discard if text was empty
   if newEntry == "" then
      return
   end
   
   -- Keep track if we are creating a new entry or overwriting an old
   local overwrite = false
   
   -- Keep track of index of existing or new
   local index = 0
   
   -- Check if entry exists already, if so overwrite
   for entryId, entry in ipairs(self.db.profile.lists[listId].entries) do
      if entry.text == newEntry then
	 overwrite = true
	 index = entryId
	 self.db.profile.lists[listId].entries[index] = self:CreateDatabaseEntry(newEntry)
	 break
      end
   end
   
   if not overwrite then
      -- Add new entry to database
      index = table.getn(self.db.profile.lists[listId].entries)+1
      self.db.profile.lists[listId].entries[index] = self:CreateDatabaseEntry(newEntry)
   end
   
   self.db.profile.lists[listId].completed = false
   if self.checklistFrame.lists[listId] and self.checklistFrame.lists[listId].checkbox then
      self.checklistFrame.lists[listId].checkbox:SetChecked(false)
   end
   
   -- Update scroll frame
   self:UpdateEntriesForScrollFrame()
   
   -- Update UI Checklist
   self:UpdateEntryOnChecklistFrame(listId, index, true)
   
   -- Update positions because of visibility change
   self:UpdateEntryPositionsOnChecklistFrame()
   
   -- Update visibility change
   self:UpdateVisibilityForListOnChecklistFrame(listId, self.db.profile.hideCompleted)
   
   -- Reset text for editbox
   self.checklistManagerTextField:SetText("")
   
   -- Reset checkboxes
   self.checklistManagerSundayCheckbox:SetChecked(false)
   self.checklistManagerMondayCheckbox:SetChecked(false)
   self.checklistManagerTuesdayCheckbox:SetChecked(false)
   self.checklistManagerWednesdayCheckbox:SetChecked(false)
   self.checklistManagerThursdayCheckbox:SetChecked(false)
   self.checklistManagerFridayCheckbox:SetChecked(false)
   self.checklistManagerSaturdayCheckbox:SetChecked(false)
   self.checklistManagerWeeklyCheckbox:SetChecked(false)
   self.checklistManagerManualCheckbox:SetChecked(false)
end

-- Creates a new list entry in the database using the current fields
function DailyToDo:CreateDatabaseEntry(text)
   local noneChecked = false
   if not self.checklistManagerSundayCheckbox:GetChecked() and
      not self.checklistManagerMondayCheckbox:GetChecked() and
      not self.checklistManagerTuesdayCheckbox:GetChecked() and
      not self.checklistManagerWednesdayCheckbox:GetChecked() and
      not self.checklistManagerThursdayCheckbox:GetChecked() and
      not self.checklistManagerFridayCheckbox:GetChecked() and
   not self.checklistManagerSaturdayCheckbox:GetChecked() then
      noneChecked = true
   end
   local entry = {
      text = text,
      checked = true,
      completed = false,
      days = {
	 [SUNDAY] = noneChecked or self.checklistManagerSundayCheckbox:GetChecked(),
	 [MONDAY] = noneChecked or self.checklistManagerMondayCheckbox:GetChecked(),
	 [TUESDAY] = noneChecked or self.checklistManagerTuesdayCheckbox:GetChecked(),
	 [WEDNESDAY] = noneChecked or self.checklistManagerWednesdayCheckbox:GetChecked(),
	 [THURSDAY] = noneChecked or self.checklistManagerThursdayCheckbox:GetChecked(),
	 [FRIDAY] = noneChecked or self.checklistManagerFridayCheckbox:GetChecked(),
	 [SATURDAY] = noneChecked or self.checklistManagerSaturdayCheckbox:GetChecked(),
      },
      weekly = self.checklistManagerWeeklyCheckbox:GetChecked(),
      manual = self.checklistManagerManualCheckbox:GetChecked(),
   }
   return entry
end

-- Change database value
function DailyToDo:ToggleSingleChecklistManagerCheckbox(currentBox)
   self.db.profile.lists[currentBox.listId].entries[currentBox.entryId].checked = currentBox:GetChecked()
   
   self:UpdateEntryOnChecklistFrame(currentBox.listId, currentBox.entryId, currentBox:GetChecked())
   
   -- Update positions because of visibility change
   self:UpdateEntryPositionsOnChecklistFrame()
end

-- Change database values, images, and checklist positions
function DailyToDo:ToggleChecklistFrameListExpand(currentExpand)
   local listId = currentExpand.listId
   local expanded = not self.db.profile.lists[listId].expanded
   self.db.profile.lists[listId].expanded = expanded
   
   if expanded then
      currentExpand:SetNormalTexture(contractNormalTexture)
      currentExpand:SetPushedTexture(contractPushedTexture)
      
      for entryId, entry in pairs(self.checklistFrame.lists[listId].entries) do
	 if self.db.profile.lists[listId].entries[entryId].checked then
	    entry.checkbox:Show()
	    entry.headerText:Show()
	 end
      end
   else
      currentExpand:SetNormalTexture(expandNormalTexture)
      currentExpand:SetPushedTexture(expandPushedTexture)
      
      for entryId, entry in pairs(self.checklistFrame.lists[listId].entries) do
	 entry.checkbox:Hide()
	 entry.headerText:Hide()
      end
   end

   self:UpdateEntryPositionsOnChecklistFrame()
end

-- Change database values
function DailyToDo:ToggleChecklistFrameListCheckbox(currentBox)
   self.db.profile.lists[currentBox.listId].completed = currentBox:GetChecked()
   
   for entryId, entry in pairs(self.db.profile.lists[currentBox.listId].entries) do
      self.db.profile.lists[currentBox.listId].entries[entryId].completed = currentBox:GetChecked()
      if self.checklistFrame.lists[currentBox.listId].entries[entryId] then
	 self.checklistFrame.lists[currentBox.listId].entries[entryId].checkbox:SetChecked(currentBox:GetChecked())
      end
   end
   
   if self.db.profile.hideCompleted then
      self:UpdateVisibilityForListOnChecklistFrame(currentBox.listId, self.db.profile.hideCompleted)
   end
   
   self:UpdateEntryPositionsOnChecklistFrame()
end

-- Change database values
function DailyToDo:ToggleSingleChecklistFrameCheckbox(currentBox)
   self.db.profile.lists[currentBox.listId].entries[currentBox.entryId].completed = currentBox:GetChecked()
   self:UpdateVisibilityForEntryOnChecklistFrame(currentBox.listId, currentBox.entryId, self.db.profile.hideCompleted)
   
   if currentBox:GetChecked() then
      local allChecked = true
      for _, entry in pairs(self.db.profile.lists[currentBox.listId].entries) do
	 if not entry.completed and entry.checked then
	    allChecked = false
	 end
      end
      if allChecked then
	 self.db.profile.lists[currentBox.listId].completed = true
	 if self.checklistFrame.lists[currentBox.listId] then
	    self.checklistFrame.lists[currentBox.listId].checkbox:SetChecked(true)
	    if self.db.profile.hideCompleted then
	       self.checklistFrame.lists[currentBox.listId].expand:Hide()
	       self.checklistFrame.lists[currentBox.listId].checkbox:Hide()
	       self.checklistFrame.lists[currentBox.listId].headerText:Hide()
	    end
	 end
      end
   else
      if self.checklistFrame.lists[currentBox.listId] and self.checklistFrame.lists[currentBox.listId].checkbox:GetChecked() then
	 self.db.profile.lists[currentBox.listId].completed = false
	 self.checklistFrame.lists[currentBox.listId].checkbox:SetChecked(false)
	 self.checklistFrame.lists[currentBox.listId].expand:Show()
	 self.checklistFrame.lists[currentBox.listId].checkbox:Show()
	 self.checklistFrame.lists[currentBox.listId].headerText:Show()
      end
   end
   
   self:UpdateEntryPositionsOnChecklistFrame()
end

-- Update entries in entries scroll frame when scrollbar moves
function DailyToDo:UpdateEntriesForScrollFrame()

   -- Remove highlight from selected entry, if any
   self:ResetSelectedManagerFrameText()
   
   -- Save selected listId
   local listId = self.selectedManagerFrameList
   
   -- Save number of checkboxes used
   local numberOfRows = 1
   
   -- Save number of entries in entries
   local numberOfEntries = 0
   
   if listId and self.db.profile.lists and self.db.profile.lists[listId] then 
      numberOfEntries = table.getn(self.db.profile.lists[listId].entries)
      for entryId, entry in ipairs(self.db.profile.lists[listId].entries) do
	 if numberOfRows <= self.maxEntries then
	    if entryId > self.checklistManagerFrameScroll.offset then
	       local checkbox = self.checklistManagerFrameCheckboxes[numberOfRows]
	       checkbox:SetChecked(entry.checked)
	       checkbox.entryId = entryId
	       checkbox.listId = listId
	       checkbox:Show()
	       
	       local label = self.checklistManagerFrameText[numberOfRows]
	       label:SetText(entry.text)
	       label:Show()
	       
	       numberOfRows = numberOfRows + 1
	    end
	 end
      end
   end
   
   for i = numberOfRows, self.maxEntries do
      self.checklistManagerFrameCheckboxes[i]:Hide()
      self.checklistManagerFrameText[i]:Hide()
   end
   
   -- Execute scroll bar update 
   FauxScrollFrame_Update(self.checklistManagerFrameScroll, numberOfEntries, self.maxEntries, 20, nil, nil, nil, nil, nil, nil, true)
end

-- Called when profile changes, reloads options, list dropdown, manager, and checklist
function DailyToDo:RefreshEverything()
   -- Reload list dropdown
   ToggleDropDownMenu(1, nil, self.checklistManagerListDropDown)
   
   CloseDropDownMenus()
   
   UIDropDownMenu_SetSelectedID(self.checklistManagerListDropDown, 1)
   self.selectedManagerFrameList = 1
   
   -- Reload list manager
   self:UpdateEntriesForScrollFrame()
   
   -- Delete existing checklist frame elements, save ui elements
   self:RemoveChecklistFrameElements()
   
   -- Reconstruct checklist frame
   self:CreateChecklistFrameElements()
   
   -- Move checklist frame
   self.checklistFrame:SetPoint(self.db.profile.framePosition.anchor, nil, self.db.profile.framePosition.anchor, self.db.profile.framePosition.x, self.db.profile.framePosition.y-16)
   
end

-- Called when minimap icon is clicked
function DailyToDo:HandleIconClick(button)
   if button == "LeftButton" then
      self.db.profile.framePosition.hidden = not self.db.profile.framePosition.hidden
      DailyToDo:UpdateVisibilityForChecklistFrame()
   elseif button == "RightButton" then
      -- Open options menu in interface->addon menu
      InterfaceOptionsFrame_OpenToCategory(self.checklistManagerFrame)
	  InterfaceOptionsFrame_OpenToCategory(self.checklistManagerFrame)
   end
end

-- Called when chat command is executed to hide the checklist frame
function DailyToDo:HideChecklistFrame()
   self.db.profile.framePosition.hidden = true
   self.checklistFrame:Hide()
end

-- Called when chat command is executed to hide the checklist frame
function DailyToDo:ShowChecklistFrame()
   self.db.profile.framePosition.hidden = false
   self.checklistFrame:Show()
end

function DailyToDo:UpdateVisibilityForIcon(hidden)
  -- TODO
end

function DailyToDo.ObjectiveTrackerFrameShow(...)
   if DailyToDo.db.profile.hideObjectives then
      DailyToDo:UpdateVisibilityForChecklistFrame()
   else
      DailyToDo.ShowObjectivesWindow(ObjectiveTrackerFrame)
   end
end
	 
function DailyToDo:UpdateVisibilityForChecklistFrame()
   if self.db.profile.framePosition.hidden then
      self.checklistFrame:Hide()
   else
      self.checklistFrame:Show()
   end
   if self.db.profile.hideObjectives then
      if self.db.profile.framePosition.hidden then
	 DailyToDo.ShowObjectivesWindow(ObjectiveTrackerFrame)
      else
	 ObjectiveTrackerFrame:Hide()
      end
   end
end

function DailyToDo:UpdateVisibilityForEntryOnChecklistFrame(listId, entryId, hidden)
   local entry = self.db.profile.lists[listId].entries[entryId]
   if hidden then
      if self.checklistFrame.lists[listId].entries[entryId] then
	 if entry.completed then
	    self.checklistFrame.lists[listId].entries[entryId].checkbox:Hide()
	    self.checklistFrame.lists[listId].entries[entryId].headerText:Hide()
	 else
	    self.checklistFrame.lists[listId].entries[entryId].checkbox:Show()
	    self.checklistFrame.lists[listId].entries[entryId].headerText:Show()
	 end
      end
   else
      if not self.checklistFrame.lists[listId].entries[entryId] then
	 if entry.checked then
	    self:CreateEntryInChecklistFrame(listId, entryId, 0)
	 end
      else
	 self.checklistFrame.lists[listId].entries[entryId].checkbox:Show()
	 self.checklistFrame.lists[listId].entries[entryId].headerText:Show()
      end
   end
end

function DailyToDo:UpdateVisibilityForListOnChecklistFrame(listId, hidden)
   local list = self.db.profile.lists[listId]
   if hidden then
      if self.checklistFrame.lists[listId] then
	 if self.checklistFrame.lists[listId].entries then
	    for entryId, entry in pairs(list.entries) do
	       if self.checklistFrame.lists[listId].entries[entryId] then
		  if entry.completed then
		     self.checklistFrame.lists[listId].entries[entryId].checkbox:Hide()
		     self.checklistFrame.lists[listId].entries[entryId].headerText:Hide()
		  else
		     self.checklistFrame.lists[listId].entries[entryId].checkbox:Show()
		     self.checklistFrame.lists[listId].entries[entryId].headerText:Show()
		  end
	       end
	    end
	 end
	 if self.checklistFrame.lists[listId].expand then
	    if list.completed then
	       self.checklistFrame.lists[listId].expand:Hide()
	       self.checklistFrame.lists[listId].checkbox:Hide()
	       self.checklistFrame.lists[listId].headerText:Hide()
	    else
	       self.checklistFrame.lists[listId].expand:Show()
	       self.checklistFrame.lists[listId].checkbox:Show()
	       self.checklistFrame.lists[listId].headerText:Show()
	    end
	 end
      end
   else
      if not self.checklistFrame.lists[listId] or not self.checklistFrame.lists[listId].entries then
	 self:CreateListOnChecklistFrame(listId, 0)
      else
	 for entryId, entry in pairs(list.entries) do
	    if not self.checklistFrame.lists[listId].entries[entryId] then
	       if entry.checked and entry.days[self.currentDay] then
		  self:CreateEntryInChecklistFrame(listId, entryId, 0)

		  if not (entry.completed and self.db.profile.hideCompleted) then
		     self.checklistFrame.lists[listId].entries[entryId].checkbox:Show()
		     self.checklistFrame.lists[listId].entries[entryId].headerText:Show()
		  end
	       end
	    end
	 end
	 if self.checklistFrame.lists[listId].expand then
	    self.checklistFrame.lists[listId].expand:Show()
	    self.checklistFrame.lists[listId].checkbox:Show()
	    self.checklistFrame.lists[listId].headerText:Show()
	 end
      end
   end
end

function DailyToDo:UpdateVisibilityOnChecklistFrame(hidden)
   for listId, _ in pairs(self.db.profile.lists) do
      self:UpdateVisibilityForListOnChecklistFrame(listId, hidden)
   end
end
