-- UI/DisplayManager.lua
-- Manages the visual display of rotation suggestions.
-- v4: Modified UpdateAction to accept a table of actions {gcdAction, offGcdAction}.
-- 基于用户提供的版本进行修正

local addonName, _ = ... -- Get addon name, don't need addonTable
local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0") -- Get AceAddon library first
local WRA = AceAddon:GetAddon(addonName) -- *** Correctly get the main addon object ***
local L = LibStub("AceLocale-3.0"):GetLocale(addonName) -- Localization

-- Create the DisplayManager module
local DisplayManager = WRA:NewModule("DisplayManager", "AceTimer-3.0") -- 添加 AceTimer-3.0 依赖
-- WRA.DisplayManager = DisplayManager -- 主文件 WRA.lua 中应该已经做了 WRA.DisplayManager = DisplayManager

-- Lua shortcuts
local pairs = pairs
local type = type
local wipe = wipe -- Added wipe shortcut
local string_format = string.format

-- Module Variables
local activeDisplayModule = nil
local activeDisplayName = nil
local availableDisplays = {} -- Stores registered display backends { [name] = moduleInstance }
local DB = nil -- 将在 OnInitialize 中从 WRA.db.profile 获取

local DEFAULT_DISPLAY_NAME = "Icons" -- 默认显示模式

-- --- Module Lifecycle ---

function DisplayManager:OnInitialize()
    if WRA.db and WRA.db.profile then
        -- 确保 displayManager 的数据库子表存在
        if not WRA.db.profile.displayManager then
            WRA.db.profile.displayManager = {}
        end
        DB = WRA.db.profile.displayManager -- 指向 displayManager 的特定配置
        if DB.selectedDisplay == nil then
            DB.selectedDisplay = DEFAULT_DISPLAY_NAME -- 初始化默认选择
        end
    else
        WRA:PrintError("[DisplayManager:OnInitialize] 错误：无法获取数据库引用！")
        -- 创建一个临时的DB表以避免后续错误，但这表示存在更深层的问题
        DB = { selectedDisplay = DEFAULT_DISPLAY_NAME }
    end
    activeDisplayModule = nil
    activeDisplayName = nil
    wipe(availableDisplays) -- 确保在初始化时清空，注册稍后进行
    WRA:PrintDebug("[DisplayManager:OnInitialize] 已初始化")
end

function DisplayManager:OnEnable()
    if not DB then
        if WRA.db and WRA.db.profile and WRA.db.profile.displayManager then
            DB = WRA.db.profile.displayManager
        else
            WRA:PrintError("[DisplayManager:OnEnable] 错误：无法启用，缺少数据库引用！")
            return
        end
    end
    WRA:PrintDebug("[DisplayManager:OnEnable] 已启用")
    
    -- 使用计时器延迟选择，给显示模块注册时间
    self:ScheduleTimer("AttemptInitialDisplaySelection", 0.1)
    WRA:PrintDebug("[DisplayManager:OnEnable] 尝试选择显示模块已计划:", DB.selectedDisplay or DEFAULT_DISPLAY_NAME)
end

function DisplayManager:AttemptInitialDisplaySelection()
    if not activeDisplayModule then -- 仅当还没有活动模块时才尝试
        local targetDisplay = DB.selectedDisplay or DEFAULT_DISPLAY_NAME
        WRA:PrintDebug("[DisplayManager:AttemptInitialDisplaySelection] 尝试选择显示模块: " .. targetDisplay)
        
        if self:GetAvailableDisplayNamesCount() == 0 then
            WRA:PrintDebug("[DisplayManager:AttemptInitialDisplaySelection] availableDisplays 为空。等待模块注册。")
            -- 可以考虑如果一段时间后仍然为空，则报错
            if not self.initialDisplayAttemptTimer then
                 self.initialDisplayAttemptTimer = self:ScheduleTimer("AttemptInitialDisplaySelection", 0.5) -- 再试一次
            end
            return
        end
        
        if self.initialDisplayAttemptTimer then
            self:CancelTimer(self.initialDisplayAttemptTimer, true)
            self.initialDisplayAttemptTimer = nil
        end

        if availableDisplays[targetDisplay] then
            self:SelectDisplay(targetDisplay)
        elseif availableDisplays[DEFAULT_DISPLAY_NAME] then
            WRA:PrintDebug(string_format("[DisplayManager:AttemptInitialDisplaySelection] 未找到 '%s', 回退到默认 '%s'", targetDisplay, DEFAULT_DISPLAY_NAME))
            self:SelectDisplay(DEFAULT_DISPLAY_NAME)
        elseif next(availableDisplays) then
            for name, _ in pairs(availableDisplays) do
                WRA:PrintDebug(string_format("[DisplayManager:AttemptInitialDisplaySelection] 默认也未找到, 回退到第一个可用 '%s'", name))
                self:SelectDisplay(name)
                return -- 选择第一个后即返回
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
    self:HideDisplay()
    -- WRA:PrintDebug("[DisplayManager:OnDisable] Kept active display reference:", activeDisplayName or "None") -- 保留引用可能导致问题，通常在禁用时应清理
