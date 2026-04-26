--[[
    Light Damage - UIRefresh.lua
    刷新逻辑：Refresh, RefreshTitle, RefreshHead, ShowTooltip, FillOvrBars
]]
local addonName, ns = ...
local L = ns.L
local UI = ns.UI
local T = UI.T
local COUNT_MODES = UI.COUNT_MODES
local MODE_TO_DM = UI.MODE_TO_DM

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    -- 嵌套结构的 cache,wipe 子表
    if self._sessionCache then
        for _, sub in pairs(self._sessionCache) do wipe(sub) end
    else
        self._sessionCache = {}
    end

    local seg  = ns.Segments and ns.Segments:GetViewSegment()
    local dur  = ns.Analysis  and ns.Analysis:GetSegmentDuration(seg) or 0
    local sp   = ns.db.split; local mode = ns.db.display.mode
    local useOvr = self:IsOverallColumnActive()
    local isSplitView = self:IsSplitActiveInCurrentScene() and (ns.db.display.mode == "split")

    local function effMode(m)
        if m == "damageTaken" and ns.state.damageTakenView == "enemy" then return "enemyDamageTaken" end
        return m
    end

    -- RefreshTitle 节流:0.5s 内最多 1 次。M+ 倒计时本来就是秒级精度,不影响功能。
    local now = GetTime()
    if not self._lastTitleRefresh or (now - self._lastTitleRefresh) > 0.5 then
        self._lastTitleRefresh = now
        self:RefreshTitle()
    end

    -- Summary 栏
    if self.summaryBar:IsShown() then
        local ovrTitleWord = L["总计"]
        local ovrSeg = ns.Segments and ns.Segments.overall
        if ovrSeg and ovrSeg._isMerged then ovrTitleWord = L["全程"] end
        if ns.state.inCombat then
            local durSafe = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall) or 0
            local dmDmg = self:GetCachedSession(Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.DamageDone)
            local dmHeal = self:GetCachedSession(Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.HealingDone)
            local dmgStr, healStr = "0", "0"
            if dmDmg then local ok3, s = pcall(AbbreviateNumbers, dmDmg.totalAmount); if ok3 and s then dmgStr = s end end
            if dmHeal then local ok4, s = pcall(AbbreviateNumbers, dmHeal.totalAmount); if ok4 and s then healStr = s end end
            self.summText:SetFormattedText(L["全程 %s  |  Damage |cffffd100%s|r  Heal |cff66ff66%s|r"], ns:FormatTime(durSafe), dmgStr, healStr)
        else
            local ovrDmg = ovrSeg and ovrSeg.totalDamage or 0; local ovrHeal = ovrSeg and ovrSeg.totalHealing or 0
            local ovrDur = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall) or (ovrSeg and ovrSeg.duration or 0)
            if ovrDmg > 0 or ovrHeal > 0 then
                self.summText:SetText(string.format(L["%s %s  |  Damage |cffffd100%s|r  Heal |cff66ff66%s|r"], ovrTitleWord, ns:FormatTime(ovrDur), ns:FormatNumber(ovrDmg), ns:FormatNumber(ovrHeal)))
            else self.summText:SetText(string.format(L["%s 0:00  |  Damage 0  Heal 0"], ovrTitleWord)) end
        end
    end

    -- Tab 高亮
    if self.splitTab then
        if isSplitView then self.splitTab.abg:Show(); self.splitTab.text:SetTextColor(0, 0.75, 1)
        else self.splitTab.abg:Hide(); self.splitTab.text:SetTextColor(0.55, 0.55, 0.55) end
    end
    for _, t in ipairs(self.tabs) do
        if mode == t.mode then t.abg:Show(); t.text:SetTextColor(1, 1, 1)
        else t.abg:Hide(); t.text:SetTextColor(0.55, 0.55, 0.55) end
    end

    -- 数据路径
    local isDeathMode = (mode == "deaths"); local forceDataMode = isDeathMode
    local isOverall = ns.Segments and ns.Segments.viewIndex == 0
    local showingCurrent = ns.state.inCombat and ns.Segments and not isOverall and not (ns.Segments.viewIndex and ns.Segments.history[ns.Segments.viewIndex])
    local showingOverallInCombat = ns.state.inCombat and isOverall

    if showingCurrent and not forceDataMode then
        local sType = Enum.DamageMeterSessionType.Current
        if isSplitView then
            self:RefreshHead(self.priHead, sp.primaryMode, nil, 0, sType); self:RefreshHead(self.secHead, sp.secondaryMode, nil, 0, sType)
            self:FillBarsFromAPI(self.priBars, self.priList, effMode(sp.primaryMode), sType); self:FillBarsFromAPI(self.secBars, self.secList, effMode(sp.secondaryMode), sType)            
            if useOvr then self:FillOvrBars(isSplitView, sp, mode) end
        else
            self:RefreshHead(self.priHead, mode, nil, 0, sType); self:FillBarsFromAPI(self.priBars, self.priList, effMode(mode), sType)
            if useOvr then self:FillOvrBars(isSplitView, sp, mode) end
        end
    elseif showingOverallInCombat and not forceDataMode then
        local sType = Enum.DamageMeterSessionType.Overall
        if isSplitView then
            self:RefreshHead(self.priHead, sp.primaryMode, nil, 0, sType); self:RefreshHead(self.secHead, sp.secondaryMode, nil, 0, sType)
            self:FillBarsFromAPI(self.priBars, self.priList, effMode(sp.primaryMode), sType); self:FillBarsFromAPI(self.secBars, self.secList, effMode(sp.secondaryMode), sType)
            if useOvr then self:FillOvrBars(isSplitView, sp, mode) end
        else
            self:RefreshHead(self.priHead, mode, nil, 0, sType); self:FillBarsFromAPI(self.priBars, self.priList, effMode(mode), sType)
            if useOvr then self:FillOvrBars(isSplitView, sp, mode) end
        end
    else
        if isSplitView then
            local priD = ns.Analysis and ns.Analysis:GetSorted(seg, sp.primaryMode) or {}
            local secD = ns.Analysis and ns.Analysis:GetSorted(seg, sp.secondaryMode) or {}
            self:RefreshHead(self.priHead, sp.primaryMode, seg, dur); self:RefreshHead(self.secHead, sp.secondaryMode, seg, dur)
            self:FillBars(self.priBars, self.priList, priD, dur, sp.primaryMode); self:FillBars(self.secBars, self.secList, secD, dur, sp.secondaryMode)
            if useOvr then
                local ovrSeg = ns.Segments and ns.Segments:GetOverallSegment(); local ovrDur = ovrSeg and ovrSeg.duration or 0
                self:FillBars(self.ovrPriBars, self.ovrPriList, ns.Analysis and ns.Analysis:GetSorted(ovrSeg, sp.primaryMode) or {}, ovrDur, sp.primaryMode)
                self:FillBars(self.ovrSecBars, self.ovrSecList, ns.Analysis and ns.Analysis:GetSorted(ovrSeg, sp.secondaryMode) or {}, ovrDur, sp.secondaryMode)
            end
        else
            self:RefreshHead(self.priHead, mode, seg, dur)
            if isDeathMode then self:FillDeathBars(seg) else self:FillBars(self.priBars, self.priList, ns.Analysis and ns.Analysis:GetSorted(seg, mode) or {}, dur, mode) end
            if useOvr then
                local ovrSeg = ns.Segments and ns.Segments:GetOverallSegment()
                if isDeathMode then self:FillDeathBars(ovrSeg, self.ovrPriBars, self.ovrPriList)
                else self:FillBars(self.ovrPriBars, self.ovrPriList, ns.Analysis and ns.Analysis:GetSorted(ovrSeg, mode) or {}, (ovrSeg and ovrSeg.duration or 0), mode) end
            end
        end
    end

    -- 刷新总计栏标题（友方/敌方切换时同步）
    if useOvr and self.ovrContainer and self.ovrContainer:IsShown() then
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
end

