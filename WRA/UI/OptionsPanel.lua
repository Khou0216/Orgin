-- wow addon/WRA/UI/OptionsPanel.lua
-- v5: Updated to use standardized localization keys for general and display settings.
-- 基于用户提供的版本进行修正

local addonName, _ = ... -- Get addon name, don't need addonTable
local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0") -- Get AceAddon library first
local WRA = AceAddon:GetAddon(addonName) -- *** Correctly get the main addon object ***

-- Request AceConfig libraries
local AceConfig = LibStub("AceConfig-3.0", true) -- 请求但不报错，后续检查
local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true) -- 新增，用于 NotifyChange
local L = LibStub("AceLocale-3.0"):GetLocale(addonName) -- Localization
local AceDBOptions = LibStub("AceDBOptions-3.0", true) -- Get AceDBOptions lib
local AceTimer = LibStub("AceTimer-3.0", true) -- 从原始文件中看，这里是需要的

-- Ensure Dialog, DBOptions, Timer are loaded (AceConfig checked later)
if not AceConfigDialog or not AceDBOptions or not AceTimer or not AceConfigRegistry then -- 增加 AceConfigRegistry 检查
    WRA:PrintError("OptionsPanel: 缺少核心 Ace 库 (AceConfigDialog, AceDBOptions, AceTimer, AceConfigRegistry)！") -- Use PrintError
    return
end

-- Create the OptionsPanel module *on the main addon object*
local OptionsPanel = WRA:NewModule("OptionsPanel", "AceTimer-3.0") -- 原始文件是 AceTimer-3.0
-- WRA.OptionsPanel = OptionsPanel -- 主文件 WRA.lua 中应该已经做了 WRA.OptionsPanel = OptionsPanel

-- *** Define a unique key for registering profile options ***
local PROFILE_OPTIONS_KEY = addonName .. "_Profiles"

-- *** Flag to track if profile panel has been added ***
OptionsPanel.profilePanelAdded = false -- 初始化标记

-- 主选项表定义 (基于原始文件结构)
local options = {
    name = addonName .. " " .. (L["SETTINGS_PANEL_TITLE"] or "Settings"), -- MODIFIED (使用 L 并提供回退)
    handler = WRA, -- Use WRA as the handler if get/set functions reference it
    type = "group",
    childGroups = "tab", -- 新增：使顶层组显示为标签页
    args = {
        general = {
            order = 1, type = "group", name = L["GENERAL_SETTINGS_HEADER"] or "General", -- MODIFIED
            args = {
                enabled = {
                    order = 1, type = "toggle", name = L["ENABLE_ADDON_NAME"] or "Enable Addon", desc = L["ENABLE_ADDON_DESC"] or "Enable/Disable the addon.", -- MODIFIED
                    get = function(info) return WRA.db.profile.enabled end,
                    set = function(info, value)
                        WRA.db.profile.enabled = value
                        if value then 
                            WRA:EnableAddonFeatures() -- 假设主WRA对象有此方法
                        else 
                            WRA:DisableAddonFeatures() -- 假设主WRA对象有此方法
                        end
                        if AceConfigRegistry then AceConfigRegistry:NotifyChange(addonName) end -- 通知更改
                    end,
                },
                debugMode = {
                    order = 10, type = "toggle", name = L["DEBUG_MODE_NAME"] or "Debug Mode", desc = L["DEBUG_MODE_DESC"] or "Enable debug messages.", -- MODIFIED
                    get = function(info) return WRA.db.profile.debugMode end,
                    set = function(info, value)
                        WRA.db.profile.debugMode = value
                        WRA:PrintDebug("调试模式已设置为:", tostring(value)) -- Print confirmation
                    end,
                },
            },
        },
        display = { -- 显示设置组 (合并了原始文件的 display 和 DisplayManager/Display_Icons 的选项)
            order = 2, type = "group", name = L["DISPLAY_SETTINGS_HEADER"] or "Display", desc = L["DISPLAY_SETTINGS_HEADER_DESC"] or "Configure display settings.", -- MODIFIED
            args = {
                -- DisplayManager 的选项将通过 GetOptionsTable 动态添加
                -- Display_Icons (或其他活动显示模块) 的选项也将动态添加
            },
        },
        specs = { -- 专精设置组
            order = 10, type = "group", name = L["SPEC_SETTINGS_HEADER"] or "Specialization", -- MODIFIED
            args = {}, -- `args` will be populated dynamically by AddSpecOptions
        },
        -- 配置文件案组将由 AceDBOptions 动态添加
    },
}

