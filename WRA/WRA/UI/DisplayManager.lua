-- UI/DisplayManager.lua
-- Manages the visual display of rotation suggestions.
-- v6: More robust GetOptionsTable and selection logic.

local addonName, _ = ...
local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0")
local WRA = AceAddon:GetAddon(addonName)
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local DisplayManager = WRA:NewModule("DisplayManager", "AceEvent-3.0", "AceTimer-3.0")

local pairs = pairs
local type = type
local wipe = wipe
local string_format = string.format
local next = next

local activeDisplayModule = nil
local activeDisplayName = nil
local availableDisplays = {}
local DB = nil

local DEFAULT_DISPLAY_NAME = "Icons" -- Default display type
local INITIAL_DISPLAY_ATTEMPT_DELAY = 0.25 -- Delay for first attempt
local INITIAL_DISPLAY_RETRY_DELAY = 0.75  -- Delay for retry if no displays found

function DisplayManager:OnInitialize()
    if WRA.db and WRA.db.profile then
        if not WRA.db.profile.displayManager then
            WRA.db.profile.displayManager = {}
        end
        DB = WRA.db.profile.displayManager
        if DB.selectedDisplay == nil or DB.selectedDisplay == "NONE_REGISTERED" then -- Ensure invalid value isn't kept
            DB.selectedDisplay = DEFAULT_DISPLAY_NAME
        end
    else
        WRA:PrintError("[DisplayManager:OnInitialize] 错误：无法获取数据库引用！")
        DB = { selectedDisplay = DEFAULT_DISPLAY_NAME }
    end
    activeDisplayModule = nil
    activeDisplayName = nil
    wipe(availableDisplays)
    WRA:PrintDebug("[DisplayManager:OnInitialize] 已初始化. DB.selectedDisplay:", DB.selectedDisplay)
end

function DisplayManager:OnEnable()
    if not DB then
        if WRA.db and WRA.db.profile and WRA.db.profile.displayManager then
            DB = WRA.db.profile.displayManager
            if DB.selectedDisplay == "NONE_REGISTERED" then DB.selectedDisplay = DEFAULT_DISPLAY_NAME end
        else
            WRA:PrintError("[DisplayManager:OnEnable] 错误：无法启用，缺少数据库引用！")
            return
        end
    end
    WRA:PrintDebug("[DisplayManager:OnEnable] 已启用")

    if self.initialDisplayAttemptTimer then
        self:CancelTimer(self.initialDisplayAttemptTimer, true)
        self.initialDisplayAttemptTimer = nil
    end
    self.initialDisplayAttemptTimer = self:ScheduleTimer("AttemptInitialDisplaySelection", INITIAL_DISPLAY_ATTEMPT_DELAY)
    WRA:PrintDebug("[DisplayManager:OnEnable] 尝试选择显示模块已计划:", DB.selectedDisplay or DEFAULT_DISPLAY_NAME, "延迟:", INITIAL_DISPLAY_ATTEMPT_DELAY)
end

function DisplayManager:AttemptInitialDisplaySelection()
    self.initialDisplayAttemptTimer = nil

    if not activeDisplayModule then
        local targetDisplay = DB.selectedDisplay or DEFAULT_DISPLAY_NAME
        WRA:PrintDebug(string_format("[DisplayManager:AttemptInitialDisplaySelection] 尝试选择显示模块: %s. 当前活动: %s", targetDisplay, activeDisplayName or "无"))

        if self:GetAvailableDisplayNamesCount() == 0 then
            WRA:PrintDebug("[DisplayManager:AttemptInitialDisplaySelection] availableDisplays 为空。计划重试。")
            if not self.initialDisplayRetryTimer then
                self.initialDisplayRetryTimer = self:ScheduleTimer(function()
                    self.initialDisplayRetryTimer = nil
                    WRA:PrintDebug("[DisplayManager Retry Timer] Retrying AttemptInitialDisplaySelection...")
                    self:AttemptInitialDisplaySelection()
                end, INITIAL_DISPLAY_RETRY_DELAY)
            end
            return
        end

        if self.initialDisplayRetryTimer then
            self:CancelTimer(self.initialDisplayRetryTimer, true)
            self.initialDisplayRetryTimer = nil
        end

        -- Validate targetDisplay before attempting to select
        if not availableDisplays[targetDisplay] then
            WRA:PrintDebug(string_format("[DisplayManager:AttemptInitialDisplaySelection] 目标显示 '%s' 不可用. 尝试默认 '%s'.", targetDisplay, DEFAULT_DISPLAY_NAME))
            targetDisplay = DEFAULT_DISPLAY_NAME
        end

        if availableDisplays[targetDisplay] then
            self:SelectDisplay(targetDisplay)
        elseif next(availableDisplays) then -- Fallback to the first available if default also fails
            for name, _ in pairs(availableDisplays) do
                WRA:PrintDebug(string_format("[DisplayManager:AttemptInitialDisplaySelection] 默认 '%s' 也未找到, 回退到第一个可用 '%s'", targetDisplay, name))
                self:SelectDisplay(name)
                return
            end
        else
            WRA:PrintError("[DisplayManager:AttemptInitialDisplaySelection] 错误：没有可用的显示模块！")
        end
    else
        WRA:PrintDebug("[DisplayManager:AttemptInitialDisplaySelection] 已有活动显示模块: " .. (activeDisplayName or "未知"))
    end
