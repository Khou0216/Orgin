-- UI/Display_Icons.lua
-- Implements the icon-based display backend for WRA, now with multi-slot and color blocks.
-- v26: Fixed GetLeftInset/etc. errors by using defined inset values.
-- 基于用户提供的版本进行修正

local addonName, _ = ...
local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0")
local WRA = AceAddon:GetAddon(addonName)
local L = LibStub("AceLocale-3.0"):GetLocale(addonName) -- Localization

local Display_Icons = WRA:NewModule("Display_Icons", "AceEvent-3.0", "AceTimer-3.0") -- 添加AceTimer依赖

-- Constants from WRA.Constants (确保它们在使用前已定义)
local ACTION_ID_IDLE -- 将在 OnInitialize 中从 WRA.Constants 获取
local ACTION_ID_WAITING
local ACTION_ID_CASTING
local ACTION_ID_UNKNOWN

-- Lua shortcuts
local GetSpellTexture = GetSpellTexture
local GetItemIcon = GetItemIcon -- WotLK GetItemInfo 返回10个值，图标是第10个
local GetTime = GetTime
local pairs = pairs
local type = type
local math_abs = math.abs
local wipe = wipe

-- Database default values
local dbDefaults = {
    displayScale = 1.0,
    displayAlpha = 1.0,
    showOffGCDSlot = true,
    iconSize = DEFAULT_ICON_SIZE,
    showColorBlocks = true,
    colorBlockBelowIcon = false,
    colorBlockHeight = DEFAULT_COLOR_BLOCK_HEIGHT,
    locked = false,
}

-- Module Variables
local mainContainerFrame = nil
local gcdSlot = {}
local offGcdSlot = {}
local DB = nil -- 将在 OnInitialize 中从 WRA.db.profile 获取
local actionMap = {} -- 用于缓存纹理

local DEFAULT_ICON_SIZE = 40 -- 原始文件中的值
local DEFAULT_COLOR_BLOCK_HEIGHT = 10 -- 原始文件中的值
local SLOT_SPACING = 4 -- 原始文件中的值
local DEFAULT_BACKDROP_INSET = 3 -- 原始文件中的值
local DEFAULT_QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- 辅助函数：获取动作的显示信息（纹理和颜色）
local function GetActionDisplayInfo(actionID) -- 保持为局部函数，因为它仅在此模块内部使用
    local displayInfo = {
        texture = DEFAULT_QUESTION_MARK_ICON, -- 默认问号图标
        color = (WRA.Constants and WRA.Constants.ActionColors and WRA.Constants.ActionColors[ACTION_ID_UNKNOWN]) or {r=0.1,g=0.1,b=0.1,a=0.8} -- 默认未知颜色
    }

    if not actionID then actionID = ACTION_ID_IDLE end -- 如果 actionID 为 nil，则视为空闲

    if actionMap[actionID] and actionMap[actionID].texture then
        displayInfo.texture = actionMap[actionID].texture
    elseif type(actionID) == "number" then
        if actionID > 0 then -- 法术ID
            local _, _, spellTex = GetSpellInfo(actionID) -- WotLK GetSpellInfo 返回3个值
            if spellTex then
                displayInfo.texture = spellTex
                actionMap[actionID] = { texture = spellTex, isSpell = true } -- 缓存
            end
        elseif actionID < 0 then -- 物品ID (负数表示)
             local _, _, _, _, _, _, _, _, _, itemTex = GetItemInfo(math_abs(actionID)) -- WotLK GetItemInfo 返回10个值
             if itemTex then
                 displayInfo.texture = itemTex
                 actionMap[actionID] = { texture = itemTex, isItem = true } -- 缓存
             end
        end
    end

    -- 获取颜色
    if WRA.Constants and WRA.Constants.ActionColors and WRA.Constants.ActionColors[actionID] then
        displayInfo.color = WRA.Constants.ActionColors[actionID]
    elseif WRA.Constants and WRA.Constants.ActionColors and (actionID == ACTION_ID_IDLE or actionID == ACTION_ID_WAITING) and WRA.Constants.ActionColors[ACTION_ID_IDLE] then
         displayInfo.color = WRA.Constants.ActionColors[ACTION_ID_IDLE] -- 空闲/等待的默认颜色
    end

    -- 确保颜色是表并且有alpha值
    if type(displayInfo.color) ~= "table" then
        displayInfo.color = (WRA.Constants and WRA.Constants.ActionColors and WRA.Constants.ActionColors[ACTION_ID_UNKNOWN]) or {r=0.1,g=0.1,b=0.1,a=0.8}
    end
    if displayInfo.color.a == nil then
        displayInfo.color.a = 1
    end

    return displayInfo
