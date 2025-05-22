-- WRA/Locales/zhCN.lua
-- 简体中文本地化文件

local L = LibStub("AceLocale-3.0"):NewLocale("WRA", "zhCN", false) -- 设置为非默认语言
if not L then return end

-- 通用
L["WRA_ADDON_NAME"] = "WRA 助手"
L["WRA_ADDON_DESCRIPTION"] = "一个强大的技能循环和战斗辅助插件。"
L["CONFIGURATION_FOR_WRA"] = "WRA 设置"
L["SETTINGS_PANEL_TITLE"] = "设置"
L["PROFILES_PANEL_TITLE"] = "配置文件"

L["DISPLAY_POSITION_RESET"] = "显示位置已重置。"
L["QUICK_CONFIG_TITLE"] = "WRA 快捷设置"
L["CONFIG_BUTTON_TEXT"] = "设置"
L["QUICK_BUTTON_TEXT"] = "快捷"
L["NO_QUICK_OPTIONS_AVAILABLE"] = "没有可用的快捷选项。"

-- 主选项面板标签页
L["TAB_GENERAL"] = "通用"
L["TAB_FURY_WARRIOR"] = "狂暴战"
L["FuryWarrior"] = "狂暴战"
L["TAB_DISPLAY"] = "显示" -- Tab name for display options

-- 通用设置
L["GENERAL_SETTINGS_HEADER"] = "通用设置"
L["ENABLE_ADDON_NAME"] = "启用 WRA 助手"
L["ENABLE_ADDON_DESC"] = "完全启用或禁用此插件。"
L["DEBUG_MODE_NAME"] = "调试模式"
L["DEBUG_MODE_DESC"] = "启用详细的调试信息输出到聊天框（主要供开发者使用）。"

-- 显示设置 (Display Settings - for DisplayManager and Display_Icons)
L["DISPLAY_SETTINGS_HEADER"] = "显示设置"
L["DISPLAY_SETTINGS_HEADER_DESC"] = "配置建议显示的出现和行为。"
L["LOCK_DISPLAY_NAME"] = "锁定显示框位置"
L["LOCK_DISPLAY_DESC"] = "锁定技能提示框的位置，防止意外拖动。"
L["RESET_DISPLAY_POSITION_NAME"] = "重置显示框位置"
L["RESET_DISPLAY_POSITION_DESC"] = "将技能提示框的位置恢复到默认。"
L["DISPLAY_SCALE_NAME"] = "显示框缩放"
L["DISPLAY_SCALE_DESC"] = "调整技能提示框的大小。"
L["DISPLAY_ALPHA_NAME"] = "显示框透明度"
L["DISPLAY_ALPHA_DESC"] = "调整技能提示框的透明度。"

L["DISPLAY_MANAGER_SETTINGS_HEADER"] = "显示管理器设置"
L["SELECT_DISPLAY_MODE_NAME"] = "显示模式"
L["SELECT_DISPLAY_MODE_DESC"] = "选择技能建议的视觉样式。"
L["NO_DISPLAY_MODULES_REGISTERED"] = "没有已注册的显示模块"
L["Icons"] = "图标" -- ****** 新增的键 ******

L["ICON_DISPLAY_SETTINGS_HEADER"] = "图标显示设置"
L["SHOW_OFFGCD_SLOT_NAME"] = "显示副技能槽"
L["SHOW_OFFGCD_SLOT_DESC"] = "切换是否显示副技能（不占GCD）的提示槽。"
L["ICON_SIZE_NAME"] = "图标大小"
L["ICON_SIZE_DESC"] = "调整显示图标的大小。"
L["SHOW_COLOR_BLOCKS_NAME"] = "显示颜色块"
L["SHOW_COLOR_BLOCKS_DESC"] = "切换是否在图标旁边或背后显示颜色块。"
L["COLOR_BLOCK_BELOW_NAME"] = "颜色块在图标下方"
L["COLOR_BLOCK_BELOW_DESC"] = "如果启用，颜色块显示在图标下方；否则显示在图标背后。"
L["COLOR_BLOCK_HEIGHT_NAME"] = "颜色块高度"
L["COLOR_BLOCK_HEIGHT_DESC"] = "调整颜色块的高度。"


-- 专精设置
L["SPEC_SETTINGS_HEADER"] = "专精设置"
L["SPEC_SETTINGS_UNKNOWN_SPEC"] = "未知专精"

