--[[
    Light Damage - UIPinned.lua
    固定自己排名系统
]]
local addonName, ns = ...
local L = ns.L
local UI = ns.UI
local INTERP = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

-- module-level helper：用于 pcall 调用而不创建闭包
local function _safeSetBarValue(fs, total, ps, showPS, isCount, suffix)
    if isCount then
        fs:SetFormattedText("%s" .. suffix, ns.AbbrevNumber(total))
    elseif showPS then
        fs:SetFormattedText("%s (%s)", ns.AbbrevNumber(total), ns.AbbrevNumber(ps))
    else
        fs:SetText(ns.AbbrevNumber(total))
    end
end

local function _safeSetStatusBar(sb, maxV, val)
    if INTERP then
        sb:SetMinMaxValues(0, maxV, INTERP)
        sb:SetValue(val, INTERP)
    else
        sb:SetMinMaxValues(0, maxV)
        sb:SetValue(val)
    end
end

function UI:MakePinnedSelfBar(container, sf, section)
    local bar = self:MakeBar(container, section, 0)
    bar.frame:SetFrameLevel(sf:GetFrameLevel() + 10); bar._isPinned = true; bar.frame:Hide(); return bar
end

function UI:GetSelfViewportPosition(listObj, selfIdx)
    local bh, gap = self:GetBarConfig(); local rowH = bh + gap; if rowH <= 0 then return "visible" end
    local viewH = listObj.sf:GetHeight(); local scrollOffset = listObj.sf:GetVerticalScroll() or 0
    local selfTop = (selfIdx - 1) * rowH; local selfBottom = selfTop + bh
    local viewTop = scrollOffset; local viewBottom = scrollOffset + viewH
    if selfBottom <= viewTop then return "above" end; if selfTop >= viewBottom then return "below" end; return "visible"
end

function UI:PositionPinnedBar(pinnedBar, listObj, position)
    local bh, gap, _, font, fSz, fOut, fShad = self:GetBarConfig()
    pinnedBar.frame:ClearAllPoints(); pinnedBar.frame:SetHeight(bh)
    if position == "top" then
        pinnedBar.frame:SetPoint("BOTTOMLEFT", listObj.sf, "TOPLEFT", 0, 0); pinnedBar.frame:SetPoint("BOTTOMRIGHT", listObj.sf, "TOPRIGHT", 0, 0)
    else
        pinnedBar.frame:SetPoint("TOPLEFT", listObj.sf, "BOTTOMLEFT", 0, 0); pinnedBar.frame:SetPoint("TOPRIGHT", listObj.sf, "BOTTOMRIGHT", 0, 0)
    end
    self:AnchorBarTexts(pinnedBar)
    self:ApplyFont(pinnedBar.rank, font, fSz-1, fOut, fShad); self:ApplyFont(pinnedBar.name, font, fSz, fOut, fShad); self:ApplyFont(pinnedBar.value, font, fSz-1, fOut, fShad)
end

function UI:FillPinnedFromData(pinnedBar, listObj, d, rank, dur, mode, maxV, position)
    self:PositionPinnedBar(pinnedBar, listObj, position)
    local bh, gap, alpha = self:GetBarConfig(); local texPath = ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8"
    local textMode = ns.db.display.textColorMode or "class"
    pinnedBar.statusbar:Hide(); pinnedBar.fill:Show()
    local cc = ns:GetClassColor(d.class) or {0.5, 0.5, 0.5}
    local offset = ns.db.display.showSpecIcon and (bh + 4) or 0
    local maxBarW = math.max(1, listObj.child:GetWidth() - offset)
    pinnedBar.fill:SetWidth(math.max(1, maxBarW * (maxV > 0 and (d.value / maxV) or 0)))
    pinnedBar.fill:SetTexture(texPath); pinnedBar.fill:SetVertexColor(cc[1], cc[2], cc[3], alpha)
    pinnedBar.statusbar:SetStatusBarTexture(texPath)
    pinnedBar.rank:SetText(ns.db.display.showRank and (rank .. ".") or "")
    pinnedBar.name:SetText(ns:DisplayName(d.name))
    do local nr, ng, nb
        if textMode == "white" then nr, ng, nb = 1, 1, 1
        elseif textMode == "custom" then local c = ns.db.display.textColor or {1,1,1}; nr, ng, nb = c[1], c[2], c[3]
        else nr, ng, nb = cc[1], cc[2], cc[3] end; pinnedBar.name:SetTextColor(nr, ng, nb)
    end
    pinnedBar.value:SetText(self:MakeValueStr(d.value, dur, mode, d.perSec, d.percent))
    pinnedBar._data = d; pinnedBar._mode = mode; pinnedBar._isDeath = false; pinnedBar._guid = d.guid; pinnedBar._nameStr = d.name; pinnedBar._classStr = d.class
    if pinnedBar.specIcon then
        local specID = d.specID
        if d.guid == ns.state.playerGUID then
            local idx = GetSpecialization()
            if idx then specID = GetSpecializationInfo(idx) end
        end
        local icon = ns:GetSpecIcon(specID, d.class, d.specIconID)
        if ns.db.display.showSpecIcon and icon then
            pinnedBar.specIcon:SetTexture(icon)
            pinnedBar.specIcon:Show()
        else
            pinnedBar.specIcon:Hide()
        end
    end
    pinnedBar.frame:Show()