end

-- 辅助函数：为槽位创建UI元素
local function CreateSlotElements(parentFrame, slotTable, slotName) -- 保持为局部函数
    if slotTable.elementsCreated then return end -- 防止重复创建

    slotTable.icon = parentFrame:CreateTexture(parentFrame:GetName() .. "_" .. slotName .. "Icon", "ARTWORK")
    slotTable.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- 原始文件的 TexCoord
    slotTable.icon:SetPoint("TOPLEFT") -- 初始定位，将在 UpdateFrameAppearanceAndLayout 中精确设置

    slotTable.cooldownText = parentFrame:CreateFontString(parentFrame:GetName() .. "_" .. slotName .. "CooldownText", "OVERLAY", "GameFontNormalLarge")
    slotTable.cooldownText:SetPoint("CENTER", slotTable.icon, "CENTER", 0, 0)
    slotTable.cooldownText:SetTextColor(1, 0.1, 0.1) -- 原始文件的颜色
    slotTable.cooldownText:SetJustifyH("CENTER")
    slotTable.cooldownText:SetJustifyV("MIDDLE")
    slotTable.cooldownText:Hide() -- 默认隐藏

    slotTable.colorBlock = parentFrame:CreateTexture(parentFrame:GetName() .. "_" .. slotName .. "ColorBlock", "BACKGROUND")
    -- 颜色将在 UpdateDisplay 中设置

    slotTable.elementsCreated = true
    WRA:PrintDebug(string_format("Display_Icons: Slot elements created for %s", slotName))
end

-- 辅助函数：创建主显示框架和所有槽位元素
local function CreateDisplayElements() -- 保持为局部函数
    if mainContainerFrame and mainContainerFrame:IsObjectType("Frame") then
        WRA:PrintDebug("Display_Icons: 主容器框架已存在。")
        return mainContainerFrame
    end
    WRA:PrintDebug("Display_Icons: 正在创建主容器框架和槽位元素...")

    mainContainerFrame = CreateFrame("Frame", "WRA_MultiIconDisplayFrame", UIParent, "BackdropTemplate")
    mainContainerFrame:SetFrameStrata("MEDIUM") -- 原始文件的设置
    mainContainerFrame:SetToplevel(true)    -- 原始文件的设置
    mainContainerFrame:SetClampedToScreen(true)
    mainContainerFrame:EnableMouse(true)
    mainContainerFrame:SetMovable(true)
    mainContainerFrame.isBeingDragged = false -- 原始文件的拖拽标记

    if mainContainerFrame.SetBackdrop then -- 检查函数是否存在
         mainContainerFrame:SetBackdrop({
             bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
             edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
             tile = true, tileSize = 16, edgeSize = 16, -- 原始文件的 tile 和 size
             insets = { left = DEFAULT_BACKDROP_INSET, right = DEFAULT_BACKDROP_INSET, top = DEFAULT_BACKDROP_INSET, bottom = DEFAULT_BACKDROP_INSET }
         })
         mainContainerFrame:SetBackdropColor(0, 0, 0, 0.3) -- 原始文件的背景色
         mainContainerFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1) -- 原始文件的边框色
    end

    CreateSlotElements(mainContainerFrame, gcdSlot, "GCD")
    CreateSlotElements(mainContainerFrame, offGcdSlot, "OffGCD")

    mainContainerFrame:SetScript("OnMouseDown", function(self, button)
        if self == mainContainerFrame and button == "LeftButton" and DB and not DB.displayLocked then
            self:StartMoving()
            self.isBeingDragged = true
        end
    end)
    mainContainerFrame:SetScript("OnMouseUp", function(self, button)
        if self ~= mainContainerFrame then return end
        if button == "LeftButton" then
            local wasActuallyDragged = self.isBeingDragged -- 检查是否真的拖动了
            if self.StopMovingOrSizing then self:StopMovingOrSizing() end
            self.isBeingDragged = false
            if wasActuallyDragged and DB then -- 仅在实际拖动后保存
                local left, top = self:GetLeft(), self:GetTop()
                local parentBottom, parentLeft = UIParent:GetBottom(), UIParent:GetLeft()
                if left and top and parentBottom and parentLeft then
                    DB.displayPoint = { -- 保存相对于UIParent底部和左边的偏移
                        point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", -- 修改relativeTo为字符串
                        x = left - parentLeft, y = top - parentBottom,
                    }
                    WRA:PrintDebug("显示位置已保存:", DB.displayPoint.x, DB.displayPoint.y)
                else
                    WRA:PrintError("无法获取有效的框架或父框架坐标来保存位置。")
                end
            end
        end
    end)

    Display_Icons:UpdateFrameAppearanceAndLayout() -- 调用模块方法
    Display_Icons:UpdateDisplay({ gcdAction = ACTION_ID_IDLE, offGcdAction = nil }) -- 初始显示为空闲
    WRA:PrintDebug("Display_Icons: 所有显示元素已创建。")
    return mainContainerFrame