function UI:FillOvrBars(isSplitView, sp, mode)
    local function effMode(m)
        if m == "damageTaken" and ns.state.damageTakenView == "enemy" then return "enemyDamageTaken" end
        return m
    end
    if ns.state.inCombat then
        local ovr = ns.Segments and ns.Segments.overall; local hasPriorData = ovr and (ovr.totalDamage > 0 or ovr.totalHealing > 0)
        local sType = hasPriorData and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
        if isSplitView then self:FillBarsFromAPI(self.ovrPriBars, self.ovrPriList, effMode(sp.primaryMode), sType); self:FillBarsFromAPI(self.ovrSecBars, self.ovrSecList, effMode(sp.secondaryMode), sType)
        else self:FillBarsFromAPI(self.ovrPriBars, self.ovrPriList, effMode(mode), sType) end
    else
        local ovrSeg = ns.Segments and ns.Segments:GetOverallSegment(); local ovrDur = ns.Analysis and ns.Analysis:GetSegmentDuration(ovrSeg) or 0
        if isSplitView then
            self:FillBars(self.ovrPriBars, self.ovrPriList, ns.Analysis and ns.Analysis:GetSorted(ovrSeg, sp.primaryMode) or {}, ovrDur, sp.primaryMode)
            self:FillBars(self.ovrSecBars, self.ovrSecList, ns.Analysis and ns.Analysis:GetSorted(ovrSeg, sp.secondaryMode) or {}, ovrDur, sp.secondaryMode)
        else self:FillBars(self.ovrPriBars, self.ovrPriList, ns.Analysis and ns.Analysis:GetSorted(ovrSeg, mode) or {}, ovrDur, mode) end
    end
