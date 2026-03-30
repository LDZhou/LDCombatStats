--[[
    Light Damage - UILayout.lua
    排版：Layout, DoLayout, AnchorBarTexts
]]

local addonName, ns = ...
local L = ns.L
local UI = ns.UI

function UI:Layout()
    if not self.frame or not self.frame:IsShown() then return end
    if self._layoutPending then return end
    self._layoutPending = true

    if ns.db.display.mode == "split" and not self:IsSplitActiveInCurrentScene() then
        ns.db.display.mode = (ns.db.split and ns.db.split.primaryMode) or "damage"
    end
    self:LayoutTabs()

    local showSumm = (ns.db and ns.db.mythicPlus and ns.db.mythicPlus.dualDisplay) and ns.state.isInInstance and self:IsOverallColumnActive() or false
    if showSumm then self.summaryBar:Show(); self.bodyFrame:SetPoint("TOPLEFT", self.summaryBar, "BOTTOMLEFT", 0, 0)
    else self.summaryBar:Hide(); self.bodyFrame:SetPoint("TOPLEFT", self.titleBar, "BOTTOMLEFT", 0, 0) end
    self.bodyFrame:SetPoint("BOTTOMRIGHT", self.tabBar, "TOPRIGHT", 0, 0)

    C_Timer.After(0, function()
        self._layoutPending = false
        self:DoLayout(0)
    end)
    self:UpdateLockState()
end