end

function Display_Icons:OnInitialize()
    if WRA.db and WRA.db.profile then
        -- 确保 displayIcons 的数据库子表存在
        if not WRA.db.profile.displayIcons then
            WRA.db.profile.displayIcons = {}
        end
        DB = WRA.db.profile.displayIcons -- 指向 displayIcons 的特定配置
    else
        WRA:PrintError("Display_Icons: 初始化时无法获取数据库引用。")
        DB = {} -- 创建临时表以避免错误，但表示配置不会被保存/加载
    end

    -- 合并默认值到DB (如果DB中没有对应项)
    for k, v in pairs(dbDefaults) do
        if DB[k] == nil then
            DB[k] = v
        end
    end
    -- 确保布尔值被正确处理 (nil会被视为false，但我们希望明确是true还是false)
    DB.showOffGCDSlot = DB.showOffGCDSlot == nil and dbDefaults.showOffGCDSlot or DB.showOffGCDSlot
    DB.showColorBlocks = DB.showColorBlocks == nil and dbDefaults.showColorBlocks or DB.showColorBlocks
    DB.colorBlockBelowIcon = DB.colorBlockBelowIcon == nil and dbDefaults.colorBlockBelowIcon or DB.colorBlockBelowIcon
    DB.displayLocked = DB.displayLocked == nil and dbDefaults.locked or DB.displayLocked


    mainContainerFrame = nil -- 确保在初始化时重置
    wipe(gcdSlot)
    wipe(offGcdSlot)
    wipe(actionMap)

    if WRA.Constants then
        ACTION_ID_IDLE = WRA.Constants.ACTION_ID_IDLE or "IDLE"
        ACTION_ID_WAITING = WRA.Constants.ACTION_ID_WAITING or 0
        ACTION_ID_CASTING = WRA.Constants.ACTION_ID_CASTING or "CASTING"
        ACTION_ID_UNKNOWN = WRA.Constants.ACTION_ID_UNKNOWN or -1
        if WRA.Constants.Spells then
            for _, spellID in pairs(WRA.Constants.Spells) do
                if type(spellID) == "number" and spellID > 0 then
                    local _, _, tex = GetSpellInfo(spellID) -- WotLK GetSpellInfo
                    if tex then actionMap[spellID] = { texture = tex, isSpell = true } end
                end
            end
        end
        if WRA.Constants.Items then
            for _, itemID in pairs(WRA.Constants.Items) do
                 if type(itemID) == "number" and itemID > 0 then
                    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemID) -- WotLK GetItemInfo
                    if tex then actionMap[-itemID] = { texture = tex, isItem = true } end -- 物品ID用负数存储
                 end
            end
        end
        -- 为特殊状态定义图标 (从原始文件中获取)
        actionMap[ACTION_ID_IDLE]    = { texture = "Interface\\Icons\\INV_Misc_QuestionMark" }
        actionMap[ACTION_ID_WAITING] = { texture = "Interface\\Icons\\INV_Misc_PocketWatch_01" }
        actionMap[ACTION_ID_CASTING] = { texture = "Interface\\Icons\\INV_Misc_PocketWatch_02" } -- 原始文件是02
        actionMap[ACTION_ID_UNKNOWN] = { texture = "Interface\\Icons\\INV_Misc_Bomb_07" } -- 原始文件是Bomb_07
    else
        WRA:PrintError("Display_Icons: WRA.Constants 未找到！无法加载常量和预置图标。")
        ACTION_ID_IDLE = "IDLE"; ACTION_ID_WAITING = 0; ACTION_ID_CASTING = "CASTING"; ACTION_ID_UNKNOWN = -1;
        actionMap[ACTION_ID_IDLE] = { texture = DEFAULT_QUESTION_MARK_ICON }
    end


    WRA:PrintDebug("Display_Icons 已初始化")
    -- **关键：在此处注册到DisplayManager**
    if WRA.DisplayManager and WRA.DisplayManager.RegisterDisplay then
        WRA.DisplayManager:RegisterDisplay("Icons", self)
        WRA:PrintDebug("Display_Icons 已向 DisplayManager 注册。")
    else
        WRA:PrintError("Display_Icons: 无法向 DisplayManager 注册（DisplayManager 或 RegisterDisplay 方法未找到）。")
    end
