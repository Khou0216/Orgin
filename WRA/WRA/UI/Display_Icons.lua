-- UI/Display_Icons.lua
-- Implements the icon-based display backend for WRA, now with multi-slot and color blocks.
-- v32: Call OptionsPanel:RefreshOptions after registering with DisplayManager.

local addonName, _ = ...
local LibStub = LibStub
local AceAddon = LibStub("AceAddon-3.0")
local WRA = AceAddon:GetAddon(addonName)
local L = LibStub("AceLocale-3.0"):GetLocale(addonName) -- Localization

local Display_Icons = WRA:NewModule("Display_Icons", "AceEvent-3.0", "AceTimer-3.0")

local ACTION_ID_IDLE
local ACTION_ID_WAITING
local ACTION_ID_CASTING
local ACTION_ID_UNKNOWN

local GetSpellTexture = GetSpellTexture
local GetItemIcon = GetItemIcon 
local GetTime = GetTime
local pairs = pairs
local type = type
local math_abs = math.abs
local wipe = wipe
local string_format = string.format 

local dbDefaults = {
    displayScale = 1.0,
    displayAlpha = 1.0,
    showOffGCDSlot = true,
    iconSize = 40,
    showColorBlocks = true,
    colorBlockBelowIcon = false,
    colorBlockHeight = 10,
    locked = false,
}

local mainContainerFrame = nil
local gcdSlot = {}
local offGcdSlot = {}
local DB = nil
local actionMap = {}

local DEFAULT_ICON_SIZE = 40
local DEFAULT_COLOR_BLOCK_HEIGHT = 10
local SLOT_SPACING = 4
local DEFAULT_BACKDROP_INSET = 3
local DEFAULT_QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function GetActionDisplayInfo(actionID)
    local displayInfo = {
        texture = DEFAULT_QUESTION_MARK_ICON,
        color = (WRA.Constants and WRA.Constants.ActionColors and WRA.Constants.ActionColors[ACTION_ID_UNKNOWN]) or {r=0.1,g=0.1,b=0.1,a=0.8}
    }
    if not actionID then actionID = ACTION_ID_IDLE end

    if actionMap[actionID] and actionMap[actionID].texture then
        displayInfo.texture = actionMap[actionID].texture
    elseif type(actionID) == "number" then
        if actionID > 0 then
            local _, _, spellTex = GetSpellInfo(actionID)
            if spellTex then
                displayInfo.texture = spellTex
                actionMap[actionID] = { texture = spellTex, isSpell = true }
            end
        elseif actionID < 0 then
             local _, _, _, _, _, _, _, _, _, itemTex = GetItemInfo(math_abs(actionID))
             if itemTex then
                 displayInfo.texture = itemTex
                 actionMap[actionID] = { texture = itemTex, isItem = true }
             end
        end
    end

    if WRA.Constants and WRA.Constants.ActionColors and WRA.Constants.ActionColors[actionID] then
        displayInfo.color = WRA.Constants.ActionColors[actionID]
    elseif WRA.Constants and WRA.Constants.ActionColors and (actionID == ACTION_ID_IDLE or actionID == ACTION_ID_WAITING) and WRA.Constants.ActionColors[ACTION_ID_IDLE] then
         displayInfo.color = WRA.Constants.ActionColors[ACTION_ID_IDLE]
    end

    if type(displayInfo.color) ~= "table" then
        displayInfo.color = (WRA.Constants and WRA.Constants.ActionColors and WRA.Constants.ActionColors[ACTION_ID_UNKNOWN]) or {r=0.1,g=0.1,b=0.1,a=0.8}
    end
    if displayInfo.color.a == nil then
        displayInfo.color.a = 1
    end
    return displayInfo
end