function UI:DoLayout(retryCount)
    if not self.bodyFrame then return end
    retryCount = retryCount or 0
    self:ApplyAllFontsIfNeeded()
    self._pinnedSfOrigH = {}; self._pinnedSfSavedAnchors = {}

    local bodyH = self.bodyFrame:GetHeight(); local bodyW = self.bodyFrame:GetWidth()
    if bodyW <= 0 or bodyH <= 0 then
        if retryCount < 20 then
            C_Timer.After(0.05, function() self:DoLayout(retryCount + 1) end)
        else
            if self._collapsed then return end
            -- 重试耗尽，强制恢复到默认尺寸
            local dw, dh = self:ClampSize(ns.db.window.width, ns.db.window.height)
            self.frame:SetSize(dw, dh)
            ns.db.window.width = dw; ns.db.window.height = dh
            C_Timer.After(0.1, function() self:DoLayout(0) end)
        end
        return
    end

    local sp = ns.db.split
    local useOvr = self:IsOverallColumnActive()
    local isSplitView = self:IsSplitActiveInCurrentScene() and (ns.db.display.mode == "split")
    local SECTH_H = UI.SECTH_H

    local curW, curH = bodyW, bodyH
    local ovrW, ovrH = 0, 0
    local curX, curY = 0, 0
    local ovrX, ovrY = 0, 0

    if useOvr then
        if sp.overallDir == "LR" then
            local lrRatio = sp.lrRatio or 0.5; local w1 = bodyW * lrRatio; local gap = 2; local sepW = 1; local w2 = bodyW - w1 - sepW - gap
            ovrH = bodyH
            if sp.currentPos == 1 then curW, ovrW = w1 - gap, w2; curX, ovrX = 0, w1 + sepW + gap
            else ovrW, curW = w1 - gap, w2; ovrX, curX = 0, w1 + sepW + gap end
            self.ovrSepLine:ClearAllPoints(); self.ovrSepLine:SetPoint("TOPLEFT", self.bodyFrame, "TOPLEFT", w1, 0)
            self.ovrSepLine:SetPoint("BOTTOMLEFT", self.bodyFrame, "BOTTOMLEFT", w1, 0); self.ovrSepLine:SetSize(sepW, bodyH); self.ovrSepLine:Show()
        else
            local tbRatio = sp.tbRatio or 0.5; local h1 = bodyH * tbRatio; local sepW = 1; local gap = 2; local h2 = bodyH - h1 - sepW - gap
            ovrW = bodyW
            if sp.currentPos == 1 then curH, ovrH = h1 - gap, h2; curY, ovrY = 0, -(h1 + sepW + gap)
            else ovrH, curH = h1 - gap, h2; ovrY, curY = 0, -(h1 + sepW + gap) end
            self.ovrSepLine:ClearAllPoints(); self.ovrSepLine:SetPoint("TOPLEFT", self.bodyFrame, "TOPLEFT", 0, -h1)
            self.ovrSepLine:SetPoint("TOPRIGHT", self.bodyFrame, "TOPRIGHT", 0, -h1); self.ovrSepLine:SetSize(bodyW, sepW); self.ovrSepLine:Show()
        end
        self.ovrContainer:ClearAllPoints(); self.ovrContainer:SetPoint("TOPLEFT", self.bodyFrame, "TOPLEFT", ovrX, ovrY)
        self.ovrContainer:SetSize(ovrW, ovrH); self.ovrContainer:Show()
    else self.ovrSepLine:Hide(); self.ovrContainer:Hide() end

    self.leftContainer:ClearAllPoints(); self.leftContainer:SetPoint("TOPLEFT", self.bodyFrame, "TOPLEFT", curX, curY); self.leftContainer:SetSize(curW, curH)

    local function LayoutInner(container, head1, list1, head2, list2, w, h, isSplit, mode1, mode2)
        if not isSplit then
            head1:Show(); head1:ClearAllPoints(); head1:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0); head1:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
            list1.sf:Show(); list1.sf:ClearAllPoints(); list1.sf:SetPoint("TOPLEFT", head1, "BOTTOMLEFT", 0, 0); list1.sf:SetPoint("TOPRIGHT", head1, "BOTTOMRIGHT", 0, 0)
            list1.sf:SetHeight(math.max(1, h - SECTH_H)); head2:Hide(); list2.sf:Hide()
            return
        end
        local splitDir = sp.splitDir or "TB"; head1:Show(); head2:Show(); list1.sf:Show(); list2.sf:Show()
        if splitDir == "TB" then
            local tbRatio = sp.tbRatio or 0.5; local h1 = h * tbRatio; local gap = 2; local h2 = h - h1 - gap
            local topHead, bottomHead, topList, bottomList
            if sp.primaryPos == 1 then topHead, bottomHead, topList, bottomList = head1, head2, list1, list2
            else topHead, bottomHead, topList, bottomList = head2, head1, list2, list1 end
            topHead:ClearAllPoints(); topHead:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0); topHead:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
            topList.sf:ClearAllPoints(); topList.sf:SetPoint("TOPLEFT", topHead, "BOTTOMLEFT", 0, 0); topList.sf:SetPoint("TOPRIGHT", topHead, "BOTTOMRIGHT", 0, 0); topList.sf:SetHeight(math.max(1, h1 - gap - SECTH_H))
            bottomHead:ClearAllPoints(); bottomHead:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -h1); bottomHead:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -h1)
            bottomList.sf:ClearAllPoints(); bottomList.sf:SetPoint("TOPLEFT", bottomHead, "BOTTOMLEFT", 0, 0); bottomList.sf:SetPoint("TOPRIGHT", bottomHead, "BOTTOMRIGHT", 0, 0); bottomList.sf:SetHeight(math.max(1, h2 - SECTH_H))
        else
            local lrRatio = sp.lrRatio or 0.5; local gap = 2; local w1 = w * lrRatio; local w2 = w - w1 - gap
            local leftHead, rightHead, leftList, rightList
            if sp.primaryPos == 1 then leftHead, rightHead, leftList, rightList = head1, head2, list1, list2
            else leftHead, rightHead, leftList, rightList = head2, head1, list2, list1 end
            leftHead:ClearAllPoints(); leftHead:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0); leftHead:SetWidth(w1 - gap)
            leftList.sf:ClearAllPoints(); leftList.sf:SetPoint("TOPLEFT", leftHead, "BOTTOMLEFT", 0, 0); leftList.sf:SetPoint("TOPRIGHT", leftHead, "BOTTOMRIGHT", 0, 0); leftList.sf:SetHeight(math.max(1, h - SECTH_H))
            rightHead:ClearAllPoints(); rightHead:SetPoint("TOPLEFT", container, "TOPLEFT", w1, 0); rightHead:SetWidth(w2)
            rightList.sf:ClearAllPoints(); rightList.sf:SetPoint("TOPLEFT", rightHead, "BOTTOMLEFT", 0, 0); rightList.sf:SetPoint("TOPRIGHT", rightHead, "BOTTOMRIGHT", 0, 0); rightList.sf:SetHeight(math.max(1, h - SECTH_H))
        end
    end

    LayoutInner(self.leftContainer, self.priHead, self.priList, self.secHead, self.secList, curW, curH, isSplitView, sp.primaryMode, sp.secondaryMode)
    if useOvr then
        LayoutInner(self.ovrContainer, self.ovrPriHead, self.ovrPriList, self.ovrSecHead, self.ovrSecList, ovrW, ovrH, isSplitView, sp.primaryMode, sp.secondaryMode)
        self.ovrPriHead.info:Hide(); self.ovrSecHead.info:Hide()
        local ovrTitleWord = L["总计"]
        if ns.Segments and ns.Segments.overall and ns.Segments.overall._isMerged then ovrTitleWord = L["全程"] end
        if isSplitView then
            local priLabel = L[ns.MODE_NAMES[sp.primaryMode] or ""]
            local secLabel = L[ns.MODE_NAMES[sp.secondaryMode] or ""]
            if sp.primaryMode == "damageTaken" and ns.state.damageTakenView == "enemy" then priLabel = L["敌人承伤"] end
            if sp.secondaryMode == "damageTaken" and ns.state.damageTakenView == "enemy" then secLabel = L["敌人承伤"] end
            self.ovrPriHead.label:SetText(string.format(L["|cff4cb8e8[%s%s]|r"], ovrTitleWord, priLabel))
            self.ovrSecHead.label:SetText(string.format(L["|cff4cb8e8[%s%s]|r"], ovrTitleWord, secLabel))
        else
            local modeLabel = L[ns.MODE_NAMES[ns.db.display.mode] or ""]
            if ns.db.display.mode == "damageTaken" and ns.state.damageTakenView == "enemy" then modeLabel = L["敌人承伤"] end
            self.ovrPriHead.label:SetText(string.format(L["|cff4cb8e8[%s%s]|r"], ovrTitleWord, modeLabel))
        end
    end
    self:Refresh()