end

function Display_Icons:OnEnable()
    if not DB then -- 再次检查DB
        if WRA.db and WRA.db.profile and WRA.db.profile.displayIcons then DB = WRA.db.profile.displayIcons
        else WRA:PrintError("Display_Icons 无法启用，数据库未找到。"); return
        end
    end
    WRA:PrintDebug("Display_Icons 已启用")
    self:Show() -- OnEnable 时调用 Show
end

function Display_Icons:OnDisable()
    WRA:PrintDebug("Display_Icons 已禁用")
    self:Hide()
end

function Display_Icons:Show()
    WRA:PrintDebug("Display_Icons Show 已调用")
    CreateDisplayElements() -- 确保UI元素存在
    if mainContainerFrame and mainContainerFrame.Show then
        self:UpdateFrameAppearanceAndLayout() -- 先更新外观和布局
        mainContainerFrame:Show()
        WRA:PrintDebug("Display_Icons 主容器框架已显示。")
    else
        WRA:PrintError("Display_Icons: 无法显示，mainContainerFrame 为 nil 或无效（在 CreateDisplayElements 之后）。")
    end
end

function Display_Icons:Hide()
    WRA:PrintDebug("Display_Icons Hide 已调用")
    if mainContainerFrame and mainContainerFrame.Hide then
        mainContainerFrame:Hide()
        WRA:PrintDebug("Display_Icons 主容器框架已隐藏。")
    end
end