local function CreateSlotElements(parentFrame, slotTable, slotName)
    if slotTable.elementsCreated then return end 

    slotTable.elementsCreated = false 

    if not parentFrame or not parentFrame:IsObjectType("Frame") then
        WRA:PrintError(string.format("CreateSlotElements: Invalid parentFrame for %s", slotName))
        return
    end

    slotTable.icon = parentFrame:CreateTexture(parentFrame:GetName() .. "_" .. slotName .. "Icon", "ARTWORK")
    if not slotTable.icon then WRA:PrintError(string.format("Failed to create icon for %s", slotName)); return end
    slotTable.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slotTable.icon:SetPoint("TOPLEFT")

    slotTable.cooldownText = parentFrame:CreateFontString(parentFrame:GetName() .. "_" .. slotName .. "CooldownText", "OVERLAY", "GameFontNormalLarge")
    if not slotTable.cooldownText then WRA:PrintError(string.format("Failed to create cooldownText for %s", slotName)); return end

    if slotTable.icon and slotTable.icon:IsObjectType("Texture") then
        slotTable.cooldownText:SetPoint("CENTER", slotTable.icon, "CENTER", 0, 0)
    else
        slotTable.cooldownText:SetPoint("CENTER", parentFrame, "CENTER", 0,0) 
    end
    slotTable.cooldownText:SetTextColor(1, 0.1, 0.1)
    slotTable.cooldownText:SetJustifyH("CENTER")
    slotTable.cooldownText:SetJustifyV("MIDDLE")
    slotTable.cooldownText:Hide()

    slotTable.colorBlock = parentFrame:CreateTexture(parentFrame:GetName() .. "_" .. slotName .. "ColorBlock", "BACKGROUND")
    if not slotTable.colorBlock then WRA:PrintError(string.format("Failed to create colorBlock for %s", slotName)); return end
    slotTable.colorBlock:SetDrawLayer("BACKGROUND")


    slotTable.elementsCreated = true 
    WRA:PrintDebug(string.format("Display_Icons: Slot elements created successfully for %s", slotName))
end

local function CreateDisplayElements()
    if not (mainContainerFrame and mainContainerFrame:IsObjectType("Frame")) then
        WRA:PrintDebug("Display_Icons: 正在创建主容器框架...")
        mainContainerFrame = CreateFrame("Frame", "WRA_MultiIconDisplayFrame", UIParent, "BackdropTemplate")
        if not mainContainerFrame then
            WRA:PrintError("Display_Icons: Failed to create mainContainerFrame!")
            return nil
        end
        mainContainerFrame:SetFrameStrata("MEDIUM")
        mainContainerFrame:SetToplevel(true)
        mainContainerFrame:SetClampedToScreen(true)
        mainContainerFrame:EnableMouse(true)
        mainContainerFrame:SetMovable(true)
        mainContainerFrame.isBeingDragged = false

        if mainContainerFrame.SetBackdrop then
             mainContainerFrame:SetBackdrop({
                 bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                 edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                 tile = true, tileSize = 16, edgeSize = 16,
                 insets = { left = DEFAULT_BACKDROP_INSET, right = DEFAULT_BACKDROP_INSET, top = DEFAULT_BACKDROP_INSET, bottom = DEFAULT_BACKDROP_INSET }
             })
             mainContainerFrame:SetBackdropColor(0, 0, 0, 0.3)
             mainContainerFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end
        mainContainerFrame:SetScript("OnMouseDown", function(self, button)
            if self == mainContainerFrame and button == "LeftButton" and DB and not DB.displayLocked then
                self:StartMoving()
                self.isBeingDragged = true
            end
        end)
        mainContainerFrame:SetScript("OnMouseUp", function(self, button)
            if self ~= mainContainerFrame then return end
            if button == "LeftButton" then
                local wasActuallyDragged = self.isBeingDragged
                if self.StopMovingOrSizing then self:StopMovingOrSizing() end
                self.isBeingDragged = false
                if wasActuallyDragged and DB then
                    local left, top = self:GetLeft(), self:GetTop()
                    local parentBottom, parentLeft = UIParent:GetBottom(), UIParent:GetLeft()
                    if left and top and parentBottom and parentLeft then
                        DB.displayPoint = {
                            point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT",
                            x = left - parentLeft, y = top - parentBottom,
                        }
                        WRA:PrintDebug("显示位置已保存:", DB.displayPoint.x, DB.displayPoint.y)
                    else
                        WRA:PrintError("无法获取有效的框架或父框架坐标来保存位置。")
                    end
                end
            end
        end)
    end

    if not mainContainerFrame or not mainContainerFrame:IsObjectType("Frame") then
        WRA:PrintError("Display_Icons: CreateDisplayElements - mainContainerFrame is invalid before creating slot elements.")
        return nil
    end

    CreateSlotElements(mainContainerFrame, gcdSlot, "GCD")
    CreateSlotElements(mainContainerFrame, offGcdSlot, "OffGCD")

    if mainContainerFrame and mainContainerFrame:IsObjectType("Frame") then
        if Display_Icons.initialLayoutTimer then
            Display_Icons:CancelTimer(Display_Icons.initialLayoutTimer, true)
        end
        Display_Icons.initialLayoutTimer = Display_Icons:ScheduleTimer(function()
            Display_Icons.initialLayoutTimer = nil
            if mainContainerFrame and mainContainerFrame:IsObjectType("Frame") then
                WRA:PrintDebug("Display_Icons: Executing deferred initial layout.")
                Display_Icons:UpdateFrameAppearanceAndLayout()
                Display_Icons:UpdateDisplay({ gcdAction = ACTION_ID_IDLE, offGcdAction = nil })
            else
                WRA:PrintError("Display_Icons: Deferred layout - mainContainerFrame became invalid.")
            end
        end, 0.2) 
    end

    WRA:PrintDebug("Display_Icons: Element creation complete, initial layout deferred.")
    return mainContainerFrame