end

function UI:RefreshTitle()
    if not self.frame or not self.frame:IsShown() then return end; if not self.titleText then return end
    local segL = ns.Segments and ns.Segments:GetViewLabel() or L["无数据"]
    local dot = ns.state.inCombat and L["|cff00ff00[战]|r "] or ""
    local dur = 0
    if ns.state.inCombat and ns.state.combatStartTime and ns.state.combatStartTime > 0 then
        local isViewingOverall = ns.Segments and ns.Segments.viewIndex == 0
        if isViewingOverall then dur = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall) or 0
        else dur = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Current) or 0 end
    else
        local seg = ns.Segments and ns.Segments:GetViewSegment()
        if seg and seg._keystoneTime and seg._keystoneTime > 0 then dur = seg._keystoneTime else dur = seg and (seg.duration or 0) or 0 end
    end
    local tStr = dur > 0 and ("|cffaaaaaa" .. ns:FormatTime(dur) .. "|r") or ""
    if self.titleTime then self.titleTime:SetText(tStr) end
    if ns.MythicPlus and ns.MythicPlus:IsActive() and ns.state.inMythicPlus then
        local info = ns.MythicPlus:GetHeaderInfo()
        if info then
            local levelStr = (info.level and info.level > 0) and string.format("|cff4cb8e8+%d|r ", info.level) or ""
            local nameStr = info.name and ("|cff4cb8e8" .. info.name .. "|r") or ""
            self.titleText:SetText(dot .. segL .. " " .. levelStr .. nameStr); return
        end
    end
    self.titleText:SetText(dot .. segL)
end

