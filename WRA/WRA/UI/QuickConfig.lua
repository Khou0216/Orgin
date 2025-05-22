-- UI/QuickConfig.lua
-- Creates the top-left buttons for Configuration and Quick Settings panel.
-- Uses the Myfury approach: Manually define options and create AceGUI widgets directly.
-- v2: Dynamically create widgets in RefreshPanel based on spec options.

local addonName, _ = ...
local LibStub = _G.LibStub
local AceAddon = LibStub("AceAddon-3.0")
local CurrentWRA = AceAddon:GetAddon(addonName) -- Get instance for module creation

-- Get required libraries (AceGUI and AceTimer needed locally)
local AceGUI = LibStub("AceGUI-3.0", true)
local AceTimer = LibStub("AceTimer-3.0", true)
local L = LibStub("AceLocale-3.0"):GetLocale(addonName) -- Localization

-- Ensure libraries are loaded
if not AceGUI or not AceTimer then
    print(addonName .. " QuickConfig: Missing AceGUI or AceTimer!")
    return
end
if not CurrentWRA then
    print(addonName .. " QuickConfig: Could not get WRA Addon instance!")
    return
end

-- --- Create the QuickConfig Module ---
local QuickConfig = CurrentWRA:NewModule("QuickConfig", "AceTimer-3.0")

-- --- Variables ---
-- Make button variables accessible within the module's scope
local configLauncherButton = nil
local quickPanelButton = nil
local quickPanelFrame = nil -- This refers to the AceGUI window instance

-- --- Functions attached to the QuickConfig MODULE ---

-- CreateLauncherButtons function (moved up for clarity)
local function CreateLauncherButtons()
    local WRA = AceAddon:GetAddon(addonName)
    if not WRA then print(addonName .. " QuickConfig: Cannot create buttons, WRA instance not found."); return end
    local QCModule = WRA:GetModule("QuickConfig") -- Use WRA:GetModule inside function
    if not QCModule then WRA:PrintError("QuickConfig: Cannot create buttons, QuickConfig module instance not found."); return end

    -- Only create if they don't exist
    if not configLauncherButton then
        WRA:PrintDebug("Creating Config Launcher Button...")
        configLauncherButton = CreateFrame("Button", "WRA_ConfigLauncher", UIParent, "UIPanelButtonTemplate")
        configLauncherButton:SetSize(60, 22); configLauncherButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
        configLauncherButton:SetText(L["Config"]); configLauncherButton:SetFrameStrata("HIGH") -- Use Locale
        configLauncherButton:SetScript("OnClick", function()
            local OnClickWRA = AceAddon:GetAddon(addonName); if not OnClickWRA then return end
            -- Use AceConfigDialog stored on WRA object
            if OnClickWRA.AceConfigDialog then
                 if type(OnClickWRA.AceConfigDialog.Open) == "function" then
                     OnClickWRA.AceConfigDialog:Open(addonName)
                     OnClickWRA:PrintDebug("Opening main options panel:", addonName)
                 else
                      OnClickWRA:PrintError("Cannot open main options: WRA.AceConfigDialog library is invalid or missing Open method.")
                 end
            else
                OnClickWRA:PrintError("Cannot open main options: WRA.AceConfigDialog reference not found.")
            end
        end)
    end

    if not quickPanelButton then
         WRA:PrintDebug("Creating Quick Launcher Button...")
         quickPanelButton = CreateFrame("Button", "WRA_QuickLauncher", UIParent, "UIPanelButtonTemplate")
         quickPanelButton:SetSize(60, 22); quickPanelButton:SetPoint("TOPLEFT", configLauncherButton, "BOTTOMLEFT", 0, -4)
         quickPanelButton:SetText(L["Quick"]); quickPanelButton:SetFrameStrata("HIGH") -- Use Locale
         quickPanelButton:SetScript("OnClick", function()
            local ClickWRA = AceAddon:GetAddon(addonName); if not ClickWRA then print("WRA instance not found on click!"); return end
            local ClickQCModule = ClickWRA:GetModule("QuickConfig") -- Get module fresh on click
            if ClickQCModule then
                 if type(ClickQCModule.ToggleFrame) == "function" then
                     ClickQCModule:ToggleFrame() -- Call the toggle function on the module instance
                 else
                     ClickWRA:PrintError("QuickConfig: ToggleFrame function not found on module!")
                 end
            else ClickWRA:PrintError("QuickConfig: QuickConfig module instance not found!") end
         end)
    end

    -- Show buttons after creation/check
    -- Let OnEnable handle showing based on addon state
