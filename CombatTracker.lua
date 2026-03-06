--[[
    LD Combat Stats - CombatTracker.lua
    战斗追踪核心逻辑
]]

local addonName, ns = ...
local L = ns.L

local CT = {}
ns.CombatTracker = CT

CT._internalReset = false

CT._updateCount          = 0
CT._baselineSessionCount = 0
CT._lastProcessedCount   = 0

-- 副本追踪
CT._currentEncounterID   = nil   -- ENCOUNTER_START 时设置，ENCOUNTER_END 后清空
CT._currentInstanceTag   = nil   -- "instanceName|mapID" 格式，副本内有效
CT._wasInInstance        = false -- 上一帧是否在副本内，用于检测退出
CT._exitingInstanceTag   = nil


CT._currentMythicLevel   = 0    -- CHALLENGE_MODE_START 时记录层数，出副本传给 mergeAndCleanInstance
CT._currentMythicMapName = nil  -- CHALLENGE_MODE_START 时记录正确的M+地图名（来自 C_ChallengeMode.GetMapUIInfo）
CT._currentInstanceName  = nil  -- ENCOUNTER_START 时记录副本名（GetInstanceInfo），用于 M+中途放弃场景的合并命名


-- ============================================================
-- 辅助
-- ============================================================
local function getAmount(val)
    if issecretvalue and issecretvalue(val) then return 0 end
    if type(val) == "number" then return val end
    return 0
end

-- ============================================================
-- 检测 session 是否仍有 secret (战斗锁)
-- ============================================================
local function isSessionStillSecret(sessionId)
    if not issecretvalue then return false end
    
    -- ★ 修复：同时检查伤害、治疗、承伤，确保所有数据都已解密
    local typesToCheck = {
        Enum.DamageMeterType.DamageDone,
        Enum.DamageMeterType.HealingDone,
        Enum.DamageMeterType.DamageTaken
    }
    
    for _, dmType in ipairs(typesToCheck) do
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionId, dmType)
        if ok and session and session.combatSources then
            for _, src in ipairs(session.combatSources) do
                -- 只要有任意一个 source 的数值是 secret，就认为还未释放
                if issecretvalue(src.totalAmount) then
                    return true
                end
            end
        end
    end
    
    return false
end