end

function Display_Icons:OnInitialize()
    if WRA.db and WRA.db.profile then
        if not WRA.db.profile.displayIcons then
            WRA.db.profile.displayIcons = {}
        end
        DB = WRA.db.profile.displayIcons
    else
        WRA:PrintError("Display_Icons: 初始化时无法获取数据库引用。")
        DB = {}
    end

    for k, v in pairs(dbDefaults) do
        if DB[k] == nil then
            DB[k] = v
        end
    end
    DB.showOffGCDSlot = DB.showOffGCDSlot == nil and dbDefaults.showOffGCDSlot or DB.showOffGCDSlot
    DB.showColorBlocks = DB.showColorBlocks == nil and dbDefaults.showColorBlocks or DB.showColorBlocks
    DB.colorBlockBelowIcon = DB.colorBlockBelowIcon == nil and dbDefaults.colorBlockBelowIcon or DB.colorBlockBelowIcon
    DB.displayLocked = DB.displayLocked == nil and dbDefaults.locked or DB.displayLocked

    mainContainerFrame = nil
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
                    local _, _, tex = GetSpellInfo(spellID)
                    if tex then actionMap[spellID] = { texture = tex, isSpell = true } end
                end
            end
        end
        if WRA.Constants.Items then
            for _, itemID in pairs(WRA.Constants.Items) do
                 if type(itemID) == "number" and itemID > 0 then
                    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemID)
                    if tex then actionMap[-itemID] = { texture = tex, isItem = true } end
                 end
            end
        end
        actionMap[ACTION_ID_IDLE]    = { texture = "Interface\\Icons\\INV_Misc_QuestionMark" }
        actionMap[ACTION_ID_WAITING] = { texture = "Interface\\Icons\\INV_Misc_PocketWatch_01" }
        actionMap[ACTION_ID_CASTING] = { texture = "Interface\\Icons\\INV_Misc_PocketWatch_02" }
        actionMap[ACTION_ID_UNKNOWN] = { texture = "Interface\\Icons\\INV_Misc_Bomb_07" }
    else
        WRA:PrintError("Display_Icons: WRA.Constants 未找到！无法加载常量和预置图标。")
        ACTION_ID_IDLE = "IDLE"; ACTION_ID_WAITING = 0; ACTION_ID_CASTING = "CASTING"; ACTION_ID_UNKNOWN = -1;
        actionMap[ACTION_ID_IDLE] = { texture = DEFAULT_QUESTION_MARK_ICON }
    end

    WRA:PrintDebug("Display_Icons 已初始化")
    if WRA.DisplayManager and WRA.DisplayManager.RegisterDisplay then
        WRA.DisplayManager:RegisterDisplay("Icons", self) 
        WRA:PrintDebug("Display_Icons 已向 DisplayManager 注册。")
        -- After successful registration, try to refresh options panel
        if WRA.OptionsPanel and WRA.OptionsPanel.RefreshOptions then
            WRA:PrintDebug("Display_Icons: Calling OptionsPanel:RefreshOptions().")
            WRA.OptionsPanel:RefreshOptions()
        else
            WRA:PrintDebug("Display_Icons: WRA.OptionsPanel or RefreshOptions not found, cannot refresh options panel.")
        end
    else
        WRA:PrintError("Display_Icons: 无法向 DisplayManager 注册。DisplayManager: ", type(WRA.DisplayManager), "RegisterDisplay:", type(WRA.DisplayManager and WRA.DisplayManager.RegisterDisplay))
    end