end


function DisplayManager:OnDisable()
    WRA:PrintDebug("[DisplayManager:OnDisable] 已禁用")
    if self.initialDisplayAttemptTimer then
        self:CancelTimer(self.initialDisplayAttemptTimer, true)
        self.initialDisplayAttemptTimer = nil
    end
    if self.initialDisplayRetryTimer then
        self:CancelTimer(self.initialDisplayRetryTimer, true)
        self.initialDisplayRetryTimer = nil
    end
    self:HideDisplay()
end

function DisplayManager:RegisterDisplay(name, moduleInstance)
    local now = GetTime()
    WRA:PrintDebug(string_format("[%.3f] [DisplayManager:RegisterDisplay] 尝试注册显示模块: %s", now, name))

    if not name or not moduleInstance then
        WRA:PrintError("[DisplayManager:RegisterDisplay] 错误：需要提供名称和模块实例。")
        return
    end
    if type(moduleInstance.UpdateDisplay) ~= "function" then
         WRA:PrintError(string_format("[DisplayManager:RegisterDisplay] 错误：显示模块 [%s] 缺少必需的 UpdateDisplay 函数。", name))
         return
    end
    if not availableDisplays[name] then
        WRA:PrintDebug(string_format("[%.3f] [DisplayManager:RegisterDisplay] 注册新的显示后端: %s. 类型: %s", now, name, type(moduleInstance)))
        availableDisplays[name] = moduleInstance

        if not activeDisplayModule and ((DB and DB.selectedDisplay == name) or (not DB or not DB.selectedDisplay and name == DEFAULT_DISPLAY_NAME)) then
            WRA:PrintDebug(string_format("[DisplayManager:RegisterDisplay] 自动选择新注册的模块: %s (因为它是选定的或默认的)", name))
            self:SelectDisplay(name)
        elseif not activeDisplayModule and self:GetAvailableDisplayNamesCount() == 1 then
            WRA:PrintDebug(string_format("[DisplayManager:RegisterDisplay] 自动选择第一个注册的模块: %s (因为它是唯一一个)", name))
            self:SelectDisplay(name)
        else
            WRA:PrintDebug(string_format("[DisplayManager:RegisterDisplay] 模块 %s 已注册，但不是当前选定或唯一一个，等待显式选择或 OnEnable 触发。", name))
        end
    else
         WRA:PrintDebug(string_format("[%.3f] [DisplayManager:RegisterDisplay] 显示后端已注册: %s", now, name))
    end
end