-- ============================================================
-- 用 deathRecapID 构建死亡记录（12.0 正确方式）
-- 返回 deathRecord 或 nil
--
-- DeathRecapEventInfo 实际字段（dump 确认）：
--   spellId (number), spellName (string), sourceName (string),
--   amount (number), currentHP (number), timestamp (number, unix float),
--   overkill (number, -1 = 无 overkill), school (number),
--   event (string: SPELL_DAMAGE / SWING_DAMAGE / SPELL_HEAL / ...)
-- ============================================================
local function buildDeathRecordFromRecapID(recapID, playerGUID, playerName, playerClass)
    if not recapID or recapID <= 0 then return nil end
    if not C_DeathRecap then return nil end

    -- ★ 修复：HasRecapEvents 不接受 recapID 参数，直接尝试获取数据
    local ok, recapRaw = pcall(C_DeathRecap.GetRecapEvents, recapID)
    if not ok or not recapRaw or #recapRaw == 0 then return nil end

    local maxHP = 1
    if C_DeathRecap.GetRecapMaxHealth then
        local ok2, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
        if ok2 and hp and hp > 0 then maxHP = hp end
    end

    -- 以下原有逻辑完全不变
    local reversed = {}
    for i = #recapRaw, 1, -1 do table.insert(reversed, recapRaw[i]) end

    local events     = {}
    local totalDmg   = 0
    local totalHeal  = 0
    local killingAbi = "?"
    local killerName = ""

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

        if isHeal then totalHeal = totalHeal + amount
        else totalDmg = totalDmg + amount end

        table.insert(events, {
            time      = ev.timestamp or GetTime(),
            spellID   = spellID,
            spellName = spellName,
            amount    = isHeal and -math.abs(amount) or math.abs(amount),
            isHeal    = isHeal,
            srcName   = srcName,
            hp        = hp,
            maxHP     = maxHP,
            hpPercent = hpPct,
            overkill  = overkill,
        })
    end

    for i = #events, 1, -1 do
        if not events[i].isHeal then
            killingAbi = events[i].spellName or "?"
            killerName = events[i].srcName   or ""
            break
        end
    end

    local timeSpan = #events >= 2
        and (events[#events].time - events[1].time) or 0
    local isSelf = (playerGUID == ns.state.playerGUID)

    return {
        timestamp            = time(),
        gameTime             = GetTime(),
        playerName           = ns:ShortName(playerName) or "?",
        playerGUID           = playerGUID,
        playerClass          = playerClass,
        isSelf               = isSelf,
        killingAbility       = killingAbi,
        killerName           = killerName,
        events               = events,
        lastHP               = 0,
        maxHP                = maxHP,
        totalDamageTaken     = totalDmg,
        totalHealingReceived = totalHeal,
        timeSpan             = timeSpan,
        _fromRecap           = true,
    }
end

-- ============================================================
-- 脱战后: 解析归档 session → history
-- ============================================================
local function processArchivedSessions()
    local segs = ns.Segments
    if not segs then return end

    local sessions     = C_DamageMeter.GetAvailableCombatSessions()
    local sessionCount = sessions and #sessions or 0
    if sessionCount == 0 then return end

    local lastProcessed = CT._lastProcessedCount

    if sessionCount > lastProcessed then
        for i = lastProcessed + 1, sessionCount do
            local s   = sessions[i]
            local sid = s.sessionID
            local dur = s.durationSeconds or 0

            if dur == 0 and (s.name == nil or s.name == "") then
                -- skip 空占位
            elseif dur >= (ns.db and ns.db.tracking and ns.db.tracking.minCombatTime or 2) then
                local isBoss = false
                if s.name and (s.name:sub(1, 3) == "(!)" or string.find(s.name, "(!)", 1, true)) then
                    isBoss = true
                end
                if CT._bossSessionIndices and CT._bossSessionIndices[i] then
                    isBoss = true
                end
                local instanceTag = (ns.state.isInInstance and CT._currentInstanceTag)
                                    or CT._exitingInstanceTag
                                    or nil

                local seg = segs:NewSegment("history", s.name or GetZoneText() or "Combat")
                seg.isActive             = false
                seg.duration             = dur
                seg.endTime              = GetTime()
                seg.startTime            = GetTime() - dur
                seg._isBoss              = isBoss
                seg._instanceTag         = instanceTag
                seg._instanceDisplayName = CT._currentInstanceName or nil
                seg._sessionIdx          = i
                seg._sessionID           = sid   -- ★ 核心：记录 sessionID 供按需加载
                seg._dataLoaded          = false  -- ★ 标记数据未加载

                -- 只处理死亡记录（deathRecapID 在脱战瞬间就已确定，不存在时机问题）
                local ok2, deathSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, Enum.DamageMeterType.Deaths)
                if ok2 and deathSession and deathSession.combatSources then
                    for _, src in ipairs(deathSession.combatSources) do
                        local guid    = src.sourceGUID
                        local deaths  = getAmount(src.totalAmount)
                        local recapID = getAmount(src.deathRecapID)

                        if guid and (deaths > 0 or recapID > 0) then
                            if recapID > 0 then
                                local class = src.classFilename
                                if not class then
                                    local _, classEng = GetPlayerInfoByGUID(guid)
                                    class = classEng or "WARRIOR"
                                end
                                local deathRecord = buildDeathRecordFromRecapID(recapID, guid, src.name, class)
                                if deathRecord then
                                    local replaced = false
                                    for di, existing in ipairs(seg.deathLog) do
                                        if existing.playerGUID == guid then
                                            if existing._fromRecap then
                                                replaced = true
                                            else
                                                seg.deathLog[di] = deathRecord
                                                replaced = true
                                            end
                                            break
                                        end
                                    end
                                    if not replaced then
                                        local insertIdx = deathRecord.isSelf and 1 or (#seg.deathLog + 1)
                                        if not deathRecord.isSelf then
                                            for di, dr in ipairs(seg.deathLog) do
                                                if not dr.isSelf then insertIdx = di; break end
                                            end
                                        end
                                        table.insert(seg.deathLog, insertIdx, deathRecord)
                                    end
                                    while #seg.deathLog > 50 do table.remove(seg.deathLog) end

                                    -- ▼▼▼ 新增：同步插入到 Overall 的死亡日志中 ▼▼▼
                                    local ovr = segs.overall
                                    if ovr then
                                        ovr.deathLog = ovr.deathLog or {}
                                        local ovrReplaced = false
                                        -- 查重：如果在 overall 里已经存在这个 recap 的记录，覆盖它
                                        for di, existing in ipairs(ovr.deathLog) do
                                            if existing.playerGUID == guid then
                                                if not existing._fromRecap then
                                                    ovr.deathLog[di] = deathRecord
                                                    ovrReplaced = true
                                                elseif math.abs((existing.gameTime or 0) - (deathRecord.gameTime or 0)) < 1 then
                                                    -- 极短时间内的同一个人死亡认为是同一条
                                                    ovrReplaced = true
                                                end
                                                if ovrReplaced then break end
                                            end
                                        end
                                        
                                        if not ovrReplaced then
                                            local insertIdx = deathRecord.isSelf and 1 or (#ovr.deathLog + 1)
                                            if not deathRecord.isSelf then
                                                for di, dr in ipairs(ovr.deathLog) do
                                                    if not dr.isSelf then insertIdx = di; break end
                                                end
                                            end
                                            table.insert(ovr.deathLog, insertIdx, deathRecord)
                                        end
                                        while #ovr.deathLog > 50 do table.remove(ovr.deathLog) end
                                    end
                                    -- ▲▲▲ 新增结束 ▲▲▲
                                end
                            end
                        end
                    end
                end

                -- ★ 不再判断 totalDamage > 0，只要时长够就插入
                --   数据按需由 LoadSegmentData 加载，此时可能还是 0
                table.insert(segs.history, 1, seg)
                local maxSeg = ns.db and ns.db.tracking and ns.db.tracking.maxSegments or 30
                while #segs.history > maxSeg do
                    table.remove(segs.history)
                end
                segs.viewIndex = 1
                if ns.SaveSessionHistory then ns:SaveSessionHistory() end
            end
        end
        CT._lastProcessedCount = sessionCount
    end

    ns.state.lastCombatWasBoss = false
    CT._bossSessionIndices = CT._bossSessionIndices or {}
    CT:RebuildOverall(sessions, sessionCount)
end

function CT:LoadSegmentData(seg)
    if not seg or not seg._sessionID then return end

    local sid  = seg._sessionID
    local segs = ns.Segments
    if not segs then return end

    -- 检查 session 是否仍然可用
    local sessions = C_DamageMeter.GetAvailableCombatSessions()
    local sessionAvailable = false
    for _, s in ipairs(sessions or {}) do
        if s.sessionID == sid then
            sessionAvailable = true
            seg.duration = s.durationSeconds or seg.duration
            break
        end
    end
    if not sessionAvailable then return end

    -- ★ 保存已有的快照字段，防止重读时被当前 cache 覆盖
    local snapshotCache = {}
    for guid, pd in pairs(seg.players) do
        snapshotCache[guid] = {
            specID = pd.specID,
            ilvl   = pd.ilvl,
            score  = pd.score,
        }
    end

    -- 重置玩家数据（保留 deathLog）
    seg.players          = {}
    seg.totalDamage      = 0
    seg.totalHealing     = 0
    seg.totalDamageTaken = 0

    local function checkSecret(val)
        return issecretvalue and issecretvalue(val)
    end

    -- 伤害 / 治疗 / 承伤
    for dmType, field in pairs({
        [Enum.DamageMeterType.DamageDone]  = "damage",
        [Enum.DamageMeterType.HealingDone] = "healing",
        [Enum.DamageMeterType.DamageTaken] = "damageTaken",
    }) do
        local ok, dmSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, dmType)
        if ok and dmSession then
            if checkSecret(dmSession.totalAmount) then
                seg._dataLoaded = false
                return
            end

            local segField = field == "damage"  and "totalDamage"
                          or field == "healing" and "totalHealing"
                          or "totalDamageTaken"
            seg[segField] = dmSession.totalAmount or 0

            if dmSession.combatSources then
                for _, src in ipairs(dmSession.combatSources) do
                    if checkSecret(src.totalAmount) then
                        seg._dataLoaded = false
                        return
                    end
                    local guid  = src.sourceGUID
                    local total = src.totalAmount or 0
                    if guid and total > 0 then
                        local pd = segs:GetPlayer(seg, guid, src.name, nil)
                        if pd then
                            pd.class  = src.classFilename or pd.class
                            pd[field] = total
                            -- ★ 直接从 session 读暴雪算好的每秒值（活跃时间口径）
                            local aps = getAmount(src.amountPerSecond)
                            if aps > 0 then
                                pd[field .. "PerSec"] = aps
                            end
                        end
                    end
                end
            end
        end
    end

    -- 打断 / 驱散
    for dmType, field in pairs({
        [Enum.DamageMeterType.Interrupts] = "interrupts",
        [Enum.DamageMeterType.Dispels]    = "dispels",
    }) do
        local spellField = field == "interrupts" and "interruptSpells" or "dispelSpells"
        local ok, dmSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, dmType)
        if ok and dmSession and dmSession.combatSources then
            for _, src in ipairs(dmSession.combatSources) do
                local guid  = src.sourceGUID
                local total = getAmount(src.totalAmount)
                if guid and total > 0 then
                    local pd = segs:GetPlayer(seg, guid, src.name, nil)
                    if pd then
                        pd.class  = src.classFilename or pd.class
                        pd[field] = (pd[field] or 0) + total
                    end
                    local ok3, srcData = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sid, dmType, guid)
                    if ok3 and srcData and srcData.combatSpells then
                        local pdd = segs:GetPlayer(seg, guid, src.name, nil)
                        if pdd then
                            for _, sp in ipairs(srcData.combatSpells) do
                                local spellID = getAmount(sp.spellID)
                                if spellID > 0 then
                                    local amt = getAmount(sp.totalAmount)
                                    if amt == 0 then amt = getAmount(sp.casts) end
                                    if amt == 0 then amt = 1 end
                                    if amt > 0 then
                                        if not pdd[spellField][spellID] then
                                            local spellName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or ("spell:" .. spellID)
                                            pdd[spellField][spellID] = segs:NewSpellData(spellID, spellName, nil)
                                        end
                                        pdd[spellField][spellID].hits   = pdd[spellField][spellID].hits   + amt
                                        pdd[spellField][spellID].damage = pdd[spellField][spellID].damage + amt
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 死亡次数
    local ok2, deathSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, Enum.DamageMeterType.Deaths)
    if ok2 and deathSession and deathSession.combatSources then
        for _, src in ipairs(deathSession.combatSources) do
            local guid   = src.sourceGUID
            local deaths = getAmount(src.totalAmount)
            if guid and deaths > 0 then
                local pd = segs:GetPlayer(seg, guid, src.name, nil)
                if pd then
                    pd.class  = src.classFilename or pd.class
                    pd.deaths = (pd.deaths or 0) + deaths
                end
            end
        end
    end

    -- 技能明细
    for guid, pd in pairs(seg.players) do
        for dmType, spellTable in pairs({
            [Enum.DamageMeterType.DamageDone]  = "spells",
            [Enum.DamageMeterType.HealingDone] = "spells",
            [Enum.DamageMeterType.DamageTaken] = "damageTakenSpells",
        }) do
            local ok3, srcData = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sid, dmType, guid)
            if ok3 and srcData and srcData.combatSpells then
                for _, sp in ipairs(srcData.combatSpells) do
                    local spellID = getAmount(sp.spellID)
                    if spellID > 0 then
                        local amt = getAmount(sp.totalAmount)
                        if amt > 0 then
                            local targetSpells = pd[spellTable]
                            
                            -- ★ 终极正解：通过法术自带的 creatureName 识别宠物
                            local isPetSpell = false
                            local petName = sp.creatureName
                            
                            -- 如果存在附属生物名字，且不是玩家自己，必然是宝宝放的
                            if petName and petName ~= "" and petName ~= pd.name and petName ~= srcData.name then
                                isPetSpell = true
                            end
                            
                            if isPetSpell then
                                if not pd.pets[petName] then
                                    pd.pets[petName] = { name = petName, spells = {}, damageTakenSpells = {}, damage = 0, healing = 0 }
                                end
                                targetSpells = pd.pets[petName][spellTable]
                                
                                if dmType == Enum.DamageMeterType.HealingDone then
                                    pd.pets[petName].healing = (pd.pets[petName].healing or 0) + amt
                                elseif dmType == Enum.DamageMeterType.DamageDone then
                                    pd.pets[petName].damage = (pd.pets[petName].damage or 0) + amt
                                end
                            end

                            if not targetSpells[spellID] then
                                local spellName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or ("spell:" .. spellID)
                                targetSpells[spellID] = segs:NewSpellData(spellID, spellName, nil)
                            end
                            local sd = targetSpells[spellID]
                            
                            if dmType == Enum.DamageMeterType.HealingDone then
                                sd.healing = (sd.healing or 0) + amt
                            else
                                sd.damage = (sd.damage or 0) + amt
                            end
                            sd.hits = (sd.hits or 0) + 1
                            if sp.isAvoidable then sd.isAvoidable = true end
                        end
                    end
                end
            end
        end
    end

    -- ★ 还原快照字段，不让后续 cache 变化污染历史数据
    for guid, pd in pairs(seg.players) do
        local snap = snapshotCache[guid]
        if snap then
            pd.specID = snap.specID or pd.specID
            pd.ilvl   = snap.ilvl   or pd.ilvl
            pd.score  = snap.score  or pd.score
        end
    end

    seg._dataLoaded = true