end

function Display_Icons:OnEnable()
    if not DB then
        if WRA.db and WRA.db.profile and WRA.db.profile.displayIcons then DB = WRA.db.profile.displayIcons
        else WRA:PrintError("Display_Icons 无法启用，数据库未找到。"); return
        end
    end
    WRA:PrintDebug("Display_Icons 已启用")
    self:Show()
end

function Display_Icons:OnDisable()
    WRA:PrintDebug("Display_Icons 已禁用")
    self:Hide()
    if self.initialLayoutTimer then
        self:CancelTimer(self.initialLayoutTimer, true)
        self.initialLayoutTimer = nil
    end
end

function Display_Icons:Show()
    WRA:PrintDebug("Display_Icons Show 已调用")
    CreateDisplayElements() 
    if mainContainerFrame and mainContainerFrame:IsObjectType("Frame") and mainContainerFrame.Show then
        if not self.initialLayoutTimer then 
            self:UpdateFrameAppearanceAndLayout()
        end
        mainContainerFrame:Show()
        WRA:PrintDebug("Display_Icons 主容器框架已显示。")
    else
        WRA:PrintDebug("Display_Icons: 无法显示，mainContainerFrame 无效或未创建。")
    end
end

function Display_Icons:Hide()
    WRA:PrintDebug("Display_Icons Hide 已调用")
    if mainContainerFrame and mainContainerFrame:IsObjectType("Frame") and mainContainerFrame.Hide then
        mainContainerFrame:Hide()
        WRA:PrintDebug("Display_Icons 主容器框架已隐藏。")
    end
end