end


function QuickConfig:RefreshPanel()
    local WRA = AceAddon:GetAddon(addonName)
    if not WRA then return end

    -- Check if the frame exists
    if not quickPanelFrame then
        return
    end

    -- Check if AceGUI is available
    if not WRA.AceGUI then
        WRA:PrintError("[RefreshPanel] Error: WRA.AceGUI reference is missing!")
        return
    end

    -- Ensure the database is initialized
    if not WRA.db or not WRA.db.profile or not WRA.db.profile.specs then
        WRA:PrintError("[RefreshPanel] Database not initialized (WRA.db.profile.specs missing), cannot build quick options.")
        return
    end

    WRA:PrintDebug("[RefreshPanel] Refreshing panel content (Dynamic approach)...")

    -- 1. Clear existing widgets from the frame
    quickPanelFrame:ReleaseChildren()
    WRA:PrintDebug("[RefreshPanel] Released existing children.") -- DEBUG

    -- 2. Get current spec and its database table
    local currentSpecKey = nil
    if WRA.SpecLoader and WRA.SpecLoader.GetCurrentSpecKey then
        currentSpecKey = WRA.SpecLoader:GetCurrentSpecKey() -- Get key like "FuryWarrior"
    end

    if not currentSpecKey then
        WRA:PrintError("[RefreshPanel] Could not determine current spec key via SpecLoader.")
        return
    end
    local specDB = WRA.db.profile.specs[currentSpecKey]
    if not specDB then
        WRA:PrintError("[RefreshPanel] Could not find specDB for key:", currentSpecKey)
        WRA.db.profile.specs[currentSpecKey] = {} -- Create empty table if needed
        specDB = WRA.db.profile.specs[currentSpecKey]
    end
    WRA:PrintDebug("[RefreshPanel] Using specDB for:", currentSpecKey)

    -- 3. Define the keys of the options to show in the quick panel
    --    These keys should match the keys defined in GetSpecOptions_YourSpec()
    local quickOptionKeys = {}
    if currentSpecKey == "FuryWarrior" then
        quickOptionKeys = {
            "useWhirlwind",
            "useRend",
            "useOverpower",
            "smartAOE",
            "enableCleave",
            "useRecklessness",
            "useDeathWish",
            "useBerserkerRage",
            -- Add other keys as needed
        }
    -- elseif currentSpecKey == "SomeOtherSpec" then
    --     quickOptionKeys = { "key1", "key2" }
    end

    -- 4. Get the full options table from the spec module to retrieve labels etc.
    local fullSpecOptions = nil
    local getOptionsFuncName = "GetSpecOptions_" .. currentSpecKey
    if WRA[getOptionsFuncName] and type(WRA[getOptionsFuncName]) == "function" then
        fullSpecOptions = WRA[getOptionsFuncName](WRA)
    end

    if not fullSpecOptions then
        WRA:PrintError("[RefreshPanel] Could not retrieve full spec options table from", getOptionsFuncName)
        -- Add a label indicating no options available
        local label = WRA.AceGUI:Create("Label")
        label:SetText(L["No quick options available."]) -- Use Locale
        label:SetFullWidth(true)
        quickPanelFrame:AddChild(label)
        quickPanelFrame:DoLayout()
        return
    end

    -- 5. Iterate through the desired keys and create widgets
    WRA:PrintDebug("[RefreshPanel] Adding widgets based on dynamic definition...")
    local widgetCount = 0
    if #quickOptionKeys > 0 then
        for _, dbKey in ipairs(quickOptionKeys) do
            local optionDef = fullSpecOptions[dbKey] -- Get the definition from the full options table

            if optionDef and optionDef.type == "toggle" then -- Only handle toggles for now
                WRA:PrintDebug("[RefreshPanel] Creating widget for:", dbKey) -- DEBUG
                local displayLabel = L[optionDef.name] or optionDef.name -- Use localized name or fallback

                local checkbox = WRA.AceGUI:Create("CheckBox")
                checkbox:SetLabel(displayLabel)
                checkbox:SetValue(specDB[dbKey] or false) -- Get value from DB
                checkbox:SetUserData("key", dbKey) -- Store the key

                -- Set the callback to directly modify the spec's DB table
                checkbox:SetCallback("OnValueChanged", function(widget, event, value)
                    specDB[dbKey] = value -- Directly set the value
                    WRA:PrintDebug("[QuickPanel Callback] Checkbox", dbKey, "set to", tostring(value), "in specDB:", currentSpecKey) -- DEBUG
                end)

                quickPanelFrame:AddChild(checkbox) -- Add the created checkbox
                widgetCount = widgetCount + 1
            else
                WRA:PrintDebug("[RefreshPanel] Skipping key:", dbKey, "- Definition not found or not a toggle.")
            end
        end
    end

    if widgetCount == 0 then
         -- Add a label if no suitable options were found/defined
         local label = WRA.AceGUI:Create("Label")
         label:SetText(L["No quick options available."]) -- Use Locale
         label:SetFullWidth(true)
         quickPanelFrame:AddChild(label)
         widgetCount = 1
    end

    WRA:PrintDebug("[RefreshPanel] Finished adding widgets. Count:", widgetCount)

    -- 6. Update layout
    quickPanelFrame:DoLayout()

    WRA:PrintDebug("Quick Panel Refreshed.")