end

-- ============================================================
-- 退出副本时：合并该副本所有 seg → 一条汇总，删掉小怪，保留 boss
-- ============================================================
-- mythicLevel: M+副本传层数(>0)，普通副本传0
local function mergeAndCleanInstance(instanceTag, mythicLevel, mythicMapName, instanceName)
    local segs = ns.Segments
    if not segs then return end

    mythicLevel = mythicLevel or 0
    local isRaid = (CT._currentInstanceType == "raid")

    local instSegs = {}
    for i, seg in ipairs(segs.history) do
        if seg._instanceTag == instanceTag and not seg._isMerged then
            -- 排除已合并的全程段
            table.insert(instSegs, {idx = i, seg = seg})
        end
    end
    if #instSegs == 0 then return end

    local zoneName
    if mythicLevel > 0 and mythicMapName and mythicMapName ~= "" then
        zoneName = mythicMapName
    elseif instanceName and instanceName ~= "" then
        zoneName = instanceName
    elseif instSegs[1].seg._instanceDisplayName and instSegs[1].seg._instanceDisplayName ~= "" then
        zoneName = instSegs[1].seg._instanceDisplayName
    else
        zoneName = instanceTag:match("^([^|]+)") or L["副本"]
    end

    -- ★ 提取公共逻辑：非 Raid 副本（地下城、大秘境等）直接深度克隆现有的 Overall 避免合并误差
    local function cloneOverallToMerged(merged)
        -- ★ 优先读取过图时的备份快照，如果没有再读当前的
        local ovr = segs.overall
        if not ovr then return end
        
        merged.totalDamage      = ovr.totalDamage or 0
        merged.totalHealing     = ovr.totalHealing or 0
        merged.totalDamageTaken = ovr.totalDamageTaken or 0
        merged.duration         = (CT._overallDurationSnapshot and CT._overallDurationSnapshot > 0)
                                  and CT._overallDurationSnapshot or (ovr.duration or 0)
        
        merged.players = CopyTable(ovr.players or {})
        
        merged.deathLog = CopyTable(ovr.deathLog or {})
        table.sort(merged.deathLog, function(a, b)
            if a.isSelf ~= b.isSelf then return a.isSelf end
            return (a.gameTime or 0) < (b.gameTime or 0)
        end)
        -- 保留最后发生的记录
        while #merged.deathLog > 50 do 
            -- 尝试删掉第一条不是自己的旧记录
            local removed = false
            for i = 1, #merged.deathLog do
                if not merged.deathLog[i].isSelf then
                    table.remove(merged.deathLog, i)
                    removed = true
                    break
                end
            end
            -- 如果全都是自己的记录（极端情况），删掉最旧的自己
            if not removed then table.remove(merged.deathLog, 2) end 
        end
    end

    -- ================= 分支1：M+ 正常通关 =================
    if mythicLevel > 0 then
        local pending = ns.MythicPlus and ns.MythicPlus._pendingMythicSeg
        if pending then
            ns.MythicPlus._pendingMythicSeg = nil

            local mergedName = string.format("|cff4cb8e8+%d|r %s", pending.level, pending.mapName)
            local merged = segs:NewSegment("mythicplus", mergedName)
            merged.isActive           = false
            merged._instanceTag       = nil
            merged._isBoss            = false
            merged._isMerged          = true
            merged._builtByMythicPlus = true
            merged.success            = pending.success
            merged._mythicLevel       = pending.level
            merged._mapName           = pending.mapName
            merged.mythicLevel        = pending.level
            merged.mapName            = pending.mapName
            merged.mapID              = pending.mapID
            merged._keystoneTime      = (pending.elapsed or 0) / 1000

            -- ★ 直接完美克隆 Overall 数据
            cloneOverallToMerged(merged)

            -- 删除非 Boss 段，保留 Boss 段
            local indicesToRemove = {}
            local bossCount = 0
            for _, entry in ipairs(instSegs) do
                if entry.seg._isBoss then bossCount = bossCount + 1
                else table.insert(indicesToRemove, entry.idx) end
            end
            table.sort(indicesToRemove, function(a, b) return a > b end)
            for _, idx in ipairs(indicesToRemove) do table.remove(segs.history, idx) end

            if merged.totalDamage > 0 or merged.totalHealing > 0 then
                table.insert(segs.history, 1, merged)
                segs.viewIndex = 1
            end

            local maxSeg = ns.db and ns.db.tracking and ns.db.tracking.maxSegments or 30
            while #segs.history > maxSeg do table.remove(segs.history) end

            if ns.CombatTracker then ns.CombatTracker:ResetBaselineToCurrentCount() end
            if ns.Segments then 
                ns.Segments._preReloadOverallData = nil

                if not ns.state.isInInstance then
                    ns.Segments.overall = ns.Segments:NewSegment("overall", L["总计"])
                end
            end
            CT._overallDurationSnapshot = nil
            CT._exitingInstanceTag = nil

            if ns.SaveSessionHistory then ns:SaveSessionHistory() end
            if ns.UI then C_Timer.After(0, function() ns.UI:Layout() end) end

            local bossStr = bossCount > 0 and string.format(L["，保留 %d 个 Boss"], bossCount) or ""
            print(string.format(L["|cff00ccff[LD Stats]|r 副本 %s 已整理%s + 1 条全程汇总"], pending.mapName, bossStr))
            return
        end
    end

    -- ================= 分支2：非M+ 或 M+中途放弃 =================
    local mergedName
    if mythicLevel > 0 then
        mergedName = string.format(L["|cff4cb8e8+%d|r %s |cffaaaaaa[全程]|r"], mythicLevel, zoneName)
    else
        mergedName = string.format(L["%s [全程]"], zoneName)
    end

    local merged = segs:NewSegment("history", mergedName)
    merged.isActive     = false
    merged._instanceTag = nil
    merged._isBoss      = false
    merged._isMerged    = true
    if mythicLevel > 0 then
        merged._mythicLevel = mythicLevel
        merged._mapName     = zoneName
    end

    if not isRaid then
        -- ★ 如果不是团队副本（即大秘境中途放弃 或 普通地下城），直接完美克隆 Overall 数据！
        cloneOverallToMerged(merged)
    else
        -- ★ 只有团队副本(Raid)，才需要手动挑出包含 _isBoss 的战斗段进行累加合并
        local totalDur = 0
        for i = #instSegs, 1, -1 do
            local entry = instSegs[i]
            local src = entry.seg
            src._dataLoaded = false
            CT:LoadSegmentData(src)

            if src._isBoss then
                totalDur = totalDur + (src.duration or 0)

                for guid, pd in pairs(src.players) do
                    local mp = segs:GetPlayer(merged, guid, pd.name, nil)
                    if mp then
                        mp.class       = pd.class or mp.class
                        mp.damage      = (mp.damage      or 0) + (pd.damage      or 0)
                        mp.healing     = (mp.healing     or 0) + (pd.healing     or 0)
                        mp.damageTaken = (mp.damageTaken or 0) + (pd.damageTaken or 0)
                        mp.interrupts  = (mp.interrupts  or 0) + (pd.interrupts  or 0)
                        mp.dispels     = (mp.dispels     or 0) + (pd.dispels     or 0)
                        mp.deaths      = (mp.deaths      or 0) + (pd.deaths      or 0)
                        for spellID, sd in pairs(pd.spells or {}) do
                            if not mp.spells[spellID] then
                                mp.spells[spellID] = segs:NewSpellData(spellID, sd.name, sd.school)
                            end
                            local msd = mp.spells[spellID]
                            msd.damage  = (msd.damage  or 0) + (sd.damage  or 0)
                            msd.healing = (msd.healing or 0) + (sd.healing or 0)
                            msd.hits    = (msd.hits    or 0) + (sd.hits    or 0)
                            msd.crits   = (msd.crits   or 0) + (sd.crits   or 0)
                        end
                        for spellID, sd in pairs(pd.damageTakenSpells or {}) do
                            if not mp.damageTakenSpells[spellID] then
                                mp.damageTakenSpells[spellID] = segs:NewSpellData(spellID, sd.name, sd.school)
                            end
                            local msd = mp.damageTakenSpells[spellID]
                            msd.damage = (msd.damage or 0) + (sd.damage or 0)
                            msd.hits   = (msd.hits or 0) + (sd.hits or 0)
                        end
                        for spellID, sd in pairs(pd.interruptSpells or {}) do
                            if not mp.interruptSpells[spellID] then
                                mp.interruptSpells[spellID] = segs:NewSpellData(spellID, sd.name, sd.school)
                            end
                            local msd = mp.interruptSpells[spellID]
                            msd.damage = (msd.damage or 0) + (sd.damage or 0)
                            msd.hits   = (msd.hits or 0) + (sd.hits or 0)
                        end
                        for spellID, sd in pairs(pd.dispelSpells or {}) do
                            if not mp.dispelSpells[spellID] then
                                mp.dispelSpells[spellID] = segs:NewSpellData(spellID, sd.name, sd.school)
                            end
                            local msd = mp.dispelSpells[spellID]
                            msd.damage = (msd.damage or 0) + (sd.damage or 0)
                            msd.hits   = (msd.hits or 0) + (sd.hits or 0)
                        end
                    end
                end

                merged.totalDamage      = merged.totalDamage      + (src.totalDamage      or 0)
                merged.totalHealing     = merged.totalHealing     + (src.totalHealing     or 0)
                merged.totalDamageTaken = merged.totalDamageTaken + (src.totalDamageTaken or 0)

                for _, dr in ipairs(src.deathLog or {}) do
                    table.insert(merged.deathLog, dr)
                end
            end
        end
        merged.duration = (CT._overallDurationSnapshot and CT._overallDurationSnapshot > 0)
                          and CT._overallDurationSnapshot or totalDur
    end

    -- ==== 收尾整理：删掉小怪，保留 Boss ====
    local indicesToRemove = {}
    local bossCount = 0
    for _, entry in ipairs(instSegs) do
        if entry.seg._isBoss then
            bossCount = bossCount + 1
        else
            table.insert(indicesToRemove, entry.idx)
        end
    end
    table.sort(indicesToRemove, function(a, b) return a > b end)
    for _, idx in ipairs(indicesToRemove) do
        table.remove(segs.history, idx)
    end

    if merged.totalDamage > 0 or merged.totalHealing > 0 then
        table.insert(segs.history, 1, merged)
        segs.viewIndex = 1
    end

    local maxSeg = ns.db and ns.db.tracking and ns.db.tracking.maxSegments or 30
    while #segs.history > maxSeg do table.remove(segs.history) end

    if ns.CombatTracker then ns.CombatTracker:ResetBaselineToCurrentCount() end

    if ns.Segments then 
        ns.Segments._preReloadOverallData = nil 
        -- ★ 延迟到这里才清空 Overall，确保户外的 overall 变成纯净的
        if not ns.state.isInInstance then
            -- ★ 离开副本且归档后，强制执行一次暴雪统计Reset，让野外重新开始计算
            if C_DamageMeter.ResetAllCombatSessions then
                CT._internalReset = true
                C_DamageMeter.ResetAllCombatSessions()
            end
            CT._baselineSessionCount = 0
            CT._lastProcessedCount   = 0
            ns.Segments.overall = ns.Segments:NewSegment("overall", L["总计"])
        end
    end
    CT._overallDurationSnapshot = nil
    CT._exitingInstanceTag = nil
    
    if ns.SaveSessionHistory then ns:SaveSessionHistory() end
    if ns.UI then C_Timer.After(0, function() ns.UI:Layout() end) end

    local bossStr = bossCount > 0 and string.format(L["，保留 %d 个 Boss"], bossCount) or ""
    print(string.format(L["|cff00ccff[LD Stats]|r 副本 %s 已整理%s + 1 条全程汇总"], zoneName, bossStr))