end

function UI:FillPinnedFromAPI(pinnedBar, listObj, src, rank, mode, maxAmt, sType, position)
    self:PositionPinnedBar(pinnedBar, listObj, position)
    local bh, gap, alpha = self:GetBarConfig(); local texPath = ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8"
    local textMode = ns.db.display.textColorMode or "class"
    pinnedBar.fill:Hide(); pinnedBar.statusbar:Show()
    local cls = src.classFilename or "WARRIOR"; local cc = ns:GetClassColor(cls) or {0.5, 0.5, 0.5}
    pinnedBar.statusbar:SetStatusBarTexture(texPath); pinnedBar.statusbar:SetStatusBarColor(cc[1], cc[2], cc[3], alpha)

    -- statusbar:用 helper + pcall(无闭包)
    pcall(_safeSetStatusBar, pinnedBar.statusbar, maxAmt or 1, src.totalAmount)

    pinnedBar.rank:SetText(ns.db.display.showRank and (rank .. ".") or "")

    -- name:secret value 时跳过
    local nameRaw = src.name
    local nameStr = ""
    local isSecret = issecretvalue and issecretvalue(nameRaw)

    if isSecret then
        nameStr = nameRaw
    elseif nameRaw then
        local ok, str = pcall(tostring, nameRaw)
        if ok and str then nameStr = str end
    end
    pinnedBar.name:SetText(ns:DisplayName(nameStr))

    do local nr, ng, nb
        if textMode == "white" then nr, ng, nb = 1, 1, 1
        elseif textMode == "custom" then local c = ns.db.display.textColor or {1,1,1}; nr, ng, nb = c[1], c[2], c[3]
        else nr, ng, nb = cc[1], cc[2], cc[3] end; pinnedBar.name:SetTextColor(nr, ng, nb)
    end

    -- value:用 helper + pcall(无闭包)
    pcall(_safeSetBarValue, pinnedBar.value, src.totalAmount, src.amountPerSecond,
          ns.db.display.showPerSecond, UI.COUNT_MODES[mode], L["次"])
    if not pinnedBar._apiData then pinnedBar._apiData = {} end
    pinnedBar._apiData.isAPI = true; pinnedBar._apiData.sourceGUID = src.sourceGUID; pinnedBar._apiData.sourceCreatureID = src.sourceCreatureID
    pinnedBar._apiData.isLocalPlayer = true; pinnedBar._apiData.totalAmount = src.totalAmount; pinnedBar._apiData.amountPerSecond = src.amountPerSecond; pinnedBar._apiData.sessionType = sType
    pinnedBar._apiData.specIconID = src.specIconID
    pinnedBar._data = pinnedBar._apiData; pinnedBar._mode = mode; pinnedBar._isDeath = false; pinnedBar._guid = src.sourceGUID; pinnedBar._nameStr = src.name; pinnedBar._classStr = cls
    if pinnedBar.specIcon then
        local specIdx = GetSpecialization()
        local specID = specIdx and GetSpecializationInfo(specIdx) or nil
        local icon = ns:GetSpecIcon(specID, cls, src.specIconID)
        if ns.db.display.showSpecIcon and icon then pinnedBar.specIcon:SetTexture(icon); pinnedBar.specIcon:Show() else pinnedBar.specIcon:Hide() end
    end
    pinnedBar.frame:Show()
end