end

function UI:AnchorBarTexts(bar)
    local rowH = ns.db.display.barHeight or 18; local iconSize = rowH
    local hash = (ns.db.display.showSpecIcon and "1" or "0") .. "|" .. rowH .. "|" .. (ns.db.display.barThickness or rowH) .. "|" .. (ns.db.display.barVOffset or 0)
    if bar._anchorHash == hash then return end; bar._anchorHash = hash
    local thickness = ns.db.display.barThickness or rowH; local vOffset = ns.db.display.barVOffset or 0

    if ns.db.display.showSpecIcon then
        bar.specIcon:SetSize(iconSize, iconSize); bar.specIcon:ClearAllPoints(); bar.specIcon:SetPoint("LEFT", bar.frame, "LEFT", 2, 0)
        local offset = iconSize + 4
        bar.bg:ClearAllPoints(); bar.bg:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", offset, vOffset); bar.bg:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset); bar.bg:SetHeight(thickness)
        bar.fill:ClearAllPoints(); bar.fill:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", offset, vOffset); bar.fill:SetHeight(thickness)
        bar.statusbar:ClearAllPoints(); bar.statusbar:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", offset, vOffset); bar.statusbar:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset); bar.statusbar:SetHeight(thickness)
        bar.textFrame:ClearAllPoints(); bar.textFrame:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", offset, 0); bar.textFrame:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, 0)
    else
        bar.specIcon:Hide()
        bar.bg:ClearAllPoints(); bar.bg:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", 0, vOffset); bar.bg:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset); bar.bg:SetHeight(thickness)
        bar.fill:ClearAllPoints(); bar.fill:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", 0, vOffset); bar.fill:SetHeight(thickness)
        bar.statusbar:ClearAllPoints(); bar.statusbar:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", 0, vOffset); bar.statusbar:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset); bar.statusbar:SetHeight(thickness)
        bar.textFrame:ClearAllPoints(); bar.textFrame:SetAllPoints(bar.frame)
    end
    bar.rank:ClearAllPoints(); bar.rank:SetPoint("LEFT", bar.textFrame, "LEFT", 3, 0)
    bar.value:ClearAllPoints(); bar.value:SetPoint("RIGHT", bar.textFrame, "RIGHT", -2, 0)
    bar.name:ClearAllPoints(); bar.name:SetPoint("LEFT", bar.rank, "RIGHT", 3, 0); bar.name:SetPoint("RIGHT", bar.value, "LEFT", -5, 0)
end