end

-- ============================================================
-- 重建 Overall 段
-- ============================================================
function CT:RebuildOverall(sessions, sessionCount)
    local segs = ns.Segments
    if not segs then return end

    sessions     = sessions or C_DamageMeter.GetAvailableCombatSessions()
    sessionCount = sessionCount or (sessions and #sessions or 0)


    -- ★ 先在本地变量中累积，最后一次性原子写入 overall，
    --   避免空闲刷新（2s）在重建中途读到清零状态
    local newPlayers        = {}
    local newTotalDamage    = 0
    local newTotalHealing   = 0
    local newTotalDTaken    = 0
    local totalDur          = 0

    -- ★ 修复Issue1：reload在副本内时，从快照恢复数据，后续新session叠加上去
    local snap = segs._preReloadOverallData
    if snap then
        newTotalDamage    = snap.totalDamage
        newTotalHealing   = snap.totalHealing
        newTotalDTaken    = snap.totalDamageTaken
        totalDur          = snap.duration
        for guid, pd in pairs(snap.players) do
            newPlayers[guid] = CopyTable(pd)
        end
    end

    local function getAmount(amt) 
        if issecretvalue and issecretvalue(amt) then return 0 end
        return type(amt)=="number" and amt or 0 
    end

    -- 内部 GetPlayer，操作 newPlayers 而非 segs.overall.players
    local function getOrCreatePlayer(guid, name)
        if not newPlayers[guid] then
            local _, classEng = GetPlayerInfoByGUID(guid)
            newPlayers[guid] = segs:NewPlayerData(guid, name, classEng or "WARRIOR")
        end
        if name and name ~= "" then
            newPlayers[guid].name = ns:ShortName(name)
        end
        return newPlayers[guid]
    end

    for i = CT._baselineSessionCount + 1, sessionCount do
        local s   = sessions[i]
        local sid = s.sessionID
        local dur = s.durationSeconds or 0
        
        if dur > 0 then
            totalDur = totalDur + dur

            for dmType, field in pairs({
                [Enum.DamageMeterType.DamageDone]  = "damage",
                [Enum.DamageMeterType.HealingDone] = "healing",
                [Enum.DamageMeterType.DamageTaken] = "damageTaken",
            }) do
                local ok2, dmSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, dmType)
                if ok2 and dmSession and dmSession.combatSources then
                    for _, src in ipairs(dmSession.combatSources) do
                        local guid  = src.sourceGUID
                        local total = getAmount(src.totalAmount)
                        if guid and total > 0 then
                            local pd = getOrCreatePlayer(guid, src.name)
                            pd.class       = src.classFilename or pd.class
                            pd[field]      = (pd[field] or 0) + total
                            if field == "damage" then
                                newTotalDamage  = newTotalDamage  + total
                            elseif field == "healing" then
                                newTotalHealing = newTotalHealing + total
                            else
                                newTotalDTaken  = newTotalDTaken  + total
                            end
                        end
                    end
                end
            end

            -- 死亡（原逻辑保留）
            for dmType, field in pairs({
                [Enum.DamageMeterType.Deaths] = "deaths",
            }) do
                local ok2, dmSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, dmType)
                if ok2 and dmSession and dmSession.combatSources then
                    for _, src in ipairs(dmSession.combatSources) do
                        local guid  = src.sourceGUID
                        local total = getAmount(src.totalAmount)
                        if guid and total > 0 then
                            local pd = getOrCreatePlayer(guid, src.name)
                            pd.class  = src.classFilename or pd.class
                            pd[field] = (pd[field] or 0) + total
                        end
                    end
                end
            end

            -- 打断/驱散 + 技能提取（原逻辑保留）
            for dmType, field in pairs({
                [Enum.DamageMeterType.Interrupts] = "interrupts",
                [Enum.DamageMeterType.Dispels]    = "dispels",
            }) do
                local spellField = field == "interrupts" and "interruptSpells" or "dispelSpells"
                local ok2, dmSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, dmType)
                if ok2 and dmSession and dmSession.combatSources then
                    for _, src in ipairs(dmSession.combatSources) do
                        local guid  = src.sourceGUID
                        local total = getAmount(src.totalAmount)
                        if guid and total > 0 then
                            local pd = getOrCreatePlayer(guid, src.name)
                            pd.class  = src.classFilename or pd.class
                            pd[field] = (pd[field] or 0) + total

                            local ok3, srcData = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sid, dmType, guid)
                            if ok3 and srcData and srcData.combatSpells then
                                for _, sp in ipairs(srcData.combatSpells) do
                                    local spellID = getAmount(sp.spellID)
                                    if spellID > 0 then
                                        local amt = getAmount(sp.totalAmount)
                                        if amt == 0 then amt = getAmount(sp.casts) end
                                        if amt == 0 then amt = 1 end
                                        if amt > 0 then
                                            if not pd[spellField][spellID] then
                                                local spellName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or ("spell:" .. spellID)
                                                pd[spellField][spellID] = segs:NewSpellData(spellID, spellName, nil)
                                            end
                                            pd[spellField][spellID].hits   = pd[spellField][spellID].hits   + amt
                                            pd[spellField][spellID].damage = pd[spellField][spellID].damage + amt
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- 技能明细：伤害/治疗/承伤（原逻辑保留）
            for guid, pd in pairs(newPlayers) do
                for dmType, spellField in pairs({
                    [Enum.DamageMeterType.DamageDone]  = "spells",
                    [Enum.DamageMeterType.HealingDone] = "spells",
                    [Enum.DamageMeterType.DamageTaken] = "damageTakenSpells",
                }) do
                    local ok3, srcData = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sid, dmType, guid)
                    if ok3 and srcData and srcData.combatSpells then
                        for _, sp in ipairs(srcData.combatSpells) do
                            local spellID = getAmount(sp.spellID)
                            if spellID > 0 then
                                local amt = getAmount(sp.totalAmount)
                                if amt > 0 then
                                    local targetSpells = pd[spellField]
                                    
                                    -- 通过法术自带的 creatureName 识别宠物
                                    local isPetSpell = false
                                    local petName = sp.creatureName
                                    
                                    -- 如果存在附属生物名字，且不是玩家自己，必然是宝宝放的
                                    if petName and petName ~= "" and petName ~= pd.name and petName ~= srcData.name then
                                        isPetSpell = true
                                    end
                                    
                                    if isPetSpell then
                                        if not pd.pets[petName] then
                                            pd.pets[petName] = { name = petName, spells = {}, damageTakenSpells = {}, damage = 0, healing = 0 }
                                        end
                                        targetSpells = pd.pets[petName][spellField]
                                        
                                        if dmType == Enum.DamageMeterType.HealingDone then
                                            pd.pets[petName].healing = (pd.pets[petName].healing or 0) + amt
                                        elseif dmType == Enum.DamageMeterType.DamageDone then
                                            pd.pets[petName].damage = (pd.pets[petName].damage or 0) + amt
                                        end
                                    end

                                    if not targetSpells[spellID] then
                                        local spellName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or ("spell:" .. spellID)
                                        targetSpells[spellID] = segs:NewSpellData(spellID, spellName, nil)
                                    end
                                    local sd = targetSpells[spellID]
                                    
                                    if dmType == Enum.DamageMeterType.HealingDone then
                                        sd.healing = (sd.healing or 0) + amt
                                    else
                                        sd.damage = (sd.damage or 0) + amt
                                    end
                                    sd.hits = (sd.hits or 0) + 1
                                    if sp.isAvoidable then sd.isAvoidable = true end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- ★ 原子写入：所有计算完成后一次性覆盖，UI 不会读到中间状态
    segs.overall.players          = newPlayers
    segs.overall.totalDamage      = newTotalDamage
    segs.overall.totalHealing     = newTotalHealing
    segs.overall.totalDamageTaken = newTotalDTaken
    
    -- 只有在没有跳过旧战斗的情况下，才能信任暴雪的原生 Overall 战斗时长
    if CT._baselineSessionCount == 0 then
        segs.overall.duration = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall) or totalDur
    else
        segs.overall.duration = totalDur
    end
    
    segs.overall.isActive         = false

    -- ▼▼▼ 新增：恢复 Reload 前的死亡记录 ▼▼▼
    if snap and snap.deathLog then
        segs.overall.deathLog = CopyTable(snap.deathLog)
    elseif not segs.overall.deathLog then
        segs.overall.deathLog = {}
    end
