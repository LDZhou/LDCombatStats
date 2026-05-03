--[[
    Light Damage - CombatTracker.lua
    战斗追踪核心：事件注册、状态同步、归档处理
    
    LoadSegmentData / RebuildOverall → DataLoader.lua
    SmartTrimHistory / MergeAndCleanInstance → InstanceManager.lua
]]

local addonName, ns = ...
local L = ns.L

local CT = {}
ns.CombatTracker = CT

CT._internalReset = false
CT._updateCount          = 0
CT._baselineSessionCount = 0
CT._lastProcessedCount   = 0
CT._currentEncounterID   = nil
CT._currentInstanceTag   = nil
CT._wasInInstance        = false
CT._exitingInstanceTag   = nil
CT._currentMythicLevel   = 0
CT._currentMythicMapName = nil
CT._currentInstanceName  = nil
CT._initialBaselineSet   = false

local function getAmount(val)
    if issecretvalue and issecretvalue(val) then return 0 end
    if type(val) == "number" then return val end
    return 0
end

local function isSessionStillSecret(sessionId)
    if not issecretvalue then return false end
    local typesToCheck = {
        Enum.DamageMeterType.DamageDone,
        Enum.DamageMeterType.HealingDone,
        Enum.DamageMeterType.DamageTaken
    }
    for _, dmType in ipairs(typesToCheck) do
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionId, dmType)
        if ok and session and session.combatSources then
            for _, src in ipairs(session.combatSources) do
                if issecretvalue(src.totalAmount) then return true end
            end
        end
    end
    return false
end