function DisplayManager:SelectDisplay(name)
    local now = GetTime()
    WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 尝试选择显示模块: %s。当前活动: %s", now, name, activeDisplayName or "无"))

    if not DB then
        if WRA.db and WRA.db.profile and WRA.db.profile.displayManager then DB = WRA.db.profile.displayManager
        else WRA:PrintError("[DisplayManager:SelectDisplay] 错误：无法选择显示模块 - 数据库引用缺失。"); return
        end
    end

    if self:GetAvailableDisplayNamesCount() == 0 then
        WRA:PrintError(string_format("[DisplayManager:SelectDisplay] 错误：availableDisplays 表为空！无法选择 '%s'。", name))
        return
    end

    local newDisplayModule = availableDisplays[name]
    if not newDisplayModule then
        WRA:PrintError(string_format("[DisplayManager:SelectDisplay] 错误：在选择期间未找到显示后端: %s", name))
        local fallbackName = DEFAULT_DISPLAY_NAME
        if name ~= fallbackName and availableDisplays[fallbackName] then
             WRA:PrintDebug(string_format("[DisplayManager:SelectDisplay] 回退到 '%s' 显示模块。", fallbackName))
             name = fallbackName
             newDisplayModule = availableDisplays[name]
        elseif next(availableDisplays) then -- If default also not found, pick first available
            for firstAvailableName, _ in pairs(availableDisplays) do
                WRA:PrintDebug(string_format("[DisplayManager:SelectDisplay] 默认和请求的模块都未找到, 回退到第一个可用 '%s'", firstAvailableName))
                name = firstAvailableName
                newDisplayModule = availableDisplays[name]
                break
            end
        end

        if not newDisplayModule then
            WRA:PrintError(string_format("[DisplayManager:SelectDisplay] 错误：回退显示模块 '%s' 在选择期间也未找到或注册。", name))
            return
        end
    end

    if activeDisplayModule == newDisplayModule and activeDisplayName == name then
         WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 显示模块 %s 已激活。", now, name))
         if WRA.db.profile.enabled and newDisplayModule.Show then
             WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 确保已激活的显示模块 %s 是可见的。", now, name))
             if newDisplayModule.CreateDisplayElements then newDisplayModule:CreateDisplayElements() end
             if newDisplayModule.UpdateFrameAppearanceAndLayout then newDisplayModule:UpdateFrameAppearanceAndLayout() end
             newDisplayModule:Show()
         end
        return
    end

    if activeDisplayModule and activeDisplayModule.Hide then
        WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 隐藏旧的显示模块: %s", now, activeDisplayName or "未知"))
        activeDisplayModule:Hide()
    end

    WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 选择新的显示后端: %s", now, name))
    activeDisplayModule = newDisplayModule
    activeDisplayName = name

    if activeDisplayModule.OnModuleSelected then
        activeDisplayModule:OnModuleSelected()
    end

    DB.selectedDisplay = name -- Save the valid selection

    if WRA.db.profile.enabled then
        WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 为新模块调用 ShowDisplay: %s", now, name))
        self:ShowDisplay()
    else
        WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 插件已禁用，不显示新模块: %s", now, name))
    end
    WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 选择完成: %s", now, name))
    WRA:SendMessage("WRA_DISPLAY_MODULE_CHANGED", name)
end

function DisplayManager:UpdateAction(actionsTable)
    if activeDisplayModule and activeDisplayModule.UpdateDisplay then
        activeDisplayModule:UpdateDisplay(actionsTable)
    end
end

function DisplayManager:ShowDisplay()
     local now = GetTime()
     WRA:PrintDebug(string_format("[%.3f] [DisplayManager:ShowDisplay] 已调用。活动显示模块: %s", now, activeDisplayName or "无"))
    if activeDisplayModule then
        if activeDisplayModule.CreateDisplayElements then activeDisplayModule:CreateDisplayElements() end
        if activeDisplayModule.UpdateFrameAppearanceAndLayout then activeDisplayModule:UpdateFrameAppearanceAndLayout() end
        if activeDisplayModule.Show then
            activeDisplayModule:Show()
        else
            WRA:PrintDebug(string_format("[%.3f] [DisplayManager:ShowDisplay] 无法显示，活动显示模块 (%s) 缺少 Show() 方法。", now, activeDisplayName or "未知"))
        end
    else
        WRA:PrintDebug(string_format("[%.3f] [DisplayManager:ShowDisplay] 无法显示，activeDisplayModule 为 nil。", now))
    end
end

function DisplayManager:HideDisplay()
     local now = GetTime()
     WRA:PrintDebug(string_format("[%.3f] [DisplayManager:HideDisplay] 已调用。活动显示模块: %s", now, activeDisplayName or "无"))
     if activeDisplayModule and activeDisplayModule.Hide then
         activeDisplayModule:Hide()
     end
end