end

-- ============================================================
-- 等 secret 释放后再解析
-- ============================================================
local waitTicker

local function waitAndProcessArchived()

    if waitTicker then return end

    local function anyUnprocessedStillSecret()
        local sessions = C_DamageMeter.GetAvailableCombatSessions()
        local count    = sessions and #sessions or 0
        for i = CT._lastProcessedCount + 1, count do
            local s = sessions[i]
            
            -- 1. 检查是否还有加密数据
            if isSessionStillSecret(s.sessionID) then
                return true
            end
            
            -- 2. 【新增防丢补丁】检查暴雪是否还没来得及生成战斗名称和时长
            -- 如果还没生成，让 ticker 再等 0.5 秒，不要急着放行给 processArchivedSessions 去跳过它
            if (s.durationSeconds or 0) == 0 and (s.name == nil or s.name == "") then
                return true
            end
        end
        return false
    end

    local function doAfterProcess()


        -- 1. 先把最后的战斗数据解析完
        processArchivedSessions()
        
        -- 2. 数据入库后，再执行副本合并
        if CT._pendingMergeArgs then
            local args = CT._pendingMergeArgs
            CT._pendingMergeArgs = nil
            mergeAndCleanInstance(args.tag, args.lvl, args.mapName, args.instName)
        end
        
        if ns.Segments then ns.Segments._locked = false end
        if ns.UI then
            C_Timer.After(0, function() ns.UI:Layout() end)
        end

        -- ★ 暴雪脱战后不仅会继续修正 durationSeconds，敌人身上的 DOT 也可能继续跳伤害
        --   轮询一段时间，发现伤害或时长有变化就重新加载，确保数据最终完全对齐
        C_Timer.After(1, function()
            local function tryRefresh(attempts)
                if ns.state.inCombat then return end  -- 已经进入下一场战斗，放弃
                
                local segs = ns.Segments
                if not segs or not segs.history or #segs.history == 0 then return end
                
                -- 获取最新归档的那场历史战斗
                local latestSeg = segs.history[1]
                if not latestSeg or not latestSeg._sessionID then return end

                local sessions = C_DamageMeter.GetAvailableCombatSessions()
                local sessionActive = false
                local latestDur = 0
                for _, s in ipairs(sessions or {}) do
                    if s.sessionID == latestSeg._sessionID then
                        latestDur = s.durationSeconds or 0
                        sessionActive = true
                        break
                    end
                end
                
                if not sessionActive then return end

                -- 获取暴雪底层更新后的总伤害 (用于对比是否跳了新的 DOT)
                local latestDmg = 0
                local ok, dmSession = pcall(C_DamageMeter.GetCombatSessionFromID, latestSeg._sessionID, Enum.DamageMeterType.DamageDone)
                if ok and dmSession and not (issecretvalue and issecretvalue(dmSession.totalAmount)) then
                    latestDmg = dmSession.totalAmount or 0
                end

                -- 检查时长或伤害是否有变化
                local isChanged = false
                if latestDur > 0 and math.abs(latestDur - (latestSeg.duration or 0)) > 0.1 then isChanged = true end
                if latestDmg > 0 and math.abs(latestDmg - (latestSeg.totalDamage or 0)) > 0.1 then isChanged = true end

                if isChanged then
                    -- 1. 更新刚结束的单次战斗数据
                    latestSeg._dataLoaded = false
                    ns.CombatTracker:LoadSegmentData(latestSeg)
                    
                    -- 2. 同步更新全程数据 (Overall)，确保加入新跳的 DOT
                    ns.Segments._preReloadOverallData = nil
                    ns.CombatTracker:RebuildOverall(sessions, sessions and #sessions or 0)
                    
                    if ns.Analysis then ns.Analysis:InvalidateCache() end
                    if ns.UI and ns.UI:IsVisible() then ns.UI:Layout() end
                end

                -- 最多重试 10 次（脱战后持续追踪 10 秒，足以覆盖绝大部分 DOT 持续时间）
                if attempts < 10 then
                    C_Timer.After(1, function() tryRefresh(attempts + 1) end)
                end
            end
            tryRefresh(1)
        end)
    end

    if not anyUnprocessedStillSecret() then
        doAfterProcess()
        return
    end

    waitTicker = C_Timer.NewTicker(0.5, function()
        if InCombatLockdown() then return end
        if anyUnprocessedStillSecret() then return end
        
        if waitTicker then waitTicker:Cancel(); waitTicker = nil end
        doAfterProcess()
    end)
end
-- ============================================================
-- 状态同步
-- ============================================================
local function syncCombatState()
    CT._updateCount = CT._updateCount + 1

    local sessions     = C_DamageMeter.GetAvailableCombatSessions()
    local sessionCount = sessions and #sessions or 0
    local hasLive      = UnitAffectingCombat("player") == true

    if hasLive then
        if not ns.state.inCombat then
            if not ns.state.combatStartTime or ns.state.combatStartTime == 0 then
                local liveDur = sessionCount > 0 and (sessions[sessionCount].durationSeconds or 0) or 0
                ns.state.combatStartTime = GetTime() - liveDur
            end
            ns:EnterCombat()
        end

        if ns.Segments and ns.Segments.current and sessionCount > 0 then
            local apiName = sessions[sessionCount].name
            if apiName and apiName ~= "" then
                ns.Segments.current.name = apiName
            end
        end
    else
        if ns.state.inCombat then
            ns:LeaveCombat()
            C_Timer.After(0.5, waitAndProcessArchived)
        end
    end
end

-- ============================================================
-- 公开接口
-- ============================================================

function CT:ResetMeterForNewRun()
    if C_DamageMeter.ResetAllCombatSessions then
        CT._internalReset = true  -- ★ 标记为内部重置，防止 DAMAGE_METER_RESET 清空 history
        C_DamageMeter.ResetAllCombatSessions()
    end
    CT._baselineSessionCount = 0
    CT._lastProcessedCount   = 0
    CT._bossSessionIndices   = {}
    if ns.MythicPlus then ns.MythicPlus:ResetBaseline() end
end


function CT:MarkReset()
    if C_DamageMeter.ResetAllCombatSessions then
        C_DamageMeter.ResetAllCombatSessions()
    end
    CT._baselineSessionCount = 0
    CT._lastProcessedCount   = 0
end

function CT:SetBaseline()
    local sessions = C_DamageMeter.GetAvailableCombatSessions()
    CT._baselineSessionCount = sessions and #sessions or 0
    CT._lastProcessedCount   = CT._baselineSessionCount
end

function CT:ResetBaselineToCurrentCount()
    local sessions = C_DamageMeter.GetAvailableCombatSessions()
    local count    = sessions and #sessions or 0
    CT._baselineSessionCount = count
    CT._lastProcessedCount   = count
    CT._bossSessionIndices   = {}
end

function CT:PullCurrentData()
    -- 预览模式下跳过数据拉取，防止真实数据覆盖假数据
    if ns.Config and ns.Config._pvRefreshBlocked then return end
    syncCombatState()
    if ns.UI and ns.UI:IsVisible() then
        ns.UI:Refresh()
    end
end

function CT:RegisterEvents()
    if CT._eventsRegistered then return end
    CT._eventsRegistered = true
    CT._initializingGuard = true

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("ENCOUNTER_START")
    f:RegisterEvent("ENCOUNTER_END")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("CHALLENGE_MODE_START")
    f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    f:RegisterEvent("CHALLENGE_MODE_RESET")
    f:RegisterEvent("PLAYER_LEAVING_WORLD")

    f:SetScript("OnEvent", function(_, event, ...)

        
        -- ★ 核心修复：在读条离开副本的瞬间，抓取官方最真实的 Overall 战斗时间
        -- 因为一旦读条结束到了 PLAYER_ENTERING_WORLD，官方接口会切到野外，返回就会变成 0。
        if event == "PLAYER_LEAVING_WORLD" then
            if ns.state.isInInstance then
                local officialDur = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall)
                if officialDur and officialDur > 0 then
                    CT._overallDurationSnapshot = officialDur
                end
            end
            return
        end

        if event == "ENCOUNTER_START" then
            local encounterID = ...
            CT._currentEncounterID = encounterID
            local ss = C_DamageMeter.GetAvailableCombatSessions()
            CT._encounterStartSessionCount = ss and #ss or 0

        elseif event == "ENCOUNTER_END" then
            CT._currentEncounterID = nil
            local ss = C_DamageMeter.GetAvailableCombatSessions()
            local now = ss and #ss or 0
            CT._bossSessionIndices = CT._bossSessionIndices or {}
            for i = (CT._encounterStartSessionCount or now) + 1, now do
                CT._bossSessionIndices[i] = true
            end

            -- ★ 修复竞态：processArchivedSessions 可能在 ENCOUNTER_END 之前已跑完，
            --   此时那些 session 对应的 history 段已经存在但 _isBoss = false。
            --   在这里补扫一遍，把属于本次 encounter 的段全部补标为 _isBoss = true。
            local segs = ns.Segments
            if segs and segs.history then
                for _, seg in ipairs(segs.history) do
                    if seg._sessionIdx and CT._bossSessionIndices[seg._sessionIdx] then
                        seg._isBoss = true
                    end
                end
            end

        elseif event == "CHALLENGE_MODE_START" then
            local level = 0
            local mapName = nil
            if C_ChallengeMode then
                if C_ChallengeMode.GetActiveKeystoneInfo then
                    level = C_ChallengeMode.GetActiveKeystoneInfo() or 0
                end
                if C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetMapUIInfo then
                    local mapID = C_ChallengeMode.GetActiveChallengeMapID()
                    if mapID then
                        mapName = C_ChallengeMode.GetMapUIInfo(mapID)
                    end
                end
            end
            CT._currentMythicLevel   = level or 0
            CT._currentMythicMapName = mapName

        elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then
            -- 不在此处清零，出副本时 mergeAndCleanInstance 用完后自行清零

        elseif event == "PLAYER_ENTERING_WORLD" then
            ns:UpdateInstanceStatus()
            local inInstance = ns.state.isInInstance
            local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()

            local rawName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
            local newBaseTag = string.format("%s|%d", rawName or "Unknown", instanceID or 0)

            -- 检测是否离开当前副本 (退到开放世界，或者直接传送到另一个副本)
            local isExitingInstance = false
            if CT._wasInInstance then
                if not inInstance then
                    isExitingInstance = true
                elseif CT._currentInstanceTag and not CT._currentInstanceTag:find(newBaseTag, 1, true) then
                    isExitingInstance = true
                end
            end

            if isExitingInstance then

                local currentSessions = C_DamageMeter.GetAvailableCombatSessions()

                local tag      = CT._currentInstanceTag
                local lvl      = CT._currentMythicLevel
                local mapName  = CT._currentMythicMapName
                local instName = CT._currentInstanceName

                if tag then
                    CT._exitingInstanceTag = tag

                    -- 1. 瞬间把参数存好（不要用定时器延迟！）
                    CT._pendingMergeArgs = {
                        tag      = tag,
                        lvl      = lvl,
                        mapName  = mapName,
                        instName = instName,
                    }

                    if ns.state.inCombat then
                        ns.state.inCombat      = false
                        ns.state.combatEndTime = GetTime()
                        if ns.Segments then ns.Segments:OnCombatEnd() end
                        if ns.UI then ns.UI:OnCombatStateChanged(false) end
                    end


                    -- 2. 立刻召唤等待函数去处理收尾和合并
                    C_Timer.After(0, waitAndProcessArchived)
                end

                CT._currentInstanceTag   = nil
                CT._currentInstanceName  = nil
                CT._currentMythicLevel   = 0
                CT._currentMythicMapName = nil

                if ns.MythicPlus then ns.MythicPlus._completedAndStillInside = false end  -- ★



                -- ★ 出副本时清掉存档的 tag
                if ns.db then 
                    ns.db.currentInstanceTag = nil 
                end
            end

            -- 进入副本
            if inInstance then

                CT._currentInstanceType = select(2, GetInstanceInfo())  -- "raid" / "party" / "scenario"

                local rawName = GetInstanceInfo()
                local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
                local baseTag = string.format("%s|%d", rawName or "Unknown", instanceID or 0)

                local existingTag = ns.db.currentInstanceTag
                local isSameInstance = false
                if existingTag and existingTag:find(baseTag, 1, true) then
                    CT._currentInstanceTag = existingTag
                    isSameInstance = true
                else
                    CT._currentInstanceTag = string.format("%s|%d|%d", rawName or "Unknown", instanceID or 0, time())
                    ns.db.currentInstanceTag = CT._currentInstanceTag
                end

                -- ▼▼▼ 新增：每次加载后，如果是同一个副本，执行全量数据同步 ▼▼▼
                if isSameInstance then
                    C_Timer.After(1.5, function()
                        if ns.Segments then
                            -- 1. 同步所有历史段落 (利用保存的 _sessionID 从官方获取最新数据)
                            if ns.Segments.history then
                                for _, seg in ipairs(ns.Segments.history) do
                                    if seg._sessionID then
                                        seg._dataLoaded = false
                                        CT:LoadSegmentData(seg)
                                    end
                                end
                            end

                            -- 2. 同步 Overall：抛弃不准确的快照，基于官方数据完全重建
                            ns.Segments._preReloadOverallData = nil
                            local sessions = C_DamageMeter.GetAvailableCombatSessions()
                            CT:RebuildOverall(sessions, sessions and #sessions or 0)

                            if ns.UI and ns.UI:IsVisible() then ns.UI:Layout() end
                        end
                    end)
                end
                -- ▲▲▲ 新增结束 ▲▲▲

                CT._currentMythicLevel   = 0
                CT._currentMythicMapName = nil
                

                -- ★ 修复：进副本时立刻用所有可用 API 尝试获取真实副本名
                --   GetRealZoneText() 在进副本后通常立刻可用，比 GetInstanceInfo() 更准确
                --   同时1s后再更新一次作为保险，此时地图数据肯定已完全加载
                local function tryGetInstanceName()
                    local name = GetRealZoneText()
                    -- GetRealZoneText 返回的是真实副本名（如L["水闸行动"]），不是大陆名
                    -- 如果它返回的和 GetZoneText 一样说明还没切换，用 GetInstanceInfo 兜底
                    if not name or name == "" or name == GetZoneText() then
                        name = rawName
                    end
                    return name
                end

                CT._currentInstanceName = tryGetInstanceName()

                -- 1s后再更新一次，确保地图数据完全加载后的准确名称
                C_Timer.After(1, function()
                    if ns.state.isInInstance then
                        CT._currentInstanceName = tryGetInstanceName()
                    end
                end)

                -- 进副本4s后重置暴雪meter
                -- ★ 修复：只有进入全新副本时，才强制重置数据。同副本重载已交给上面的全量同步处理。
                if (not CT._wasInInstance or isExitingInstance) and not isSameInstance then
                    C_Timer.After(4, function()
                        if ns.state.isInInstance and not ns.state.inCombat then
                            -- 全新的副本，强制清空可能残留的历史快照并重置底层
                            if ns.Segments then
                                ns.Segments._preReloadOverallData = nil
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

            CT._wasInInstance = inInstance
            CT._bossSessionIndices = CT._bossSessionIndices or {}

            C_Timer.After(0.5, function()
                if not ns.state.inCombat
                   and ns.Segments
                   and #(ns.Segments.history or {}) > 0
                   and (ns.Segments.viewIndex == nil or ns.Segments.viewIndex == 0) then
                    ns.Segments.viewIndex = 1
                    if ns.UI and ns.UI:IsVisible() then
                        C_Timer.After(0, function() ns.UI:Layout() end)
                    end
                end
            end)

        elseif event == "PLAYER_REGEN_DISABLED" then
            if ns.Segments and ns.Segments.viewIndex and ns.Segments.viewIndex ~= 0 then
                ns.Segments.viewIndex = nil
            end
            
            -- ★ 核心修复：利用 CT._wasInInstance 抓取过图读条的瞬间
            -- 如果当前不在副本，但上一帧在副本，说明现在正处于出本的加载屏幕中！
            local isTransitioningOut = (CT._wasInInstance and not ns.state.isInInstance)
            local isExiting = (CT._exitingInstanceTag ~= nil) or (CT._pendingMergeArgs ~= nil) or isTransitioningOut
            
            -- 加入了 CT._lastProcessedCount == 0 的条件，防止连续战斗错误推移 baseline
            if not ns.state.isInInstance and CT._baselineSessionCount == 0 and CT._lastProcessedCount == 0 and not isExiting then
                local ss = C_DamageMeter.GetAvailableCombatSessions()
                local sc = ss and #ss or 0
                if sc > 0 then
                    local lastDur = ss[sc].durationSeconds or 0
                    local offset = (lastDur < 2) and 1 or 0
                    CT._baselineSessionCount = math.max(0, sc - offset)
                    CT._lastProcessedCount   = math.max(0, sc - offset)
                end
            end
            
            if not ns.state.inCombat then
                ns.state.combatStartTime = GetTime()
                ns:EnterCombat()
            end

        elseif event == "PLAYER_REGEN_ENABLED" then
            if ns.state.inCombat then
                ns.state.combatStartTime = 0
                syncCombatState()
            end
        end
    end)

    -- 初始化副本状态
    do
        local rawName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        CT._wasInInstance = ns.state.isInInstance
        if ns.state.isInInstance then
            CT._currentInstanceTag  = string.format("%s|%d", rawName or "Unknown", instanceID or 0)
            CT._currentInstanceName = nil
            C_Timer.After(1, function()
                if ns.state.isInInstance then
                    CT._currentInstanceName = GetRealZoneText() or rawName
                end
            end)
        end
        CT._bossSessionIndices = {}
    end
end

-- ============================================================
-- Sessions 专项诊断（/ldcs sessions）
-- ============================================================
function CT:DebugSessions()
    print(L["=== [LD Stats] Sessions 诊断 ==="])
    print(string.format("  baseline=%d  lastProcessed=%d  inCombat=%s  isInInstance=%s",
        CT._baselineSessionCount, CT._lastProcessedCount,
        tostring(ns.state.inCombat), tostring(ns.state.isInInstance)))

    local sessions = C_DamageMeter.GetAvailableCombatSessions()
    local n = sessions and #sessions or 0
    print(string.format(L["  GetAvailableCombatSessions: %d 条"], n))

    for i, s in ipairs(sessions or {}) do
        local secret = isSessionStillSecret(s.sessionID)
        print(string.format("    [%d] id=%-4d dur=%-6s secret=%-5s name=%s",
            i, s.sessionID,
            tostring(s.durationSeconds),
            tostring(secret),
            tostring(s.name)))
    end

    local segs = ns.Segments
    print(string.format(L["  history: %d 条"], segs and #segs.history or 0))
    for i, seg in ipairs(segs and segs.history or {}) do
        print(string.format("    [%d] %s  dmg=%d  heal=%d  dur=%.1f",
            i, seg.name or "?", seg.totalDamage, seg.totalHealing, seg.duration or 0))
    end
end

-- ============================================================
-- API Debug（/ldcs debug）
-- ============================================================
function CT:DebugAPI()
    print("=== [LD Stats] API Debug ===")
    print("  inCombat:", ns.state.inCombat)
    print("  updateCount:", CT._updateCount)
    print("  baseline:", CT._baselineSessionCount)
    print("  lastProcessed:", CT._lastProcessedCount)
    print("  issecretvalue:", issecretvalue ~= nil)
    print("  AbbreviateNumbers:", AbbreviateNumbers ~= nil)

    local sessions = C_DamageMeter.GetAvailableCombatSessions()
    print("  sessions:", sessions and #sessions or 0)
    if sessions then
        for i, s in ipairs(sessions) do
            print(string.format("    [%d] id=%d dur=%s name=%s",
                i, s.sessionID, tostring(s.durationSeconds), tostring(s.name)))
        end
    end

    local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone)
    if ok and s then
        print("  Current session sources:", s.combatSources and #s.combatSources or 0)
        print("  maxAmount:", s.maxAmount)
        print("  durationSeconds:", s.durationSeconds)
        if s.combatSources and #s.combatSources > 0 then
            local src = s.combatSources[1]
            print("  [1] name:", src.name)
            print("  [1] totalAmount:", src.totalAmount)
            print("  [1] classFilename:", src.classFilename)
            if issecretvalue then
                print("  [1] name isSecret:", issecretvalue(src.name))
                print("  [1] amount isSecret:", issecretvalue(src.totalAmount))
            end
        end
    else
        print("  Current session: nil or error")
    end

    local ok2, sh = pcall(C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.HealingDone)
    if ok2 and sh then
        print("  HealingDone sources:", sh.combatSources and #sh.combatSources or 0)
    end

    -- Deaths debug
    local ok3, sd = pcall(C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.Deaths)
    if ok3 and sd and sd.combatSources then
        print("  Deaths sources:", #sd.combatSources)
        for j, src in ipairs(sd.combatSources) do
            print(string.format("    [%d] name=%s deaths=%s recapID=%s",
                j, tostring(src.name), tostring(src.totalAmount), tostring(src.deathRecapID)))
        end
    end
end