function UI:RefreshHead(h, mode, seg, dur, apiSessionType)
    if not h:IsShown() then return end
    local mn = L[ns.MODE_NAMES[mode] or mode]

    -- 承伤模式下显示友方/敌方双按钮
    if h.dtFriendly then
        if mode == "damageTaken" then
            local isEnemy = (ns.state.damageTakenView == "enemy")
            h.dtFriendlyText:SetText(L["友方"])
            h.dtEnemyText:SetText(L["敌方"])
            if isEnemy then
                h.dtFriendlyText:SetTextColor(0.3, 0.5, 0.3)
                h.dtEnemyText:SetTextColor(1.0, 0.4, 0.4)
                mn = L["敌人承伤"]
            else
                h.dtFriendlyText:SetTextColor(0.3, 1.0, 0.3)
                h.dtEnemyText:SetTextColor(0.5, 0.3, 0.3)
            end
            h.dtFriendly:Show(); h.dtEnemy:Show()
        else
            h.dtFriendly:Hide(); h.dtEnemy:Hide()
        end
    end
    local ac = mode=="damage" and T.dmgC or mode=="healing" and T.healC or mode=="damageTaken" and T.takenC or T.accent
    h.label:SetText(string.format("|cff%02x%02x%02x%s|r", ac[1]*255, ac[2]*255, ac[3]*255, mn))

    -- 承伤模式：固定按钮位置，防止跳动
    if mode == "damageTaken" and h.dtFriendly then
        if not h._dtMaxLabelW then
            -- 首次计算：测量两种文字的最大宽度并缓存
            local savedText = h.label:GetText()
            h.label:SetWidth(0)
            local fmt = "|cff%02x%02x%02x%s|r"
            h.label:SetText(string.format(fmt, ac[1]*255, ac[2]*255, ac[3]*255, L[ns.MODE_NAMES["damageTaken"]]))
            local w1 = h.label:GetStringWidth()
            h.label:SetText(string.format(fmt, ac[1]*255, ac[2]*255, ac[3]*255, L["敌人承伤"]))
            local w2 = h.label:GetStringWidth()
            h._dtMaxLabelW = math.max(w1, w2) + 2
            h.label:SetText(savedText)
        end
        -- 按钮锚定到 header LEFT + 固定偏移，不跟随 label 宽度
        h.dtFriendly:ClearAllPoints()
        h.dtFriendly:SetPoint("LEFT", h, "LEFT", 6 + h._dtMaxLabelW + 4, 0)
        h.dtEnemy:ClearAllPoints()
        h.dtEnemy:SetPoint("LEFT", h.dtFriendly, "RIGHT", 2, 0)
    end
    if seg then
        local total = 0
        if mode == "damageTaken" and ns.state.damageTakenView == "enemy" then
            for _, entry in ipairs(seg.enemyDamageTakenList or {}) do total = total + entry.total end
        elseif COUNT_MODES[mode] then
            for _, p in pairs(seg.players) do total = total + (p[mode] or 0) end
        else
            total = mode=="damage" and seg.totalDamage or mode=="healing" and seg.totalHealing or mode=="damageTaken" and seg.totalDamageTaken or 0
        end
        local valStr = COUNT_MODES[mode] and (ns:FormatNumber(total)..L["次"]) or ns:FormatNumber(total)
        h.info:SetText(string.format(L["团队总%s: %s"], mn, valStr))
    elseif apiSessionType then
        local effM = mode
        if mode == "damageTaken" and ns.state.damageTakenView == "enemy" then effM = "enemyDamageTaken" end
        local dmType = MODE_TO_DM[effM]
        if dmType then
            local session = self:GetCachedSession(apiSessionType, dmType)
            if session and session.totalAmount then
                if COUNT_MODES[mode] then h.info:SetFormattedText(L["团队总%s: %s次"], mn, AbbreviateNumbers(session.totalAmount))
                else h.info:SetFormattedText(L["团队总%s: %s"], mn, AbbreviateNumbers(session.totalAmount)) end
            else h.info:SetText("") end
        else h.info:SetText("") end
    else h.info:SetText("") end
end

-- ============================================================
-- Tooltip
-- ============================================================
function UI:AnchorTooltipToWindow(bar)
    local f = self.frame; if not f then GameTooltip:SetOwner(bar.frame, "ANCHOR_LEFT"); return end
    GameTooltip:SetOwner(bar.frame, "ANCHOR_NONE"); GameTooltip:ClearAllPoints()
    local scale = f:GetEffectiveScale(); local fLeft = (f:GetLeft() or 0) * scale; local fTop = (f:GetTop() or 0) * scale
    local screenH = GetScreenHeight() * UIParent:GetEffectiveScale()
    if fLeft > 280 then GameTooltip:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, 0)
    elseif fTop < screenH * 0.7 then GameTooltip:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
    else GameTooltip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4) end
end