-- Called when the OptionsPanel module is initialized by AceAddon
function OptionsPanel:OnInitialize()
    -- **关键修复**：确保 WRA 主对象上有一个 AceConfigRegistry 实例的引用。
    -- 这通常在 WRA.lua 的 OnInitialize 中完成： WRA.AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
    if not AceConfig then -- 检查局部 AceConfig (来自 LibStub)
        WRA:PrintError("[OptionsPanel:OnInitialize] AceConfig-3.0 库未加载！无法注册选项。")
        return
    end
    if not WRA.AceConfigRegistry then -- 检查 WRA 对象上的引用
         WRA:PrintError("[OptionsPanel:OnInitialize] WRA.AceConfigRegistry 未在主插件中初始化！")
         -- 可以尝试在这里赋值，但不推荐，应该由主插件负责
         -- WRA.AceConfigRegistry = AceConfigRegistry 
    end


    -- 动态填充 display 组的 args
    if WRA.DisplayManager and WRA.DisplayManager.GetOptionsTable then
        local dmOptions = WRA.DisplayManager:GetOptionsTable()
        if dmOptions and dmOptions.args then -- 假设 GetOptionsTable 返回的是一个包含 args 的 group
            for k,v in pairs(dmOptions.args) do
                options.args.display.args[k] = v
            end
        elseif dmOptions then -- 如果直接返回 args 表
             for k,v in pairs(dmOptions) do
                options.args.display.args[k] = v
            end
        end
    end

    if WRA.DisplayManager and WRA.DisplayManager:GetCurrentDisplay() and WRA.DisplayManager:GetCurrentDisplay().GetOptionsTable then
        local currentDisplayOptions = WRA.DisplayManager:GetCurrentDisplay():GetOptionsTable()
        if currentDisplayOptions then
            -- 合并到 display.args，注意避免键名冲突，可以加前缀
            local prefix = (WRA.DisplayManager:GetCurrentDisplayName() or "currentDisplay") .. "_"
            local optsToMerge = currentDisplayOptions.args or currentDisplayOptions
            for k,v in pairs(optsToMerge) do
                options.args.display.args[prefix .. k] = v
                if not v.order then v.order = 200 end -- 确保有顺序
            end
        end
    end
    
    -- 注册主选项表
    AceConfigRegistry:RegisterOptionsTable(addonName, options, true) -- 使用 AceConfigRegistry
    WRA:PrintDebug("[OptionsPanel:OnInitialize] 已注册主选项表。")

    if AceConfigDialog then
        local panelDisplayName = addonName .. " " .. (L["SETTINGS_PANEL_TITLE"] or "Settings")
        self.optionsFrame = AceConfigDialog:AddToBlizOptions(addonName, panelDisplayName, nil) -- 移除 "general" 以显示顶级标签
        WRA.optionsFrame = self.optionsFrame
        WRA:PrintDebug("[OptionsPanel:OnInitialize] 已初始化并创建 Blizzard 面板。")
    else
        WRA:PrintError("[OptionsPanel:OnInitialize] AceConfigDialog 库未找到！无法创建 Blizzard 面板。")
    end

    -- 原始文件中的调试打印
    local specKeys = {}
    if options.args.specs and options.args.specs.args then
        for k,_ in pairs(options.args.specs.args) do table.insert(specKeys, k) end
    end
    WRA:PrintDebug("[OptionsPanel:OnInitialize] 初始 specs.args 键:", table.concat(specKeys, ", "))
end

-- Called when the module is enabled
function OptionsPanel:OnEnable()
    WRA:PrintDebug("[OptionsPanel:OnEnable] 已启用。计划注册和添加配置档案选项面板。")
    if AceConfigDialog and WRA.db and AceDBOptions and AceDBOptions.GetOptionsTable then -- 增加对 AceDBOptions.GetOptionsTable 的检查
        if not self.profilePanelAdded then
            self:ScheduleTimer(function()
                if self.profilePanelAdded then return end -- 再次检查标记

                WRA:PrintDebug("[OptionsPanel Timer - OnEnable] 正在注册和添加 AceDBOptions 配置档案面板...")
                local profileOptions = AceDBOptions:GetOptionsTable(WRA.db)

                if type(profileOptions) == "table" then
                    if not AceConfigRegistry then -- 再次检查
                        WRA:PrintError("[OptionsPanel Timer - OnEnable] AceConfigRegistry 未找到！无法注册配置档案选项。")
                        return
                    end
                    -- 使用 PROFILE_OPTIONS_KEY 注册配置档案选项表
                    AceConfigRegistry:RegisterOptionsTable(PROFILE_OPTIONS_KEY, profileOptions, true)
                    WRA:PrintDebug("[OptionsPanel Timer - OnEnable] 已注册配置档案选项表，键为:", PROFILE_OPTIONS_KEY)

                    local profilePanelName = addonName .. " " .. (L["PROFILES_PANEL_TITLE"] or "Profiles")
                    -- 使用 xpcall 以更安全地调用 AddToBlizOptions
                    -- 父级是 addonName，因此它显示为子类别
                    local success, err = xpcall(AceConfigDialog.AddToBlizOptions, geterrorhandler(), AceConfigDialog, PROFILE_OPTIONS_KEY, profilePanelName, addonName)
                    if success then
                         WRA:PrintDebug("[OptionsPanel Timer - OnEnable] 已添加配置档案面板:", profilePanelName, "父级为:", addonName)
                         self.profilePanelAdded = true -- 成功添加后设置标记
                    else
                         WRA:PrintError("[OptionsPanel Timer - OnEnable] 添加配置档案选项面板时出错:", err or "未知错误")
                    end
                else
                    WRA:PrintError("[OptionsPanel Timer - OnEnable] AceDBOptions:GetOptionsTable 未返回表！")
                end
            end, 0.2) -- 原始文件中的延迟
        else
            WRA:PrintDebug("[OptionsPanel:OnEnable] 配置档案面板已添加，跳过计划。")
        end
    else
         WRA:PrintError("[OptionsPanel:OnEnable] AceConfigDialog、WRA.db 或 AceDBOptions (或其GetOptionsTable方法) 未找到！无法计划添加配置档案选项。")
    end