function Display_Icons:ResetPosition() -- 原始文件中的函数名
    if not DB then WRA:PrintError("无法重置位置，DB 未初始化。"); return end

    if mainContainerFrame and mainContainerFrame.ClearAllPoints and mainContainerFrame.SetPoint then
        local defaultX = 0  -- 默认居中X偏移
        local defaultY = 150 -- 默认居中Y偏移 (原始文件中的值)
        mainContainerFrame:ClearAllPoints()
        mainContainerFrame:SetPoint("CENTER", UIParent, "CENTER", defaultX, defaultY)
        
        -- 更新数据库中的保存点为默认值
        local left, top = mainContainerFrame:GetLeft(), mainContainerFrame:GetTop()
        if left and top then
            local parentBottom, parentLeft = UIParent:GetBottom(), UIParent:GetLeft()
            if parentBottom and parentLeft then
                DB.displayPoint = { point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", x = left - parentLeft, y = top - parentBottom }
                WRA:PrintDebug("Display_Icons 位置已重置并保存。")
                self:UpdateFrameAppearanceAndLayout() -- 确保应用新位置
            else
                WRA:PrintError("重置位置时无法获取父框架坐标。")
            end
        else
            WRA:PrintError("重置位置时无法获取框架坐标。")
        end
    else
        WRA:PrintError("无法重置位置，主框架无效。")
    end
end

function Display_Icons:UpdateFrameAppearanceAndLayout()
    if not mainContainerFrame then WRA:PrintDebug("UpdateFrameAppearanceAndLayout: 框架尚未创建。"); return end
    if not DB then
        if WRA.db and WRA.db.profile and WRA.db.profile.displayIcons then DB = WRA.db.profile.displayIcons
        else WRA:PrintError("UpdateFrameAppearanceAndLayout: 数据库引用为 nil。"); return
        end
    end

    local pos = DB.displayPoint
    mainContainerFrame:ClearAllPoints() -- 总是先清除
    if pos and pos.point and pos.relativeTo and _G[pos.relativeTo] and pos.relativePoint and type(pos.x) == "number" and type(pos.y) == "number" then
        mainContainerFrame:SetPoint(pos.point, _G[pos.relativeTo], pos.relativePoint, pos.x, pos.y)
    else
        WRA:PrintDebug("无效或缺失的 displayPoint，使用默认位置 CENTER, 0, 150。保存的点:", pos and pos.point, pos and pos.relativeTo, pos and pos.relativePoint, pos and pos.x, pos and pos.y)
        mainContainerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150) -- 默认位置
    end

    mainContainerFrame:SetScale(DB.displayScale or 1.0)
    mainContainerFrame:SetAlpha(DB.displayAlpha or 1.0)
    if mainContainerFrame.SetMovable then mainContainerFrame:SetMovable(not DB.displayLocked) end -- 根据DB.displayLocked设置
    
    if mainContainerFrame.SetBackdropBorderColor then -- 检查函数是否存在
        if DB.displayLocked then mainContainerFrame:SetBackdropBorderColor(0.8, 0.2, 0.2, 1) -- 锁定时的边框颜色
        else mainContainerFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1) -- 未锁定时的边框颜色
        end
    end

    local iconSize = DB.iconSize or DEFAULT_ICON_SIZE -- 从DB获取，如果DB中没有则用默认值
    local colorBlockHeight = (DB.showColorBlocks and (DB.colorBlockHeight or DEFAULT_COLOR_BLOCK_HEIGHT)) or 0
    
    -- 计算槽位总高度，考虑色块是否在下方
    local slotHeightWithBlockBelow = iconSize + ( (DB.colorBlockBelowIcon and colorBlockHeight > 0) and (colorBlockHeight + 2) or 0) -- 2是色块和图标间距
    local slotHeightIconOnly = iconSize
    local currentSlotHeight
    if DB.showColorBlocks and DB.colorBlockBelowIcon and colorBlockHeight > 0 then
        currentSlotHeight = slotHeightWithBlockBelow
    else
        currentSlotHeight = slotHeightIconOnly
    end

    local insetLeft = DEFAULT_BACKDROP_INSET
    local insetRight = DEFAULT_BACKDROP_INSET
    local insetTop = DEFAULT_BACKDROP_INSET
    local insetBottom = DEFAULT_BACKDROP_INSET

    if gcdSlot.elementsCreated then
        gcdSlot.icon:SetSize(iconSize, iconSize)
        gcdSlot.icon:ClearAllPoints()
        gcdSlot.icon:SetPoint("TOPLEFT", insetLeft, -insetTop)

        if DB.showColorBlocks and colorBlockHeight > 0 then
            gcdSlot.colorBlock:SetSize(iconSize, colorBlockHeight)
            gcdSlot.colorBlock:ClearAllPoints()
            if DB.colorBlockBelowIcon then
                gcdSlot.colorBlock:SetPoint("TOPLEFT", gcdSlot.icon, "BOTTOMLEFT", 0, -2) -- 图标下方2像素间距
            else -- 作为背景
                gcdSlot.colorBlock:SetAllPoints(gcdSlot.icon) -- 完全覆盖图标位置
                gcdSlot.colorBlock:SetFrameLevel(gcdSlot.icon:GetFrameLevel() - 1) -- 确保在图标之下
            end
            gcdSlot.colorBlock:Show()
        else
            gcdSlot.colorBlock:Hide()
        end
        gcdSlot.icon:Show()
        if gcdSlot.cooldownText and gcdSlot.icon then -- 确保冷却文本居中于图标
            gcdSlot.cooldownText:ClearAllPoints()
            gcdSlot.cooldownText:SetPoint("CENTER", gcdSlot.icon, "CENTER", 0, 0)
            -- gcdSlot.cooldownText:Hide() -- 暂时隐藏，直到实现冷却逻辑
        end
    end

    local offGcdSlotVisible = DB.showOffGCDSlot
    local offGcdIconSize = iconSize * 0.8 -- 原始文件中的缩放比例
    local offGcdColorBlockHeight = colorBlockHeight * 0.8 -- 原始文件中的缩放比例

    if offGcdSlot.elementsCreated then
        if offGcdSlotVisible then
            offGcdSlot.icon:SetSize(offGcdIconSize, offGcdIconSize)
            offGcdSlot.icon:ClearAllPoints()
            offGcdSlot.icon:SetPoint("TOPLEFT", gcdSlot.icon, "TOPRIGHT", SLOT_SPACING, 0) -- 定位在GCD图标右侧
            offGcdSlot.icon:Show()

            if DB.showColorBlocks and offGcdColorBlockHeight > 0 then
                offGcdSlot.colorBlock:SetSize(offGcdIconSize, offGcdColorBlockHeight)
                offGcdSlot.colorBlock:ClearAllPoints()
                if DB.colorBlockBelowIcon then
                    offGcdSlot.colorBlock:SetPoint("TOPLEFT", offGcdSlot.icon, "BOTTOMLEFT", 0, -2)
                else
                    offGcdSlot.colorBlock:SetAllPoints(offGcdSlot.icon)
                    offGcdSlot.colorBlock:SetFrameLevel(offGcdSlot.icon:GetFrameLevel() - 1)
                end
                offGcdSlot.colorBlock:Show()
            else
                offGcdSlot.colorBlock:Hide()
            end
            if offGcdSlot.cooldownText and offGcdSlot.icon then
                 offGcdSlot.cooldownText:ClearAllPoints()
                 offGcdSlot.cooldownText:SetPoint("CENTER", offGcdSlot.icon, "CENTER", 0, 0)
                 offGcdSlot.cooldownText:SetFontObject(GameFontNormal) -- 原始文件中的字体
                 -- offGcdSlot.cooldownText:Hide() -- 暂时隐藏
            end
        else
            offGcdSlot.icon:Hide()
            if offGcdSlot.colorBlock then offGcdSlot.colorBlock:Hide() end
            if offGcdSlot.cooldownText then offGcdSlot.cooldownText:Hide() end
        end
    end

    -- 根据内容和边衬调整主容器大小
    local totalContentWidth = iconSize
    if offGcdSlotVisible then
        totalContentWidth = totalContentWidth + SLOT_SPACING + offGcdIconSize
    end
    local totalContentHeight = currentSlotHeight -- 使用之前计算的槽位高度

    mainContainerFrame:SetSize(totalContentWidth + insetLeft + insetRight, totalContentHeight + insetTop + insetBottom)
    -- WRA:PrintDebug("Display_Icons 外观和布局已更新。") --这条信息太频繁，可以注释掉