end


function QuickConfig:ToggleFrame()
    local WRA = AceAddon:GetAddon(addonName)
    if not WRA then
        print(addonName .. " QuickConfig: Cannot toggle panel, WRA instance not found.")
        return
    end
    WRA:PrintDebug("[QuickConfig:ToggleFrame] Function called.") -- Use Module name

    -- Use WRA.AceGUI reference for creating the window (assuming it's stored in WRA.lua)
    if not WRA.AceGUI or type(WRA.AceGUI.Create) ~= "function" then
        WRA:PrintError("[QuickConfig:ToggleFrame] Cannot create frame, WRA.AceGUI reference is invalid!")
        return
    end

    if not quickPanelFrame then
        WRA:PrintDebug("[QuickConfig:ToggleFrame] Creating quick panel frame...")
        -- Use "Window" for title bar and draggability
        quickPanelFrame = WRA.AceGUI:Create("Window") -- Use stored AceGUI reference
        quickPanelFrame:SetTitle(addonName .. " " .. L["Quick Settings"]) -- Set title, use Locale
        quickPanelFrame:SetLayout("Flow") -- Use "Flow" or "List" layout
        quickPanelFrame:SetWidth(200)  -- Keep a fixed width or set to "auto" if desired
        quickPanelFrame:SetHeight(220) -- Increased default height further (adjust as needed)
        quickPanelFrame:EnableResize(true) -- Allow manual resizing

        quickPanelFrame.frame:SetFrameStrata("HIGH") -- Keep on top
        quickPanelFrame.frame:SetMovable(true) -- Explicitly ensure movable
        quickPanelFrame.frame:EnableMouse(true) -- Ensure mouse interaction
        quickPanelFrame.frame:ClearAllPoints()
        quickPanelFrame.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -50) -- Initial position

        -- Add padding to the bottom of the content frame
        if quickPanelFrame.content then
             quickPanelFrame.content:ClearAllPoints()
             quickPanelFrame.content:SetPoint("TOPLEFT", 5, -25)
             quickPanelFrame.content:SetPoint("TOPRIGHT", -5, -25)
             quickPanelFrame.content:SetPoint("BOTTOMLEFT", 5, 30)
             quickPanelFrame.content:SetPoint("BOTTOMRIGHT", -25, 30)
             WRA:PrintDebug("[QuickConfig:ToggleFrame] Adjusted content frame anchors.") -- DEBUG
        else
             WRA:PrintError("[QuickConfig:ToggleFrame] Could not find quickPanelFrame.content to adjust anchors!")
        end

        quickPanelFrame:Hide() -- Start hidden

        -- Register frame with AceGUI to handle cleanup if needed (optional but good practice)
        WRA.AceGUI:RegisterAsContainer(quickPanelFrame) -- Use stored AceGUI reference

        -- Call RefreshPanel using self (which is the QuickConfig module instance)
        -- This will populate the frame the first time it's created
        WRA:PrintDebug("[QuickConfig:ToggleFrame] Calling RefreshPanel after frame creation...") -- DEBUG
        self:RefreshPanel()
    end

    if quickPanelFrame.frame:IsShown() then
        WRA:PrintDebug("[QuickConfig:ToggleFrame] Hiding frame.")
        quickPanelFrame:Hide()
    else
        WRA:PrintDebug("[QuickConfig:ToggleFrame] Showing frame.")
        -- Refresh content *before* showing to ensure it's up-to-date
        WRA:PrintDebug("[QuickConfig:ToggleFrame] Calling RefreshPanel before Show()...")
        self:RefreshPanel()
        quickPanelFrame:Show()
    end