function UI:ShrinkSfForPinned(listKey, listObj, dataCount, position)
    if not self._pinnedSfOrigH then self._pinnedSfOrigH = {} end
    if not self._pinnedSfOrigH[listKey] then self._pinnedSfOrigH[listKey] = listObj.sf:GetHeight() end
    local bh = self:GetBarConfig(); local newH = math.max(1, self._pinnedSfOrigH[listKey] - bh)
    if position == "top" then
        if not self._pinnedSfSavedAnchors then self._pinnedSfSavedAnchors = {} end
        if not self._pinnedSfSavedAnchors[listKey] then
            local n = listObj.sf:GetNumPoints(); local anchors = {}
            for i = 1, n do anchors[i] = { listObj.sf:GetPoint(i) } end
            self._pinnedSfSavedAnchors[listKey] = anchors
            listObj.sf:ClearAllPoints()
            for _, a in ipairs(anchors) do
                local point, rel, relPoint, x, y = unpack(a)
                if point:find("TOP") then listObj.sf:SetPoint(point, rel, relPoint, x, y - bh)
                else listObj.sf:SetPoint(point, rel, relPoint, x, y) end
            end
        end
    end
    listObj.sf:SetHeight(newH); self:UpdateScrollState(listObj, dataCount)
end

function UI:RestoreSfForPinned(listKey, listObj, dataCount)
    local restored = false
    if self._pinnedSfOrigH and self._pinnedSfOrigH[listKey] then listObj.sf:SetHeight(self._pinnedSfOrigH[listKey]); self._pinnedSfOrigH[listKey] = nil; restored = true end
    if self._pinnedSfSavedAnchors and self._pinnedSfSavedAnchors[listKey] then
        listObj.sf:ClearAllPoints(); for _, a in ipairs(self._pinnedSfSavedAnchors[listKey]) do listObj.sf:SetPoint(unpack(a)) end
        self._pinnedSfSavedAnchors[listKey] = nil; restored = true
    end
    if restored then self:UpdateScrollState(listObj, dataCount) end
end

function UI:CheckPinnedSelfForBars(listKey, listObj, data, dur, mode, count)
    if not self._pinnedSelf then return end; local pinnedBar = self._pinnedSelf[listKey]; if not pinnedBar then return end
    if not self._pinnedSelfCache then self._pinnedSelfCache = {} end
    self._pinnedSelfCache[listKey] = { type = "bars", data = data, dur = dur, mode = mode, count = count }
    self:RestoreSfForPinned(listKey, listObj, count)
    if not ns.db.display.alwaysShowSelf or mode == "deaths" then pinnedBar.frame:Hide(); return end
    local selfIdx, selfData = nil, nil
    for i, d in ipairs(data) do if d.guid == ns.state.playerGUID then selfIdx = i; selfData = d; break end end
    if not selfIdx or not selfData then pinnedBar.frame:Hide(); return end
    local position = self:GetSelfViewportPosition(listObj, selfIdx)
    if position == "visible" then pinnedBar.frame:Hide(); return end
    self:ShrinkSfForPinned(listKey, listObj, count, position)
    local maxV = data[1] and data[1].value or 0
    self:FillPinnedFromData(pinnedBar, listObj, selfData, selfIdx, dur, mode, maxV, position)
end

function UI:CheckPinnedSelfForAPI(listKey, listObj, sources, mode, maxAmt, sType)
    if not self._pinnedSelf then return end; local pinnedBar = self._pinnedSelf[listKey]; if not pinnedBar then return end
    local count = math.min(#sources, UI.MAX_BARS)
    if not self._pinnedSelfCache then self._pinnedSelfCache = {} end
    self._pinnedSelfCache[listKey] = { type = "api", sources = sources, mode = mode, maxAmt = maxAmt, sType = sType }
    self:RestoreSfForPinned(listKey, listObj, count)
    if not ns.db.display.alwaysShowSelf or mode == "deaths" then pinnedBar.frame:Hide(); return end
    local selfIdx, selfSrc = nil, nil
    for i, src in ipairs(sources) do if src.isLocalPlayer then selfIdx = i; selfSrc = src; break end end
    if not selfIdx or not selfSrc then pinnedBar.frame:Hide(); return end
    local position = self:GetSelfViewportPosition(listObj, selfIdx)
    if position == "visible" then pinnedBar.frame:Hide(); return end
    self:ShrinkSfForPinned(listKey, listObj, count, position)
    self:FillPinnedFromAPI(pinnedBar, listObj, selfSrc, selfIdx, mode, maxAmt, sType, position)
end