local function buildDeathRecordFromRecapID(recapID, playerGUID, playerName, playerClass)
    if not recapID or recapID <= 0 then return nil end
    if not C_DeathRecap then return nil end
    local ok, recapRaw = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if not ok or not recapRaw or #recapRaw == 0 then return nil end
    local maxHP = 1
    if C_DeathRecap.GetRecapMaxHealth then
        local ok2, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
        if ok2 and hp and hp > 0 then maxHP = hp end
    end
    local reversed = {}
    for i = #recapRaw, 1, -1 do table.insert(reversed, recapRaw[i]) end
    local events, totalDmg, totalHeal, killingAbi, killerName = {}, 0, 0, "?", ""
    for _, ev in ipairs(reversed) do
        local spellID   = getAmount(ev.spellId)
        local spellName = ev.spellName or ""
        local evType    = ev.event or ""
        local isHeal    = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")
        local amount    = getAmount(ev.amount)
        local overkill  = getAmount(ev.overkill)
        if spellName == "" then
            if isHeal then spellName = L["治疗"]
            elseif evType == "SWING_DAMAGE" then spellName = L["近战"]
            else spellName = L["未知"] end
        end
        local srcName = ev.sourceName or ""
        local hp      = getAmount(ev.currentHP)
        local hpPct   = maxHP > 0 and (hp / maxHP * 100) or 0
        if isHeal then totalHeal = totalHeal + amount else totalDmg = totalDmg + amount end
        table.insert(events, {
            time = ev.timestamp or GetTime(), spellID = spellID, spellName = spellName,
            amount = isHeal and -math.abs(amount) or math.abs(amount), isHeal = isHeal,
            srcName = srcName, hp = hp, maxHP = maxHP, hpPercent = hpPct, overkill = overkill,
        })
    end
    for i = #events, 1, -1 do
        if not events[i].isHeal then
            killingAbi = events[i].spellName or "?"
            killerName = events[i].srcName   or ""
            break
        end
    end
    local timeSpan = #events >= 2 and (events[#events].time - events[1].time) or 0
    local deathTimestamp = time()
    if #events > 0 and events[#events].time then
        deathTimestamp = math.floor(events[#events].time)
    end
    return {
        timestamp = deathTimestamp, gameTime = GetTime(),
        playerName = ns:ShortName(playerName) or "?", playerGUID = playerGUID,
        playerClass = playerClass, isSelf = (playerGUID == ns.state.playerGUID),
        killingAbility = killingAbi, killerName = killerName, events = events,
        lastHP = 0, maxHP = maxHP, totalDamageTaken = totalDmg,
        totalHealingReceived = totalHeal, timeSpan = timeSpan, _fromRecap = true,
        _recapID = recapID,
    }
end

-- ============================================================
-- 脱战后: 解析归档 session → history
-- 通过对比 sessionID set,有就跳过,没有就插入。
-- 任何理由(secret 没解、事件没触发、异常被吞)漏掉的段,下次扫到都会补。
-- ============================================================
local function processArchivedSessions()
    local segs = ns.Segments
    if not segs then return end
    local sessions     = C_DamageMeter.GetAvailableCombatSessions()
    local sessionCount = sessions and #sessions or 0
    if sessionCount == 0 then return end

    -- 单调推进:从上次水位线之后的 session 开始扫,不需要去重表也不需要黑名单
    local addedAny = false
    for i = (CT._lastProcessedCount or 0) + 1, sessionCount do
        local s = sessions[i]
        if not s then break end
        local sid = s.sessionID
        local dur = s.durationSeconds or 0

        if dur <= 0 then
            -- 0 时长 session(尚未稳定),跳过,下次扫描再处理
        elseif dur < (ns.db and ns.db.tracking and ns.db.tracking.minCombatTime or 2) then
            -- 时长不足,跳过
        else
            -- API 有但 history 没有 → 新增
            local isBoss = false
            if s.name and (s.name:sub(1, 3) == "(!)" or string.find(s.name, "(!)", 1, true)) then
                isBoss = true
            end
            if CT._bossSessionIndices and CT._bossSessionIndices[i] then
                isBoss = true
            end

            local instanceTag = (ns.state.isInInstance and CT._currentInstanceTag)
                                or CT._exitingInstanceTag or nil

            local seg = segs:NewSegment("history", s.name or GetZoneText() or "Combat")
            seg.isActive = false
            seg.duration = dur
            seg.endTime = GetTime()
            seg.startTime = GetTime() - dur
            seg._isBoss = isBoss
            seg._instanceTag = instanceTag
            seg._instanceDisplayName = CT._currentInstanceName or nil
            seg._sessionIdx = i
            seg._sessionID = sid
            seg._dataLoaded = false  -- 懒加载

            -- 死亡日志(新增段才构建,避免覆盖用户已查看的)
            local ok2, deathSession = pcall(C_DamageMeter.GetCombatSessionFromID,
                sid, Enum.DamageMeterType.Deaths)
            if ok2 and deathSession and deathSession.combatSources then
                for _, src in ipairs(deathSession.combatSources) do
                    local guid    = src.sourceGUID
                    local deaths  = getAmount(src.totalAmount)
                    local recapID = getAmount(src.deathRecapID)
                    if guid and (deaths > 0 or recapID > 0) and recapID > 0 then
                        local class = src.classFilename
                        if not class then
                            if ns:IsNPCGUID(guid) then
                                class = "NPC"
                            else
                                local ok, _, ce = pcall(GetPlayerInfoByGUID, guid)
                                class = (ok and ce) or "WARRIOR"
                            end
                        end
                        local deathRecord = buildDeathRecordFromRecapID(recapID, guid, src.name, class)
                        if deathRecord then
                            local insertIdx = deathRecord.isSelf and 1 or (#seg.deathLog + 1)
                            if not deathRecord.isSelf then
                                for di, dr in ipairs(seg.deathLog) do
                                    if not dr.isSelf then insertIdx = di; break end
                                end
                            end
                            table.insert(seg.deathLog, insertIdx, deathRecord)
                            while #seg.deathLog > 50 do table.remove(seg.deathLog) end

                            -- 同步到 Overall
                            local ovr = segs.overall
                            if ovr then
                                ovr.deathLog = ovr.deathLog or {}
                                local ovrReplaced = false
                                for di, existing in ipairs(ovr.deathLog) do
                                    if existing.playerGUID == guid then
                                        if existing._recapID and deathRecord._recapID
                                           and existing._recapID == deathRecord._recapID then
                                            ovrReplaced = true
                                        elseif not existing._fromRecap then
                                            ovr.deathLog[di] = deathRecord
                                            ovrReplaced = true
                                        elseif not existing._recapID then
                                            ovr.deathLog[di] = deathRecord
                                            ovrReplaced = true
                                        end
                                        if ovrReplaced then break end
                                    end
                                end
                                if not ovrReplaced then
                                    local ovrInsertIdx = deathRecord.isSelf and 1 or (#ovr.deathLog + 1)
                                    if not deathRecord.isSelf then
                                        for di, dr in ipairs(ovr.deathLog) do
                                            if not dr.isSelf then ovrInsertIdx = di; break end
                                        end
                                    end
                                    table.insert(ovr.deathLog, ovrInsertIdx, deathRecord)
                                end
                                while #ovr.deathLog > 50 do table.remove(ovr.deathLog) end
                            end
                        end
                    end
                end
            end

            table.insert(segs.history, 1, seg)
            addedAny = true

            -- 0 数据段:启动 10 秒兜底扫描
            if not seg._dataLoaded then
                local segRef = seg
                C_Timer.After(10, function()
                    if not segRef._dataLoaded
                       and segRef._sessionID
                       and (segRef.totalDamage or 0) == 0 then
                        CT:LoadSegmentData(segRef)
                        if ns.Analysis then ns.Analysis:InvalidateCache() end
                        if ns.UI and ns.UI:IsVisible() then ns.UI:Refresh() end
                    end
                end)
            end
        end
    end

    -- 收尾
    if addedAny then
        if ns.SaveSessionHistory then ns:SaveSessionHistory() end
    end
    CT._lastProcessedCount = sessionCount

    ns.state.lastCombatWasBoss = false
    CT._bossSessionIndices = CT._bossSessionIndices or {}
    CT:RebuildOverall(sessions, sessionCount)
end

-- ============================================================
-- 等 secret 释放后再解析
-- ============================================================
local waitTicker, waitAttempts = nil, 0

local function waitAndProcessArchived(fastPath)
    if waitTicker then return end

    -- fastPath 节流:300ms 内最多 1 次,防止事件风暴
    if fastPath then
        local now = GetTime()
        if CT._lastFastPathTime and (now - CT._lastFastPathTime) < 0.3 then return end
        CT._lastFastPathTime = now
    end

    waitAttempts = 0

    local function anyUnprocessedStillSecret()
        local sessions = C_DamageMeter.GetAvailableCombatSessions()
        local count    = sessions and #sessions or 0
        for i = (CT._lastProcessedCount or 0) + 1, count do
            local s = sessions[i]
            if s then
                if isSessionStillSecret(s.sessionID) then return true end
                if (s.durationSeconds or 0) == 0 then return true end
            end
        end
        return false
    end

    local function doAfterProcess()
        -- 即使 processArchivedSessions 内部崩,也要保证后续清理逻辑跑
        pcall(processArchivedSessions)
        if CT._pendingMergeArgs then
            local args = CT._pendingMergeArgs
            CT._pendingMergeArgs = nil
            pcall(CT.MergeAndCleanInstance, CT, args.tag, args.lvl, args.mapName, args.instName)
        end
        if ns.Segments then ns.Segments._locked = false end
        if ns.UI then C_Timer.After(0, function() ns.UI:Layout() end) end

        -- 1 秒后再扫一次
        C_Timer.After(1, function()
            if ns.state.inCombat then return end
            pcall(processArchivedSessions)
            if ns.Analysis then ns.Analysis:InvalidateCache() end
            if ns.UI and ns.UI:IsVisible() then ns.UI:Layout() end
        end)
    end

    -- 立即可处理:直接执行
    if not anyUnprocessedStillSecret() then
        doAfterProcess()
        return
    end

    -- 有 secret 在解密,等待
    waitTicker = C_Timer.NewTicker(0.3, function()
        waitAttempts = waitAttempts + 1
        if InCombatLockdown() then return end
        if waitAttempts >= 10 then
            -- 超时也归档,反正下次会再扫(幂等保证)
            if waitTicker then waitTicker:Cancel(); waitTicker = nil end
            doAfterProcess()
            return
        end
        if anyUnprocessedStillSecret() then return end
        if waitTicker then waitTicker:Cancel(); waitTicker = nil end
        doAfterProcess()
    end)
end

-- ============================================================
-- 状态同步
-- ============================================================
local function isGroupInCombat()
    if UnitAffectingCombat("player") then return true end
    if not ns.state.isInInstance then return false end
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() do if UnitAffectingCombat(prefix .. i) then return true end end
    return false
end

local function syncCombatState()
    CT._updateCount = CT._updateCount + 1
    local sessions     = C_DamageMeter.GetAvailableCombatSessions()
    local sessionCount = sessions and #sessions or 0
    local hasLive      = isGroupInCombat()
    if hasLive then
        if not ns.state.inCombat then
            if not ns.state.combatStartTime or ns.state.combatStartTime == 0 then
                local liveDur = sessionCount > 0 and (sessions[sessionCount].durationSeconds or 0) or 0
                ns.state.combatStartTime = GetTime() - liveDur
            end
            ns:EnterCombat()
        end
        if ns.UI and ns.UI._collapsed then ns.UI:CheckAutoCollapse() end
        if ns.Segments and ns.Segments.current and sessionCount > 0 then
            local apiName = sessions[sessionCount].name
            if apiName and apiName ~= "" then ns.Segments.current.name = apiName end
        end
    else
        if ns.state.inCombat then
            if CT._currentEncounterID then return end
            ns:LeaveCombat()
            C_Timer.After(0.3, waitAndProcessArchived)
        end
    end
end

-- ============================================================
-- 公开接口
-- ============================================================
function CT:ClearLoadedSessionIDs()
    local segs = ns.Segments
    if not segs or not segs.history then return end
    for _, seg in ipairs(segs.history) do
        if seg._dataLoaded and seg._sessionID then
            seg._sessionID = nil
        end
    end
end
function CT:ResetMeterForNewRun()
    self:ClearLoadedSessionIDs()
    if C_DamageMeter.ResetAllCombatSessions then CT._internalReset = true; C_DamageMeter.ResetAllCombatSessions() end
    CT._baselineSessionCount = 0; CT._lastProcessedCount = 0; CT._initialBaselineSet = true; CT._bossSessionIndices = {}
    if ns.MythicPlus then ns.MythicPlus:ResetBaseline() end
end
function CT:MarkReset()
    self:ClearLoadedSessionIDs()
    if C_DamageMeter.ResetAllCombatSessions then C_DamageMeter.ResetAllCombatSessions() end
    CT._baselineSessionCount = 0; CT._lastProcessedCount = 0; CT._initialBaselineSet = true
end
function CT:SetBaseline()
    local sessions = C_DamageMeter.GetAvailableCombatSessions()
    CT._baselineSessionCount = sessions and #sessions or 0; CT._lastProcessedCount = CT._baselineSessionCount; CT._initialBaselineSet = true
end
function CT:ResetBaselineToCurrentCount()
    local sessions = C_DamageMeter.GetAvailableCombatSessions(); local count = sessions and #sessions or 0
    CT._baselineSessionCount = count; CT._lastProcessedCount = count; CT._initialBaselineSet = true; CT._bossSessionIndices = {}
end
function CT:PullCurrentData()
    if ns.Config and ns.Config._pvRefreshBlocked then return end
    syncCombatState()
    if ns.UI and ns.UI:IsVisible() then ns.UI:Refresh() end
end

-- ============================================================
-- 事件注册
-- ============================================================
function CT:RegisterEvents()
    if CT._eventsRegistered then return end
    CT._eventsRegistered = true

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED"); f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("ENCOUNTER_START"); f:RegisterEvent("ENCOUNTER_END")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("CHALLENGE_MODE_START"); f:RegisterEvent("CHALLENGE_MODE_COMPLETED"); f:RegisterEvent("CHALLENGE_MODE_RESET")
    f:RegisterEvent("PLAYER_LEAVING_WORLD")
    f:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")

    f:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_LEAVING_WORLD" then
            if ns.state.isInInstance then
                local officialDur = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall)
                if officialDur and officialDur > 0 then CT._overallDurationSnapshot = officialDur end
            end
            return
        end
        if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
            if ns.state.inCombat or isGroupInCombat() then return end
            C_Timer.After(0, function() waitAndProcessArchived(true) end)
            CT:RescanZeroDataSegments()
            return
        end
        if event == "ENCOUNTER_START" then
            CT._currentEncounterID = ...; local ss = C_DamageMeter.GetAvailableCombatSessions(); CT._encounterStartSessionCount = ss and #ss or 0
        elseif event == "ENCOUNTER_END" then
            CT._currentEncounterID = nil
            local ss = C_DamageMeter.GetAvailableCombatSessions(); local now = ss and #ss or 0
            CT._bossSessionIndices = CT._bossSessionIndices or {}
            for i = (CT._encounterStartSessionCount or now) + 1, now do CT._bossSessionIndices[i] = true end
            local segs = ns.Segments
            if segs and segs.history then
                for _, seg in ipairs(segs.history) do
                    if seg._sessionIdx and CT._bossSessionIndices[seg._sessionIdx] then seg._isBoss = true end
                end
            end
        elseif event == "CHALLENGE_MODE_START" then
            local level, mapName = 0, nil
            if C_ChallengeMode then
                if C_ChallengeMode.GetActiveKeystoneInfo then level = C_ChallengeMode.GetActiveKeystoneInfo() or 0 end
                if C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetMapUIInfo then
                    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
                    if mapID then mapName = C_ChallengeMode.GetMapUIInfo(mapID) end
                end
            end
            CT._currentMythicLevel = level or 0; CT._currentMythicMapName = mapName
        elseif event == "PLAYER_ENTERING_WORLD" then
            CT:SmartTrimHistory()
            ns:UpdateInstanceStatus()
            local inInstance = ns.state.isInInstance
            local rawName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
            local newBaseTag = string.format("%s|%d", rawName or "Unknown", instanceID or 0)
            local isExitingInstance = false
            if CT._wasInInstance then
                if not inInstance then isExitingInstance = true
                elseif CT._currentInstanceTag and not CT._currentInstanceTag:find(newBaseTag, 1, true) then isExitingInstance = true end
            end
            if isExitingInstance then
                local tag, lvl, mapName, instName = CT._currentInstanceTag, CT._currentMythicLevel, CT._currentMythicMapName, CT._currentInstanceName
                if tag then
                    CT._exitingInstanceTag = tag
                    CT._pendingMergeArgs = { tag = tag, lvl = lvl, mapName = mapName, instName = instName }
                    if ns.state.inCombat then ns:LeaveCombat() end
                    C_Timer.After(0, waitAndProcessArchived)
                    C_Timer.After(8, function() if CT._pendingMergeArgs then waitAndProcessArchived() end end)
                end
                CT._currentInstanceTag = nil; CT._currentInstanceName = nil; CT._currentMythicLevel = 0; CT._currentMythicMapName = nil
                if ns.MythicPlus then ns.MythicPlus._completedAndStillInside = false end
                if ns.db then ns.db.currentInstanceTag = nil end
            end
            if inInstance then
                CT._currentInstanceType = select(2, GetInstanceInfo())
                local rawName2 = GetInstanceInfo()
                local _, _, _, _, _, _, _, instanceID2 = GetInstanceInfo()
                local baseTag = string.format("%s|%d", rawName2 or "Unknown", instanceID2 or 0)
                local existingTag = ns.db.currentInstanceTag
                local isSameInstance = false
                if existingTag and existingTag:find(baseTag, 1, true) then CT._currentInstanceTag = existingTag; isSameInstance = true
                else CT._currentInstanceTag = string.format("%s|%d|%d", rawName2 or "Unknown", instanceID2 or 0, time()); ns.db.currentInstanceTag = CT._currentInstanceTag end
                if isSameInstance then
                    C_Timer.After(1.5, function()
                        if ns.Segments then
                            if ns.Segments.history then for _, s in ipairs(ns.Segments.history) do if s._sessionID and not s._dataLoaded then CT:LoadSegmentData(s) end end end
                            ns.Segments._preReloadOverallData = nil
                            local sess = C_DamageMeter.GetAvailableCombatSessions(); CT:RebuildOverall(sess, sess and #sess or 0)
                            if ns.UI and ns.UI:IsVisible() then ns.UI:Layout() end
                        end
                    end)
                end
                CT._currentMythicLevel = 0; CT._currentMythicMapName = nil
                local function tryGetInstanceName() local name = GetRealZoneText(); if not name or name == "" or name == GetZoneText() then name = rawName end; return name end
                CT._currentInstanceName = tryGetInstanceName()
                C_Timer.After(1, function() if ns.state.isInInstance then CT._currentInstanceName = tryGetInstanceName() end end)
                if (not CT._wasInInstance or isExitingInstance) and not isSameInstance then
                    C_Timer.After(4, function()
                        if ns.state.isInInstance and not ns.state.inCombat then
                            if ns.Segments then
                                ns.Segments._preReloadOverallData = nil
                                if ns.Segments.history then for _, s in ipairs(ns.Segments.history) do if s._sessionID and not s._dataLoaded and (s._isBoss or s._isMerged) then CT:LoadSegmentData(s) end end end
                            end
                            CT:ResetMeterForNewRun()
                            if ns.Segments then
                                local displayName = CT._currentInstanceName or rawName or L["副本"]
                                ns.Segments.overall = ns.Segments:NewSegment("overall", string.format(L["%s [全程]"], displayName))
                            end
                        end
                    end)
                end
            end
            CT._wasInInstance = inInstance; CT._bossSessionIndices = CT._bossSessionIndices or {}
            C_Timer.After(0.5, function()
                if not ns.state.inCombat and ns.Segments and #(ns.Segments.history or {}) > 0 and (ns.Segments.viewIndex == nil or ns.Segments.viewIndex == 0) then
                    ns.Segments.viewIndex = 1
                    if ns.UI and ns.UI:IsVisible() then C_Timer.After(0, function() ns.UI:Layout() end) end
                end
            end)
        elseif event == "PLAYER_REGEN_DISABLED" then
            if ns.Segments and ns.Segments.viewIndex and ns.Segments.viewIndex ~= 0 then ns.Segments.viewIndex = nil end
            local isTransitioningOut = (CT._wasInInstance and not ns.state.isInInstance)
            local isExiting = (CT._exitingInstanceTag ~= nil) or (CT._pendingMergeArgs ~= nil) or isTransitioningOut
            if not ns.state.isInInstance and not CT._initialBaselineSet and CT._baselineSessionCount == 0 and CT._lastProcessedCount == 0 and not isExiting then
                CT._initialBaselineSet = true
                local ss = C_DamageMeter.GetAvailableCombatSessions(); local sc = ss and #ss or 0
                if sc > 0 then
                    local lastDur = ss[sc].durationSeconds or 0; local offset = (lastDur < 2) and 1 or 0
                    CT._baselineSessionCount = math.max(0, sc - offset); CT._lastProcessedCount = math.max(0, sc - offset)
                end
            end
            if not ns.state.inCombat then ns.state.combatStartTime = GetTime(); ns:EnterCombat() end
            if ns.UI and ns.UI._collapsed then ns.UI:CheckAutoCollapse() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if ns.state.inCombat then
                if CT._currentEncounterID then return end
                C_Timer.After(0.3, function() if not isGroupInCombat() then ns.state.combatStartTime = 0; syncCombatState() end end)
            end
        end
    end)

    -- 初始化副本状态
    do
        local rawName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        CT._wasInInstance = ns.state.isInInstance
        if ns.state.isInInstance then
            CT._currentInstanceTag = string.format("%s|%d", rawName or "Unknown", instanceID or 0)
            CT._currentInstanceName = nil
            C_Timer.After(1, function() if ns.state.isInInstance then CT._currentInstanceName = GetRealZoneText() or rawName end end)
        end
        CT._bossSessionIndices = {}
    end
end

-- ============================================================
-- 事件驱动重读:扫 history,把 0 数据段填上真实数据
-- ============================================================
function CT:RescanZeroDataSegments()
    local segs = ns.Segments
    if not segs or not segs.history then return end
    local refreshed = false
    for _, seg in ipairs(segs.history) do
        if seg._sessionID
           and not seg._isMerged
           and not seg._preKeystone
           and (not seg._dataLoaded or (seg.totalDamage or 0) == 0) then
            self:LoadSegmentData(seg)
            if seg._dataLoaded then refreshed = true end
        end
    end
    if refreshed then
        if ns.Analysis then ns.Analysis:InvalidateCache() end
        if ns.UI and ns.UI:IsVisible() then ns.UI:Refresh() end
        if ns.SaveSessionHistory then ns:SaveSessionHistory() end
    end
end


function CT:ScanArchivedSessions()
    if self._scanInProgress then return end
    if ns.state.inCombat then return end
    self._scanInProgress = true
    pcall(processArchivedSessions)
    self._scanInProgress = false
end

-- ============================================================
-- Debug
-- ============================================================
function CT:DebugSessions()
    print(L["=== [Light Damage] Sessions 诊断 ==="])
    print(string.format("  baseline=%d  lastProcessed=%d  inCombat=%s  isInInstance=%s", CT._baselineSessionCount, CT._lastProcessedCount, tostring(ns.state.inCombat), tostring(ns.state.isInInstance)))
    local sessions = C_DamageMeter.GetAvailableCombatSessions(); local n = sessions and #sessions or 0
    print(string.format(L["  GetAvailableCombatSessions: %d 条"], n))
    for i, s in ipairs(sessions or {}) do
        print(string.format("    [%d] id=%-4d dur=%-6s secret=%-5s name=%s", i, s.sessionID, tostring(s.durationSeconds), tostring(isSessionStillSecret(s.sessionID)), tostring(s.name)))
    end
    local segs = ns.Segments; print(string.format(L["  history: %d 条"], segs and #segs.history or 0))
    for i, seg in ipairs(segs and segs.history or {}) do
        print(string.format("    [%d] %s  dmg=%d  heal=%d  dur=%.1f", i, seg.name or "?", seg.totalDamage, seg.totalHealing, seg.duration or 0))
    end
end

function CT:DebugAPI()
    print("=== [Light Damage] API Debug ===")
    print("  inCombat:", ns.state.inCombat); print("  updateCount:", CT._updateCount)
    print("  baseline:", CT._baselineSessionCount); print("  lastProcessed:", CT._lastProcessedCount)
    print("  issecretvalue:", issecretvalue ~= nil); print("  AbbreviateNumbers:", AbbreviateNumbers ~= nil)
    local sessions = C_DamageMeter.GetAvailableCombatSessions(); print("  sessions:", sessions and #sessions or 0)
    if sessions then for i, s in ipairs(sessions) do print(string.format("    [%d] id=%d dur=%s name=%s", i, s.sessionID, tostring(s.durationSeconds), tostring(s.name))) end end
    local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone)
    if ok and s then
        print("  Current session sources:", s.combatSources and #s.combatSources or 0)
        if s.combatSources and #s.combatSources > 0 then local src = s.combatSources[1]; print("  [1] name:", src.name, "totalAmount:", src.totalAmount) end
    end
end