end

function Display_Icons:UpdateDisplay(actionsTable)
    if not mainContainerFrame then
        WRA:PrintDebug("UpdateDisplay: 已中止，mainContainerFrame 为 nil。")
        return
    end
    -- 移除原始文件中对 WRA.db.profile.enabled 的检查，因为 Show/Hide 应该由 DisplayManager 控制
    -- if not mainContainerFrame:IsVisible() and not (WRA.db and WRA.db.profile and WRA.db.profile.enabled) then
    --     return
    -- end
    if not gcdSlot.elementsCreated or not offGcdSlot.elementsCreated then
        WRA:PrintDebug("UpdateDisplay: 槽位元素尚未创建。")
        -- 尝试再次创建，以防初始化顺序问题
        CreateDisplayElements()
        if not gcdSlot.elementsCreated or not offGcdSlot.elementsCreated then return end
    end

    actionsTable = actionsTable or {}
    local gcdActionID = actionsTable.gcdAction
    local offGcdActionID = actionsTable.offGcdAction

    local gcdDisplayInfo = GetActionDisplayInfo(gcdActionID) -- 使用局部函数
    if gcdSlot.icon and gcdSlot.icon.SetTexture then 
        gcdSlot.icon:SetTexture(gcdDisplayInfo.texture) 
        gcdSlot.icon:Show() -- 确保图标可见
    end
    if DB.showColorBlocks and gcdSlot.colorBlock and gcdSlot.colorBlock.SetColorTexture then
        gcdSlot.colorBlock:SetColorTexture(gcdDisplayInfo.color.r, gcdDisplayInfo.color.g, gcdDisplayInfo.color.b, gcdDisplayInfo.color.a or 1)
        gcdSlot.colorBlock:Show()
    elseif gcdSlot.colorBlock then
        gcdSlot.colorBlock:Hide()
    end
    if gcdSlot.cooldownText then gcdSlot.cooldownText:Hide() end -- 暂时隐藏冷却文本

    if DB.showOffGCDSlot then -- 根据DB设置决定是否处理OffGCD槽
        if offGcdActionID and offGcdActionID ~= ACTION_ID_IDLE and offGcdActionID ~= ACTION_ID_WAITING then -- 只有在有实际的OffGCD技能时才显示
            local offGcdDisplayInfo = GetActionDisplayInfo(offGcdActionID) -- 使用局部函数
            if offGcdSlot.icon and offGcdSlot.icon.SetTexture then
                offGcdSlot.icon:SetTexture(offGcdDisplayInfo.texture)
                offGcdSlot.icon:Show()
            end
            if DB.showColorBlocks and offGcdSlot.colorBlock and offGcdSlot.colorBlock.SetColorTexture then
                offGcdSlot.colorBlock:SetColorTexture(offGcdDisplayInfo.color.r, offGcdDisplayInfo.color.g, offGcdDisplayInfo.color.b, offGcdDisplayInfo.color.a or 1)
                offGcdSlot.colorBlock:Show()
            elseif offGcdSlot.colorBlock then
                offGcdSlot.colorBlock:Hide()
            end
            if offGcdSlot.cooldownText then offGcdSlot.cooldownText:Hide() end -- 暂时隐藏
        else -- 没有有效的OffGCD技能，则隐藏整个OffGCD槽
            if offGcdSlot.icon then offGcdSlot.icon:Hide() end
            if offGcdSlot.colorBlock then offGcdSlot.colorBlock:Hide() end
            if offGcdSlot.cooldownText then offGcdSlot.cooldownText:Hide() end
        end
    else -- 如果不显示OffGCD槽，则全部隐藏
        if offGcdSlot.icon then offGcdSlot.icon:Hide() end
        if offGcdSlot.colorBlock then offGcdSlot.colorBlock:Hide() end
        if offGcdSlot.cooldownText then offGcdSlot.cooldownText:Hide() end
    end