-- 狂暴战士选项 (确保这些键也都在这里定义)
L["SPEC_OPTIONS_FURYWARRIOR_HEADER_ROTATION"] = "循环选项"
L["OPTION_USE_WHIRLWIND_NAME"] = "旋风斩"
L["OPTION_USE_WHIRLWIND_DESC"] = "在循环中启用/禁用旋风斩。"
L["OPTION_USE_REND_NAME"] = "撕裂"
L["OPTION_USE_REND_DESC"] = "启用/禁用撕裂（需要切换姿态）。"
L["OPTION_USE_OVERPOWER_NAME"] = "压制"
L["OPTION_USE_OVERPOWER_DESC"] = "启用/禁用压制（需要切换姿态和触发）。"
L["OPTION_SMART_AOE_NAME"] = "智能AOE"
L["OPTION_SMART_AOE_DESC"] = "当“强制顺劈斩”关闭时，根据附近敌人数量自动在英勇打击和顺劈斩之间切换。"
L["OPTION_ENABLE_CLEAVE_NAME"] = "强制顺劈斩"
L["OPTION_ENABLE_CLEAVE_DESC"] = "强制使用顺劈斩替代英勇打击，无论目标数量或智能AOE设置如何。"

L["SPEC_OPTIONS_FURYWARRIOR_HEADER_COOLDOWNS"] = "爆发技能"
L["OPTION_USE_RECKLESSNESS_NAME"] = "鲁莽"
L["OPTION_USE_RECKLESSNESS_DESC"] = "允许自动使用鲁莽。"
L["OPTION_USE_DEATH_WISH_NAME"] = "死亡之愿"
L["OPTION_USE_DEATH_WISH_DESC"] = "允许自动使用死亡之愿。"
L["OPTION_USE_BERSERKER_RAGE_NAME"] = "狂暴之怒"
L["OPTION_USE_BERSERKER_RAGE_DESC"] = "允许自动使用狂暴之怒（主要用于保持激怒效果）。"

L["SPEC_OPTIONS_FURYWARRIOR_HEADER_UTILITY"] = "辅助技能"
L["OPTION_USE_SHATTERING_THROW_NAME"] = "碎裂投掷"
L["OPTION_USE_SHATTERING_THROW_DESC"] = "允许对首领自动使用碎甲投掷。"
L["OPTION_USE_INTERRUPTS_NAME"] = "打断 (拳击)"
L["OPTION_USE_INTERRUPTS_DESC"] = "允许自动使用拳击打断目标施法。"
L["OPTION_USE_SHOUTS_NAME"] = "战斗怒吼"
L["OPTION_USE_SHOUTS_DESC"] = "允许自动刷新战斗怒吼。"

L["SPEC_OPTIONS_FURYWARRIOR_HEADER_CONSUMABLES"] = "消耗品与种族技能"
L["OPTION_USE_TRINKETS_NAME"] = "自动饰品"
L["OPTION_USE_TRINKETS_DESC"] = "允许自动使用已追踪的主动使用型饰品。"
L["OPTION_USE_POTIONS_NAME"] = "自动药水"
L["OPTION_USE_POTIONS_DESC"] = "允许自动使用加速药水（配合死亡之愿）。"
L["OPTION_USE_RACIALS_NAME"] = "种族技能"
L["OPTION_USE_RACIALS_DESC"] = "允许自动使用进攻型种族技能（例如：血性狂怒、狂暴）。"

L["SPEC_OPTIONS_FURYWARRIOR_HEADER_AOE"] = "AOE 设置" -- Added this key based on OptionsPanel_Fury.lua


-- DisplayManager (Old, might be superseded by keys above if they are for the same options)
L["DISPLAY_TYPE_ICONS_NAME"] = "图标模式"
L["DISPLAY_TYPE_ICONS_DESC"] = "使用图标显示技能提示。"

-- QuickConfig
L["Config"] = "设置"
L["Quick"] = "快捷"
L["Quick Settings"] = "快捷设置"

-- General command/status messages
L["Addon Loaded"] = "插件已加载"
L["Addon Enabled"] = "插件已启用"
L["Addon Disabled"] = "插件已禁用"
L["Usage: /wra [config|quick|reset|toggle]"] = "用法: /wra [config|quick|reset|toggle]"
L["Profiles"] = "配置文件"
L["config"] = "config"
L["quick"] = "quick"
L["reset"] = "reset"
L["toggle"] = "toggle"