function DisplayManager:ResetDisplayPosition()
    if activeDisplayModule and activeDisplayModule.ResetPosition then
        activeDisplayModule:ResetPosition()
        WRA:Print(L["DISPLAY_POSITION_RESET"])
    elseif activeDisplayModule then
        WRA:Print(string.format("警告：活动显示模块 [%s] 不支持 ResetPosition。", activeDisplayName or "?"))
    else
        WRA:Print("没有活动的显示模块来重置位置。")
    end
end

function DisplayManager:GetAvailableDisplayTypes()
    local types = {}
    for name, _ in pairs(availableDisplays) do types[name] = name end
    return types
end

function DisplayManager:GetAvailableDisplayNamesCount()
    local count = 0
    for _ in pairs(availableDisplays) do
        count = count + 1
    end
    return count
end

function DisplayManager:GetCurrentDisplay() return activeDisplayModule end
function DisplayManager:GetCurrentDisplayName() return activeDisplayName end

function DisplayManager:OpenConfiguration()
    if activeDisplayModule and activeDisplayModule.OpenConfiguration then
        activeDisplayModule:OpenConfiguration()
    else
        WRA:Print("活动显示模块没有特定的配置界面。")
    end
end

function DisplayManager:GetOptionsTable()
    local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
    if not L then L = setmetatable({}, {__index=function(t,k) return k end}) end

    local displayValuesFunc = function()
        local values = {}
        local displayNames = self:GetAvailableDisplayTypes()
        if next(displayNames) == nil then
            -- Provide a default option even if none are registered yet,
            -- but ensure it's clear it's a placeholder or the intended default.
            values[DEFAULT_DISPLAY_NAME] = L[DEFAULT_DISPLAY_NAME] or DEFAULT_DISPLAY_NAME -- Show "Icons"
            WRA:PrintDebug("[DisplayManager:GetOptionsTable:displayValuesFunc] No displays registered, offering default:", DEFAULT_DISPLAY_NAME)
        else
            for key, val in pairs(displayNames) do
                values[key] = L[val] or val
            end
        end
        return values
    end

    return {
        type = "group",
        name = L["DISPLAY_MANAGER_SETTINGS_HEADER"] or "Display Manager Settings",
        order = 1,
        args = {
            selectedDisplay = {
                order = 1,
                type = "select",
                name = L["SELECT_DISPLAY_MODE_NAME"] or "Display Mode",
                desc = L["SELECT_DISPLAY_MODE_DESC"] or "Choose the visual style for rotation suggestions.",
                get = function(info)
                    if not DB then return DEFAULT_DISPLAY_NAME end
                    -- Ensure the saved value is valid, otherwise return default
                    if availableDisplays[DB.selectedDisplay] then
                        return DB.selectedDisplay
                    elseif availableDisplays[DEFAULT_DISPLAY_NAME] then
                        return DEFAULT_DISPLAY_NAME
                    elseif next(availableDisplays) then -- Fallback to first available if default not there
                        for k, _ in pairs(availableDisplays) do return k end
                    end
                    return DEFAULT_DISPLAY_NAME -- Ultimate fallback
                end,
                set = function(info, value)
                    if not DB then WRA:PrintError("[DisplayManager:SetSelectedDisplay] DB is nil!"); return end

                    if availableDisplays[value] then
                        DB.selectedDisplay = value
                        self:SelectDisplay(value)
                        WRA:SendMessage("WRA_DISPLAY_MODULE_CHANGED", value)
                    else
                        WRA:PrintError(string.format("[DisplayManager:SetSelectedDisplay] Attempted to set invalid display '%s'. Reverting to default or first available.", value))
                        -- Attempt to set a valid default
                        if availableDisplays[DEFAULT_DISPLAY_NAME] then
                            DB.selectedDisplay = DEFAULT_DISPLAY_NAME
                            self:SelectDisplay(DEFAULT_DISPLAY_NAME)
                        elseif next(availableDisplays) then
                            for k, _ in pairs(availableDisplays) do
                                DB.selectedDisplay = k
                                self:SelectDisplay(k)
                                break
                            end
                        end
                        WRA:SendMessage("WRA_DISPLAY_MODULE_CHANGED", DB.selectedDisplay)
                    end
                end,
                values = displayValuesFunc,
            },
        }
    }
end