function Display_Icons:ResetPosition()
    if not DB then WRA:PrintError("无法重置位置，DB 未初始化。"); return end

    if mainContainerFrame and mainContainerFrame:IsObjectType("Frame") and mainContainerFrame.ClearAllPoints and mainContainerFrame.SetPoint then
        local defaultX = 0
        local defaultY = 150
        mainContainerFrame:ClearAllPoints()
        mainContainerFrame:SetPoint("CENTER", UIParent, "CENTER", defaultX, defaultY)

        local left, top = mainContainerFrame:GetLeft(), mainContainerFrame:GetTop()
        if left and top then
            local parentBottom, parentLeft = UIParent:GetBottom(), UIParent:GetLeft()
            if parentBottom and parentLeft then
                DB.displayPoint = { point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", x = left - parentLeft, y = top - parentBottom }
                WRA:PrintDebug("Display_Icons 位置已重置并保存。")
                self:UpdateFrameAppearanceAndLayout()
            else
                WRA:PrintError("重置位置时无法获取父框架坐标。")
            end
        else
            WRA:PrintError("重置位置时无法获取框架坐标。")
        end
    else
        WRA:PrintError("无法重置位置，主框架无效或未创建。")
    end
end

function Display_Icons:UpdateFrameAppearanceAndLayout()
    if not mainContainerFrame or not mainContainerFrame:IsObjectType("Frame") then
        WRA:PrintDebug("UpdateFrameAppearanceAndLayout: mainContainerFrame 无效或尚未创建。")
        return
    end
    if not DB then
        if WRA.db and WRA.db.profile and WRA.db.profile.displayIcons then DB = WRA.db.profile.displayIcons
        else WRA:PrintError("UpdateFrameAppearanceAndLayout: 数据库引用为 nil。"); return
        end
    end

    local pos = DB.displayPoint
    mainContainerFrame:ClearAllPoints()
    if pos and pos.point and pos.relativeTo and _G[pos.relativeTo] and pos.relativePoint and type(pos.x) == "number" and type(pos.y) == "number" then
        mainContainerFrame:SetPoint(pos.point, _G[pos.relativeTo], pos.relativePoint, pos.x, pos.y)
    else
        WRA:PrintDebug("无效或缺失的 displayPoint，使用默认位置 CENTER, 0, 150。")
        mainContainerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end

    mainContainerFrame:SetScale(DB.displayScale or 1.0)
    mainContainerFrame:SetAlpha(DB.displayAlpha or 1.0)
    if mainContainerFrame.SetMovable then mainContainerFrame:SetMovable(not DB.displayLocked) end

    if mainContainerFrame.SetBackdropBorderColor then
        if DB.displayLocked then mainContainerFrame:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
        else mainContainerFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end
    end

    local iconSize = DB.iconSize or DEFAULT_ICON_SIZE
    local colorBlockHeight = (DB.showColorBlocks and (DB.colorBlockHeight or DEFAULT_COLOR_BLOCK_HEIGHT)) or 0

    local slotHeightWithBlockBelow = iconSize + ( (DB.colorBlockBelowIcon and colorBlockHeight > 0) and (colorBlockHeight + 2) or 0)
    local slotHeightIconOnly = iconSize
    local currentSlotHeight = (DB.showColorBlocks and DB.colorBlockBelowIcon and colorBlockHeight > 0) and slotHeightWithBlockBelow or slotHeightIconOnly

    local insetLeft = DEFAULT_BACKDROP_INSET
    local insetRight = DEFAULT_BACKDROP_INSET
    local insetTop = DEFAULT_BACKDROP_INSET
    local insetBottom = DEFAULT_BACKDROP_INSET

    if gcdSlot.elementsCreated then
        if gcdSlot.icon and gcdSlot.icon:IsObjectType("Texture") then
            gcdSlot.icon:SetSize(iconSize, iconSize)
            gcdSlot.icon:ClearAllPoints()
            gcdSlot.icon:SetPoint("TOPLEFT", insetLeft, -insetTop)

            if DB.showColorBlocks and colorBlockHeight > 0 then
                if gcdSlot.colorBlock and gcdSlot.colorBlock:IsObjectType("Texture") then 
                    gcdSlot.colorBlock:SetSize(iconSize, colorBlockHeight)
                    gcdSlot.colorBlock:ClearAllPoints()
                    if DB.colorBlockBelowIcon then
                        gcdSlot.colorBlock:SetPoint("TOPLEFT", gcdSlot.icon, "BOTTOMLEFT", 0, -2)
                        gcdSlot.colorBlock:SetDrawLayer("ARTWORK") 
                    else
                        gcdSlot.colorBlock:SetAllPoints(gcdSlot.icon)
                        gcdSlot.colorBlock:SetDrawLayer("BACKGROUND") 
                    end
                    gcdSlot.colorBlock:Show()
                else
                     WRA:PrintDebug("Display_Icons: gcdSlot.colorBlock is nil or not a Texture when trying to set it up.")
                end
            elseif gcdSlot.colorBlock and gcdSlot.colorBlock:IsObjectType("Texture") then
                gcdSlot.colorBlock:Hide()
            end
            gcdSlot.icon:Show()
            if gcdSlot.cooldownText and gcdSlot.cooldownText:IsObjectType("FontString") and gcdSlot.icon and gcdSlot.icon:IsObjectType("Texture") then
                gcdSlot.cooldownText:ClearAllPoints()
                gcdSlot.cooldownText:SetPoint("CENTER", gcdSlot.icon, "CENTER", 0, 0)
            end
        else
            WRA:PrintError("Display_Icons: gcdSlot.icon is nil or not a Texture, even though elementsCreated is true.")
        end
    end

    local offGcdSlotVisible = DB.showOffGCDSlot
    local offGcdIconSize = iconSize * 0.8
    local offGcdColorBlockHeight = colorBlockHeight * 0.8

    if offGcdSlot.elementsCreated then
        if offGcdSlotVisible then
            if offGcdSlot.icon and offGcdSlot.icon:IsObjectType("Texture") then
                offGcdSlot.icon:SetSize(offGcdIconSize, offGcdIconSize)
                offGcdSlot.icon:ClearAllPoints()
                if gcdSlot.icon and gcdSlot.icon:IsObjectType("Texture") then
                    offGcdSlot.icon:SetPoint("TOPLEFT", gcdSlot.icon, "TOPRIGHT", SLOT_SPACING, 0)
                else
                     offGcdSlot.icon:SetPoint("TOPLEFT", insetLeft, -insetTop)
                end
                offGcdSlot.icon:Show()

                if DB.showColorBlocks and offGcdColorBlockHeight > 0 then
                    if offGcdSlot.colorBlock and offGcdSlot.colorBlock:IsObjectType("Texture") then 
                        offGcdSlot.colorBlock:SetSize(offGcdIconSize, offGcdColorBlockHeight)
                        offGcdSlot.colorBlock:ClearAllPoints()
                        if DB.colorBlockBelowIcon then
                            offGcdSlot.colorBlock:SetPoint("TOPLEFT", offGcdSlot.icon, "BOTTOMLEFT", 0, -2)
                            offGcdSlot.colorBlock:SetDrawLayer("ARTWORK")
                        else
                            offGcdSlot.colorBlock:SetAllPoints(offGcdSlot.icon)
                            offGcdSlot.colorBlock:SetDrawLayer("BACKGROUND")
                        end
                        offGcdSlot.colorBlock:Show()
                    else
                        WRA:PrintDebug("Display_Icons: offGcdSlot.colorBlock is nil or not a Texture when trying to set it up.")
                    end
                elseif offGcdSlot.colorBlock and offGcdSlot.colorBlock:IsObjectType("Texture") then
                    offGcdSlot.colorBlock:Hide()
                end
                if offGcdSlot.cooldownText and offGcdSlot.cooldownText:IsObjectType("FontString") and offGcdSlot.icon and offGcdSlot.icon:IsObjectType("Texture") then
                     offGcdSlot.cooldownText:ClearAllPoints()
                     offGcdSlot.cooldownText:SetPoint("CENTER", offGcdSlot.icon, "CENTER", 0, 0)
                     offGcdSlot.cooldownText:SetFontObject(GameFontNormal)
                end
            else
                 WRA:PrintDebug("Display_Icons: offGcdSlot.icon is nil or not a Texture, even though elementsCreated and offGcdSlotVisible are true.")
            end
        else
            if offGcdSlot.icon and offGcdSlot.icon.Hide then offGcdSlot.icon:Hide() end
            if offGcdSlot.colorBlock and offGcdSlot.colorBlock.Hide then offGcdSlot.colorBlock:Hide() end
            if offGcdSlot.cooldownText and offGcdSlot.cooldownText.Hide then offGcdSlot.cooldownText:Hide() end
        end
    end

    local totalContentWidth = iconSize
    if offGcdSlotVisible then
        totalContentWidth = totalContentWidth + SLOT_SPACING + offGcdIconSize
    end
    local totalContentHeight = currentSlotHeight

    mainContainerFrame:SetSize(totalContentWidth + insetLeft + insetRight, totalContentHeight + insetTop + insetBottom)
end


function Display_Icons:UpdateDisplay(actionsTable)
    if not mainContainerFrame or not mainContainerFrame:IsObjectType("Frame") then
        WRA:PrintDebug("UpdateDisplay: 已中止，mainContainerFrame 无效。")
        return
    end

    if not gcdSlot.elementsCreated or not offGcdSlot.elementsCreated then
        WRA:PrintDebug("UpdateDisplay: 槽位元素尚未创建。")
        CreateDisplayElements()
        if not (mainContainerFrame and mainContainerFrame:IsObjectType("Frame") and gcdSlot.elementsCreated and offGcdSlot.elementsCreated) then
             WRA:PrintError("UpdateDisplay: CreateDisplayElements 未能成功创建所有元素。")
             return
        end
    end

    actionsTable = actionsTable or {}
    local gcdActionID = actionsTable.gcdAction
    local offGcdActionID = actionsTable.offGcdAction

    local gcdDisplayInfo = GetActionDisplayInfo(gcdActionID)
    if gcdSlot.icon and gcdSlot.icon:IsObjectType("Texture") and gcdSlot.icon.SetTexture then
        gcdSlot.icon:SetTexture(gcdDisplayInfo.texture)
        gcdSlot.icon:Show()
    end
    if DB.showColorBlocks and gcdSlot.colorBlock and gcdSlot.colorBlock:IsObjectType("Texture") and gcdSlot.colorBlock.SetColorTexture then
        gcdSlot.colorBlock:SetColorTexture(gcdDisplayInfo.color.r, gcdDisplayInfo.color.g, gcdDisplayInfo.color.b, gcdDisplayInfo.color.a or 1)
        gcdSlot.colorBlock:Show()
    elseif gcdSlot.colorBlock and gcdSlot.colorBlock.Hide then
        gcdSlot.colorBlock:Hide()
    end
    if gcdSlot.cooldownText and gcdSlot.cooldownText.Hide then gcdSlot.cooldownText:Hide() end

    if DB.showOffGCDSlot then
        if offGcdActionID and offGcdActionID ~= ACTION_ID_IDLE and offGcdActionID ~= ACTION_ID_WAITING then
            local offGcdDisplayInfo = GetActionDisplayInfo(offGcdActionID)
            if offGcdSlot.icon and offGcdSlot.icon:IsObjectType("Texture") and offGcdSlot.icon.SetTexture then
                offGcdSlot.icon:SetTexture(offGcdDisplayInfo.texture)
                offGcdSlot.icon:Show()
            end
            if DB.showColorBlocks and offGcdSlot.colorBlock and offGcdSlot.colorBlock:IsObjectType("Texture") and offGcdSlot.colorBlock.SetColorTexture then
                offGcdSlot.colorBlock:SetColorTexture(offGcdDisplayInfo.color.r, offGcdDisplayInfo.color.g, offGcdDisplayInfo.color.b, offGcdDisplayInfo.color.a or 1)
                offGcdSlot.colorBlock:Show()
            elseif offGcdSlot.colorBlock and offGcdSlot.colorBlock.Hide then
                offGcdSlot.colorBlock:Hide()
            end
            if offGcdSlot.cooldownText and offGcdSlot.cooldownText.Hide then offGcdSlot.cooldownText:Hide() end
        else
            if offGcdSlot.icon and offGcdSlot.icon.Hide then offGcdSlot.icon:Hide() end
            if offGcdSlot.colorBlock and offGcdSlot.colorBlock.Hide then offGcdSlot.colorBlock:Hide() end
            if offGcdSlot.cooldownText and offGcdSlot.cooldownText.Hide then offGcdSlot.cooldownText:Hide() end
        end
    else
        if offGcdSlot.icon and offGcdSlot.icon.Hide then offGcdSlot.icon:Hide() end
        if offGcdSlot.colorBlock and offGcdSlot.colorBlock.Hide then offGcdSlot.colorBlock:Hide() end
        if offGcdSlot.cooldownText and offGcdSlot.cooldownText.Hide then offGcdSlot.cooldownText:Hide() end
    end
end

function Display_Icons:OnProfileChanged(event, database, newProfileKey)
    WRA:PrintDebug("Display_Icons: OnProfileChanged 触发。新档案: " .. tostring(newProfileKey))
    if database and database.profile and database.profile.displayIcons then
        DB = database.profile.displayIcons
        if mainContainerFrame and mainContainerFrame:IsObjectType("Frame") then
            self:UpdateFrameAppearanceAndLayout()
        end
        WRA:PrintDebug("Display_Icons 档案已更改/应用。")
    else
        WRA:PrintError("Display_Icons: 在档案更改时收到无效的数据库。")
    end
end

function Display_Icons:RefreshConfig()
    WRA:PrintDebug("Display_Icons RefreshConfig 已调用。")
    if WRA.db and WRA.db.profile and WRA.db.profile.displayIcons then
        DB = WRA.db.profile.displayIcons
    end
    if mainContainerFrame and mainContainerFrame:IsObjectType("Frame") then
        self:UpdateFrameAppearanceAndLayout()
    end
end

function Display_Icons:GetOptionsTable()
    local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
    if not L then L = setmetatable({}, {__index=function(t,k) return k end}) end

    if not DB then
        if WRA.db and WRA.db.profile and WRA.db.profile.displayIcons then
            DB = WRA.db.profile.displayIcons
        else
            WRA:PrintError("Display_Icons:GetOptionsTable - DB 未初始化，无法创建选项。")
            return {}
        end
    end

    return {
        locked = {
            order = 1, type = "toggle", name = L["LOCK_DISPLAY_NAME"] or "锁定位置",
            desc = L["LOCK_DISPLAY_DESC"] or "锁定提示框的位置，防止意外拖动。",
            get = function(info) return DB.displayLocked end,
            set = function(info, value) DB.displayLocked = value; self:UpdateFrameAppearanceAndLayout() end,
        },
        resetPos = {
            order = 2, type = "execute", name = L["RESET_DISPLAY_POSITION_NAME"] or "重置位置",
            desc = L["RESET_DISPLAY_POSITION_DESC"] or "将提示框的位置和大小重置为默认值。",
            func = function() self:ResetPosition() end,
        },
        scale = {
            order = 3, type = "range", name = L["DISPLAY_SCALE_NAME"] or "缩放",
            desc = L["DISPLAY_SCALE_DESC"] or "调整提示框的整体缩放比例。",
            min = 0.5, max = 2.0, step = 0.05,
            get = function(info) return DB.displayScale end,
            set = function(info, value) DB.displayScale = value; self:UpdateFrameAppearanceAndLayout() end,
        },
        alpha = {
            order = 4, type = "range", name = L["DISPLAY_ALPHA_NAME"] or "透明度",
            desc = L["DISPLAY_ALPHA_DESC"] or "调整提示框的透明度。",
            min = 0.1, max = 1.0, step = 0.05,
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
    }
end