end

function OptionsPanel:OnDisable()
    WRA:PrintDebug("[OptionsPanel:OnDisable] 模块已禁用。")
    -- self.profilePanelAdded = false -- 不应在此处重置标记，因为Blizzard选项条目不会自动移除
end


-- Function called by SpecLoader to add spec-specific options dynamically
function OptionsPanel:AddSpecOptions(specKey, specOptionsTable)
    if not AceConfigRegistry then -- **关键修复**：使用 AceConfigRegistry
        WRA:PrintError("[OptionsPanel:AddSpecOptions] AceConfigRegistry 引用缺失！无法通知更改。")
    end

    if not options or not options.args or not options.args.specs or not options.args.specs.args then
        WRA:PrintError(string_format("错误：无法为 %s 添加专精选项。主选项结构未就绪。", specKey))
        return
    end
    if not specKey or type(specOptionsTable) ~= "table" then
        WRA:PrintError("错误：传递给 AddSpecOptions 的参数无效。SpecKey:", tostring(specKey))
        return
    end

    local specOrder = 10 -- 默认顺序
    if WRA.Constants and WRA.Constants.SPEC_ORDER and WRA.Constants.SPEC_ORDER[specKey] then
        specOrder = WRA.Constants.SPEC_ORDER[specKey]
    end

    WRA:PrintDebug("[OptionsPanel:AddSpecOptions] 正在为专精添加选项组:", specKey)

    -- 在主 'specs' 组内创建专精组
    options.args.specs.args[specKey] = {
        type = "group",
        name = L[specKey] or (L["SPEC_SETTINGS_UNKNOWN_SPEC"] or specKey), -- MODIFIED: 使用 L[specKey] 或回退
        order = specOrder,
        args = specOptionsTable, -- 分配专精模块提供的表
        hidden = function() -- 原始文件中的 hidden 逻辑
           local currentSpecKey = WRA.SpecLoader and WRA.SpecLoader:GetCurrentSpecKey() or "nil"
           local shouldHide = not (currentSpecKey == specKey)
           return shouldHide
        end,
    }

    local specKeys = {}
    if options.args.specs and options.args.specs.args then
        for k,_ in pairs(options.args.specs.args) do table.insert(specKeys, k) end
    end
    WRA:PrintDebug("[OptionsPanel:AddSpecOptions] 当前 specs.args 键:", table.concat(specKeys, ", "))

    -- 通知 AceConfig 选项表已修改
    if AceConfigRegistry and AceConfigRegistry.NotifyChange then -- **关键修复**
        AceConfigRegistry:NotifyChange(addonName) -- 在有效实例上调用 NotifyChange
        WRA:PrintDebug("[OptionsPanel:AddSpecOptions] 已通知 AceConfig 关于 ", addonName, " 的更改")
    else
         WRA:PrintError("[OptionsPanel:AddSpecOptions] 无法通知 AceConfig 更改 (AceConfigRegistry 缺失或 NotifyChange 无效)。UI 可能不会更新。")
    end
end

-- 新增：用于打开选项面板的公共方法
function OptionsPanel:Open(groupPath)
    if not AceConfigRegistry or not AceConfigDialog then
        WRA:PrintError("无法打开选项面板，AceConfigRegistry 或 AceConfigDialog 未加载。")
        return
    end
    if not AceConfigRegistry:IsRegistered(addonName) then
        WRA:PrintDebug("主选项表尚未注册，尝试注册...")
        self:OnInitialize() -- 确保选项已注册
        if not AceConfigRegistry:IsRegistered(addonName) then
            WRA:PrintError("注册主选项表失败，无法打开选项面板。")
            return
        end
    end
    -- 确保档案面板也已尝试注册 (如果适用)
    if WRA.db and AceDBOptions and not self.profilePanelAdded and not AceConfigRegistry:IsRegistered(PROFILE_OPTIONS_KEY) then
        WRA:PrintDebug("档案面板可能尚未注册，尝试启用流程...")
        self:OnEnable() -- 尝试触发档案面板的添加
    end

    AceConfigDialog:Open(addonName, groupPath) -- groupPath 可以是 "general", "display", "specs.FuryWarrior" 等
    WRA:PrintDebug("尝试打开选项面板到路径: ", groupPath or " (根)")
end

-- 原始文件中的其他函数，如处理斜杠命令等，可以保留或按需调整。
-- 例如，如果WRA主文件处理斜杠命令并调用 WRA.OptionsPanel:Open()