end

-- --- Public API ---

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
        WRA:PrintDebug(string_format("[%.3f] [DisplayManager:RegisterDisplay] 注册新的显示后端: %s", now, name))
        availableDisplays[name] = moduleInstance
        
        -- 如果这是第一个注册的模块，或者它是用户选择的模块但尚未激活，则尝试激活
        if not activeDisplayModule and ((DB and DB.selectedDisplay == name) or (not DB or not DB.selectedDisplay and name == DEFAULT_DISPLAY_NAME)) then
            WRA:PrintDebug(string_format("[DisplayManager:RegisterDisplay] 自动选择新注册的模块: %s", name))
            self:SelectDisplay(name)
        elseif not activeDisplayModule and self:GetAvailableDisplayNamesCount() == 1 then -- 如果是唯一一个
            WRA:PrintDebug(string_format("[DisplayManager:RegisterDisplay] 自动选择第一个注册的模块: %s", name))
            self:SelectDisplay(name)
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

    if self:GetAvailableDisplayNamesCount() == 0 then -- 使用辅助函数检查
        WRA:PrintError("[DisplayManager:SelectDisplay] 错误：availableDisplays 表为空！无法选择任何显示模块。")
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
        end
        if not newDisplayModule then
            WRA:PrintError(string_format("[DisplayManager:SelectDisplay] 错误：回退显示模块 '%s' 在选择期间也未找到或注册。", fallbackName))
            -- 不要将 activeDisplayModule 设置为 nil，除非确实无法恢复
            return -- 直接返回，不改变当前状态
        end
    end

    if activeDisplayModule == newDisplayModule and activeDisplayName == name then
         WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 显示模块 %s 已激活。", now, name))
         -- 确保即使已激活，如果插件启用，它也是可见的
         if WRA.db.profile.enabled and newDisplayModule.Show then
             WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 确保已激活的显示模块 %s 是可见的。", now, name))
             if newDisplayModule.CreateDisplayElements then newDisplayModule:CreateDisplayElements() end -- 确保元素存在
             if newDisplayModule.UpdateFrameAppearanceAndLayout then newDisplayModule:UpdateFrameAppearanceAndLayout() end
             newDisplayModule:Show()
         end
        return
    end

    if activeDisplayModule and activeDisplayModule.Hide then -- 检查 Hide 方法是否存在
        WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 隐藏旧的显示模块: %s", now, activeDisplayName or "未知"))
        activeDisplayModule:Hide()
    end

    WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 选择新的显示后端: %s", now, name))
    activeDisplayModule = newDisplayModule
    activeDisplayName = name

    if activeDisplayModule.OnModuleSelected then -- 新增：通知模块它被选中了
        activeDisplayModule:OnModuleSelected()
    end
    
    -- 确保在调用Show之前，模块的Enable方法被调用（如果它实现了AceAddon的Enable）
    -- AceAddon模块通常在被WRA:NewModule创建时会自动处理Enable/Disable状态，
    -- 但如果显示模块不是标准的AceAddon模块，可能需要手动管理。
    -- 对于Display_Icons，它是一个WRA:NewModule，其OnEnable应该由WRA主插件控制。
    -- 此处主要确保其UI元素被正确创建和显示。

    DB.selectedDisplay = name -- 保存用户的选择

    if WRA.db.profile.enabled then -- 检查主插件的启用状态
        WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 为新模块调用 ShowDisplay: %s", now, name))
        self:ShowDisplay() -- ShowDisplay内部会处理CreateElements和Layout
    else
        WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 插件已禁用，不显示新模块: %s", now, name))
    end
    WRA:PrintDebug(string_format("[%.3f] [DisplayManager:SelectDisplay] 选择完成: %s", now, name))
    WRA:SendMessage("WRA_DISPLAY_MODULE_CHANGED", name) -- 通知选项面板等模块