function UI:ShowTooltip(bar, section)
    local d = bar._data; if not d then return end; self:AnchorTooltipToWindow(bar)
    local guid = bar._guid; local seg = ns.Segments and ns.Segments:GetViewSegment()
    local specID, ilvl, score
    if d and d.isAPI then specID = d.specID; ilvl = d.ilvl or 0; score = d.score or 0
    elseif seg and seg.isActive then
        local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
        specID = (d and d.specID) or cache.specID; ilvl = (d and d.ilvl) or cache.ilvl or 0; score = (d and d.score) or cache.score or 0
        if guid == ns.state.playerGUID then local specIdx = GetSpecialization(); if specIdx then specID = GetSpecializationInfo(specIdx) end end
        if d then d.specID = specID; d.ilvl = ilvl; d.score = score end
    else specID = d and d.specID; ilvl = d and d.ilvl or 0; score = d and d.score or 0 end

    local specName = ""; if specID then local _, name = GetSpecializationInfoByID(specID); if name then specName = name end end

    local function AddPlayerInfoLines()
        if specName ~= "" or (ilvl and ilvl > 0) or (score and score > 0) then
            GameTooltip:AddLine(" ")
            if specName ~= "" then GameTooltip:AddDoubleLine(L["专精"], specName, 0.7,0.7,0.7, 1,1,1) end
            if ilvl and ilvl > 0 then GameTooltip:AddDoubleLine(L["平均装等"], tostring(ilvl), 0.7,0.7,0.7, 1,0.85,0) end
            if score and score > 0 then
                local color = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
                if color then GameTooltip:AddDoubleLine(L["大秘境评分"], color:WrapTextInColorCode(tostring(score)), 0.7,0.7,0.7, 1,1,1)
                else GameTooltip:AddDoubleLine(L["大秘境评分"], tostring(score), 0.7,0.7,0.7, 1,0.5,0) end
            end
        end
    end

    if bar._isDeath then
        GameTooltip:AddLine(ns:GetClassHex(d.playerClass)..ns:DisplayName(d.playerName)..L["|r [死亡]"]); AddPlayerInfoLines()
        GameTooltip:AddLine(" "); GameTooltip:AddDoubleLine(L["致命技能"], d.killingAbility or "?", 0.7,0.7,0.7, 1,0.3,0.3)
        GameTooltip:AddDoubleLine(L["击杀者"], ns:DisplayName(d.killerName) or "?", 0.7,0.7,0.7, 1,1,1)
        GameTooltip:AddDoubleLine(L["死前受伤"], ns:FormatNumber(d.totalDamageTaken or 0), 0.7,0.7,0.7, 1,0.5,0.5)
        GameTooltip:AddDoubleLine(L["死前受治"], ns:FormatNumber(d.totalHealingReceived or 0), 0.7,0.7,0.7, 0.5,1,0.5)
        GameTooltip:AddLine(" "); GameTooltip:AddLine(L["|cff00ccff点击查看完整死亡日志|r"], 0.4,0.4,0.4); GameTooltip:Show(); return
    end

    if d.isAPI then
        GameTooltip:AddLine(ns:GetClassHex(bar._classStr)..ns:DisplayName(bar._nameStr or "?").."|r"); AddPlayerInfoLines()
        GameTooltip:AddLine(" "); GameTooltip:AddLine(L["|cffaaaaaa— 战斗中 (实时) —|r"])
        if COUNT_MODES[bar._mode] then GameTooltip:AddDoubleLine((L[ns.MODE_NAMES[bar._mode] or bar._mode])..L["次"], AbbreviateNumbers(d.totalAmount), 0.7,0.7,0.7, 1,1,1)
        elseif ns.db.display.showPerSecond then
            GameTooltip:AddDoubleLine(ns.MODE_NAMES[bar._mode] or bar._mode, AbbreviateNumbers(d.totalAmount), 0.7,0.7,0.7, 1,1,1)
            GameTooltip:AddDoubleLine(L["每秒"], AbbreviateNumbers(d.amountPerSecond), 0.7,0.7,0.7, 1,0.85,0)
        else GameTooltip:AddDoubleLine(ns.MODE_NAMES[bar._mode] or bar._mode, AbbreviateNumbers(d.totalAmount), 0.7,0.7,0.7, 1,1,1) end
        GameTooltip:AddLine(" "); GameTooltip:AddLine(L["|cff00ccff左键: 技能细分  右键: 切换模式|r"], 0.4,0.4,0.4); GameTooltip:Show(); return
    end

    local mode = bar._mode or ns.db.display.mode; local dur2 = ns.Analysis and ns.Analysis:GetSegmentDuration(seg) or 0
    local mn = L[ns.MODE_NAMES[mode] or mode]
    GameTooltip:AddLine(ns:GetClassHex(d.class)..ns:DisplayName(d.name or "?").."|r"); AddPlayerInfoLines()
    GameTooltip:AddLine(" "); GameTooltip:AddLine(L["|cffaaaaaa— 本段 —|r"])
    GameTooltip:AddDoubleLine(mn, ns:FormatNumber(d.value), 0.7,0.7,0.7, 1,1,1)
    if dur2 > 0 and ns.MODE_UNITS[mode] then GameTooltip:AddDoubleLine(ns.MODE_UNITS[mode], string.format("%.1f", d.value/dur2), 0.7,0.7,0.7, 1,0.85,0) end
    GameTooltip:AddDoubleLine(L["占比"], string.format("%.1f%%", d.percent or 0), 0.7,0.7,0.7, 1,1,1)
    if d.petDamage and d.petDamage > 0 and mode == "damage" then GameTooltip:AddDoubleLine(L["含宠物"], ns:FormatNumber(d.petDamage), 0.5,0.5,0.5, 0.7,0.7,0.7) end

    if ns.db.split.enabled and seg then
        local other = (section=="primary") and ns.db.split.secondaryMode or ns.db.split.primaryMode
        if other ~= mode and seg.players[d.guid] then
            local ov = ns.Analysis and ns.Analysis:GetPlayerValue(seg.players[d.guid], other, seg)
            if ov and ov > 0 then GameTooltip:AddLine(" "); local on2 = L[ns.MODE_NAMES[other] or other]
                GameTooltip:AddDoubleLine(on2, ns:FormatNumber(ov), 0.7,0.7,0.7, 1,1,1)
                if dur2 > 0 then GameTooltip:AddDoubleLine(ns.MODE_UNITS[other] or "", string.format("%.1f",ov/dur2), 0.7,0.7,0.7, 1,0.85,0) end
            end
        end
    end

    if self:IsOverallColumnActive() then
        local ovd = ns.Analysis and ns.Analysis:GetOverallPlayerData(d.guid, mode)
        if ovd then
            local ac2 = T.accent or {0.0, 0.65, 1.0}; GameTooltip:AddLine(" ")
            local ovrTitleWord = L["总计"]; if ns.Segments and ns.Segments.overall and ns.Segments.overall._isMerged then ovrTitleWord = L["全程"] end
            GameTooltip:AddLine(string.format(L["|cff%02x%02x%02x— %s —|r"], ac2[1]*255, ac2[2]*255, ac2[3]*255, ovrTitleWord))
            GameTooltip:AddDoubleLine(string.format(L["%s%s"], ovrTitleWord, mn), ns:FormatNumber(ovd.value), 0.7,0.7,0.7, 1,1,1)
            if ovd.dur > 0 and ns.MODE_UNITS[mode] then GameTooltip:AddDoubleLine(string.format(L["%s%s"], ovrTitleWord, ns.MODE_UNITS[mode]), string.format("%.1f",ovd.perSec), 0.7,0.7,0.7, 1,0.85,0) end
            GameTooltip:AddDoubleLine(string.format(L["%s占比"], ovrTitleWord), string.format("%.1f%%", ovd.percent), 0.7,0.7,0.7, ac2[1],ac2[2],ac2[3])
        end
    end

    GameTooltip:AddLine(" ")
    if d.deaths and d.deaths > 0 then GameTooltip:AddDoubleLine(L["死亡"], d.deaths, 0.7,0.7,0.7, 1,0.3,0.3) end
    if d.interrupts and d.interrupts > 0 then GameTooltip:AddDoubleLine(L["打断"], d.interrupts, 0.7,0.7,0.7, 0.3,1,0.3) end
    if d.dispels and d.dispels > 0 then GameTooltip:AddDoubleLine(L["驱散"], d.dispels, 0.7,0.7,0.7, 0.3,0.8,1) end
    GameTooltip:AddLine(" "); GameTooltip:AddLine(L["|cff00ccff左键: 技能细分  右键: 切换模式|r"], 0.4,0.4,0.4); GameTooltip:Show()
end