end

-- Function to explicitly show launcher buttons
function QuickConfig:ShowLauncherButtons()
    CurrentWRA:PrintDebug("[QuickConfig:ShowLauncherButtons] Attempting to show buttons...") -- DEBUG
    -- Ensure buttons exist before showing
    if not configLauncherButton or not quickPanelButton then
        CreateLauncherButtons() -- Create them if they are missing
    end
    -- Add checks for button validity
    if configLauncherButton and configLauncherButton.Show then
        configLauncherButton:Show()
        CurrentWRA:PrintDebug("[QuickConfig:ShowLauncherButtons] Config button shown.") -- DEBUG
    else
         CurrentWRA:PrintError("[QuickConfig:ShowLauncherButtons] Config button is nil or invalid after creation attempt!") -- DEBUG
    end
    if quickPanelButton and quickPanelButton.Show then
        quickPanelButton:Show()
        CurrentWRA:PrintDebug("[QuickConfig:ShowLauncherButtons] Quick button shown.") -- DEBUG
    else
        CurrentWRA:PrintError("[QuickConfig:ShowLauncherButtons] Quick button is nil or invalid after creation attempt!") -- DEBUG
    end
end

-- Function to explicitly hide launcher buttons
function QuickConfig:HideLauncherButtons()
    CurrentWRA:PrintDebug("[QuickConfig:HideLauncherButtons] Attempting to hide buttons...") -- DEBUG
    if configLauncherButton and configLauncherButton.Hide then configLauncherButton:Hide() end
    if quickPanelButton and quickPanelButton.Hide then quickPanelButton:Hide() end
    CurrentWRA:PrintDebug("[QuickConfig:HideLauncherButtons] Buttons hidden.")
end

-- Function to explicitly hide the quick panel
function QuickConfig:HideQuickPanel()
    if quickPanelFrame and quickPanelFrame.Hide then -- Check if frame and Hide method exist
        if quickPanelFrame.frame and quickPanelFrame.frame:IsShown() then
            quickPanelFrame:Hide()
            CurrentWRA:PrintDebug("[QuickConfig:HideQuickPanel] Panel hidden.")
        end
    end
end


-- Module Lifecycle Methods
function QuickConfig:OnInitialize()
    CurrentWRA:PrintDebug("[QuickConfig:OnInitialize] Module Initialized.")
    -- Schedule button creation slightly delayed to ensure WRA is ready
    self:ScheduleTimer(CreateLauncherButtons, 0.1)
end
function QuickConfig:OnEnable()
    CurrentWRA:PrintDebug("[QuickConfig:OnEnable] Module Enabled.")
    -- Show buttons when module is enabled (will create if needed)
    self:ShowLauncherButtons()
end
function QuickConfig:OnDisable()
    CurrentWRA:PrintDebug("[QuickConfig:OnDisable] Module Disabled.")
    -- Hide UI elements when the module is disabled by AceAddon
    self:HideLauncherButtons()
    self:HideQuickPanel()
    CurrentWRA:PrintDebug("QuickConfig UI elements hidden for disable.")
    -- Note: Don't release quickPanelFrame here, AceAddon handles module cleanup.
    -- Releasing it might cause issues if the addon is re-enabled without a full reload.
end


-- --- Event Handling ---
-- Keep PLAYER_LOGIN event to schedule initial button creation
local eventFrame = CreateFrame("Frame", "WRA_QuickConfigEventFrame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        local EventWRA = AceAddon:GetAddon(addonName); if not EventWRA then return end
        EventWRA:PrintDebug("PLAYER_LOGIN detected by QuickConfig.")
        local QCModule = EventWRA:GetModule("QuickConfig")
        if QCModule then
            -- Schedule button creation slightly after login to ensure other modules might be ready
            if QCModule.ScheduleTimer then
                 QCModule:ScheduleTimer(CreateLauncherButtons, 0.8) -- Increased delay slightly
                 EventWRA:PrintDebug("QuickConfig: Scheduled CreateLauncherButtons.") -- DEBUG
            else
                 EventWRA:PrintError("QuickConfig: ScheduleTimer method not found on QCModule! Cannot schedule button creation.")
            end
        else
            EventWRA:PrintError("QuickConfig: QuickConfig module not found, cannot schedule button creation.")
        end
        self:UnregisterEvent("PLAYER_LOGIN") -- Unregister after first login
    end
end)