end

function Display_Icons:OnProfileChanged(event, database, newProfileKey)
    WRA:PrintDebug("Display_Icons: OnProfileChanged 触发。新档案: " .. tostring(newProfileKey))
    if database and database.profile and database.profile.displayIcons then -- 确保是正确的数据库部分
        DB = database.profile.displayIcons
        if mainContainerFrame then
            self:UpdateFrameAppearanceAndLayout()
        end
        WRA:PrintDebug("Display_Icons 档案已更改/应用。")
    else
        WRA:PrintError("Display_Icons: 在档案更改时收到无效的数据库。")
        -- DB = nil -- 不应将DB设为nil，除非确定要重置为无配置状态
    end
end

function Display_Icons:RefreshConfig() -- 原始文件中的函数名
    WRA:PrintDebug("Display_Icons RefreshConfig 已调用。")
    if WRA.db and WRA.db.profile and WRA.db.profile.displayIcons then 
        DB = WRA.db.profile.displayIcons 
    end
    if mainContainerFrame then
        self:UpdateFrameAppearanceAndLayout()
    end
end

-- 为选项面板提供此模块的选项定义
function Display_Icons:GetOptionsTable()
    local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
    if not L then L = setmetatable({}, {__index=function(t,k) return k end}) end

    -- 确保DB已初始化
    if not DB then
        if WRA.db and WRA.db.profile and WRA.db.profile.displayIcons then
            DB = WRA.db.profile.displayIcons
        else
            WRA:PrintError("Display_Icons:GetOptionsTable - DB 未初始化，无法创建选项。")
            return {} -- 返回空表
        end
    end
    
    return {
        -- 保持与之前版本相似的结构，以便OptionsPanel能正确合并
        -- type = "group", name = L["ICON_DISPLAY_SETTINGS_HEADER"] or "Icon Display Settings", order = 1,
        -- args = { ... }
        -- 直接返回args部分，因为OptionsPanel会将它包装在一个group里
        locked = {
            order = 1, type = "toggle", name = L["LOCK_DISPLAY_NAME"] or "锁定位置", 
            desc = L["LOCK_DISPLAY_DESC"] or "锁定提示框的位置，防止意外拖动。",
            get = function(info) return DB.displayLocked end,
            set = function(info, value) DB.displayLocked = value; self:UpdateFrameAppearanceAndLayout() end,
        },
        resetPos = {
            order = 2, type = "execute", name = L["RESET_DISPLAY_POSITION_NAME"] or "重置位置", 
            desc = L["RESET_DISPLAY_POSITION_DESC"] or "将提示框的位置和大小重置为默认值。",
            func = function() self:ResetPosition() end, -- 调用模块的ResetPosition
        },
        scale = {
            order = 3, type = "range", name = L["DISPLAY_SCALE_NAME"] or "缩放", 
            desc = L["DISPLAY_SCALE_DESC"] or "调整提示框的整体缩放比例。", 
            min = 0.5, max = 2.0, step = 0.05, -- isPercent = true, -- isPercent不是标准AceConfig选项
            get = function(info) return DB.displayScale end,
            set = function(info, value) DB.displayScale = value; self:UpdateFrameAppearanceAndLayout() end,
        },
        alpha = {
            order = 4, type = "range", name = L["DISPLAY_ALPHA_NAME"] or "透明度", 
            desc = L["DISPLAY_ALPHA_DESC"] or "调整提示框的透明度。", 
            min = 0.1, max = 1.0, step = 0.05, -- isPercent = true,
            get = function(info) return DB.displayAlpha end,
            set = function(info, value) DB.displayAlpha = value; self:UpdateFrameAppearanceAndLayout() end,
        },
        showOffGCDSlot = {
            order = 10, type = "toggle", name = L["SHOW_OFFGCD_SLOT_NAME"] or "显示副技能槽",
            desc = L["SHOW_OFFGCD_SLOT_DESC"] or "切换是否显示副技能（不占GCD）的提示槽。",
            get = function(info) return DB.showOffGCDSlot end,
            set = function(info, value) DB.showOffGCDSlot = value; self:UpdateFrameAppearanceAndLayout() end,
        },
        iconSize = {
            order = 11, type = "range", name = L["ICON_SIZE_NAME"] or "图标大小",
            desc = L["ICON_SIZE_DESC"] or "调整显示图标的大小。",
            min = 16, max = 64, step = 1,
            get = function(info) return DB.iconSize or DEFAULT_ICON_SIZE end,
            set = function(info, value) DB.iconSize = value; self:UpdateFrameAppearanceAndLayout() end,
        },
        showColorBlocks = {
            order = 20, type = "toggle", name = L["SHOW_COLOR_BLOCKS_NAME"] or "显示颜色块",
            desc = L["SHOW_COLOR_BLOCKS_DESC"] or "切换是否在图标下方或背后显示颜色块。",
            get = function(info) return DB.showColorBlocks end,
            set = function(info, value) DB.showColorBlocks = value; self:UpdateFrameAppearanceAndLayout() end,
        },
        colorBlockBelowIcon = {
            order = 21, type = "toggle", name = L["COLOR_BLOCK_BELOW_NAME"] or "颜色块在图标下方",
            desc = L["COLOR_BLOCK_BELOW_DESC"] or "如果启用，颜色块显示在图标下方；否则（简化处理）显示在图标背后。",
            disabled = function() return not DB.showColorBlocks end,
            get = function(info) return DB.colorBlockBelowIcon end,
            set = function(info, value) DB.colorBlockBelowIcon = value; self:UpdateFrameAppearanceAndLayout() end,
        },
        colorBlockHeight = {
            order = 22, type = "range", name = L["COLOR_BLOCK_HEIGHT_NAME"] or "颜色块高度",
            desc = L["COLOR_BLOCK_HEIGHT_DESC"] or "调整颜色块的高度。",
            disabled = function() return not DB.showColorBlocks end,
            min = 4, max = 32, step = 1,
            get = function(info) return DB.colorBlockHeight or DEFAULT_COLOR_BLOCK_HEIGHT end,
            set = function(info, value) DB.colorBlockHeight = value; self:UpdateFrameAppearanceAndLayout() end,
        },
        -- 可以添加更多 Display_Icons 特有的设置
    }
end