end

-- MODIFIED: UpdateAction now accepts a table of actions
-- actionsTable is expected to be { gcdAction = actionID1, offGcdAction = actionID2 }
function DisplayManager:UpdateAction(actionsTable)
    -- local now = GetTime() -- 减少日志垃圾
    -- WRA:PrintDebug(string_format("[%.3f] [DisplayManager] Received UpdateAction call.", now)) 

    if activeDisplayModule and activeDisplayModule.UpdateDisplay then
        -- WRA:PrintDebug(string_format("[%.3f] [DisplayManager] Forwarding actionsTable to display backend: %s", now, activeDisplayName or "Unknown"))
        activeDisplayModule:UpdateDisplay(actionsTable)
    else
        -- 此调试信息如果每帧都因无活动显示而打印，可能会过于频繁
        -- if not activeDisplayModule then
        --     WRA:PrintDebug(string_format("[%.3f] [DisplayManager] Cannot update display - activeDisplayModule is nil.", now))
        -- elseif not activeDisplayModule.UpdateDisplay then
        --     WRA:PrintDebug(string_format("[%.3f] [DisplayManager] Cannot update display - activeDisplayModule (%s) is missing UpdateDisplay method.", now, activeDisplayName or "Unknown"))
        -- end
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
    if activeDisplayModule and activeDisplayModule.ResetPosition then -- 检查原始文件中使用的函数名
        activeDisplayModule:ResetPosition()
        WRA:Print(L["DISPLAY_POSITION_RESET"]) -- 使用 L 键
    elseif activeDisplayModule then
        WRA:Print(string_format("警告：活动显示模块 [%s] 不支持 ResetPosition。", activeDisplayName or "?"))
    else
        WRA:Print("没有活动的显示模块来重置位置。")
    end
end

function DisplayManager:GetAvailableDisplayTypes() -- 函数名在原始文件中是这个
    local types = {}
    for name, _ in pairs(availableDisplays) do types[name] = name end -- 原始文件逻辑
    -- 原始文件中的这行似乎是为了确保 "Icons" 总是存在，但如果它未注册则不应强制添加
    -- if not types["Icons"] and availableDisplays["Icons"] then types["Icons"] = "Icons" end 
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
function DisplayManager:GetCurrentDisplayName() return activeDisplayName end -- 新增，方便外部获取

function DisplayManager:OpenConfiguration()
    if activeDisplayModule and activeDisplayModule.OpenConfiguration then 
        activeDisplayModule:OpenConfiguration() 
    else 
        WRA:Print("活动显示模块没有特定的配置界面。")
    end
end

-- 添加一个获取选项表的函数，供OptionsPanel使用
function DisplayManager:GetOptionsTable()
    local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
    if not L then L = setmetatable({}, {__index=function(t,k) return k end}) end -- 本地化回退

    local displayValuesFunc = function() -- 改为函数以动态获取
        local values = {}
        local displayNames = self:GetAvailableDisplayTypes() -- 使用原始函数名
        if next(displayNames) == nil then
            values["NONE_REGISTERED"] = L["NO_DISPLAY_MODULES_REGISTERED"] or "No display modules registered"
        else
            for key, val in pairs(displayNames) do
                values[key] = L[val] or val -- 尝试本地化显示名称
            end
        end
        return values
    end

    return {
        type = "group", -- 返回一个group，让OptionsPanel可以正确合并
        name = L["DISPLAY_MANAGER_SETTINGS_HEADER"] or "Display Manager Settings",
        order = 1, -- 在Display_Icons等具体模块选项之前
        args = {
            selectedDisplay = {
                order = 1,
                type = "select",
                name = L["SELECT_DISPLAY_MODE_NAME"] or "Display Mode",
                desc = L["SELECT_DISPLAY_MODE_DESC"] or "Choose the visual style for rotation suggestions.",
                get = function(info) return DB and DB.selectedDisplay or DEFAULT_DISPLAY_NAME end,
                set = function(info, value)
                    if DB then DB.selectedDisplay = value end
                    self:SelectDisplay(value)
                    WRA:SendMessage("WRA_DISPLAY_MODULE_CHANGED", value) -- 通知OptionsPanel刷新
                end,
                values = displayValuesFunc, -- 使用函数
            },
        }
    }
end
