--[[
    LD Combat Stats - Segments.lua
    段落管理系统

    ★ 改造说明 (虚拟段架构):
    - history 数组仅存已归档段。每个已归档段在创建时分配 _localID。
    - 暴雪 API 现存的 sessions 不进 history,UI 渲染时通过 GetHistoryList 实时拼成
      虚拟段 (_isVirtual=true, 携带 _sessionID),数据每次现读 API。
    - viewIndex 改为 key 存储:
        nil                                       -> 实时 current
        { kind="overall" }                        -> 总计
        { kind="archived", localID="..." }        -> 已归档段
        { kind="virtual",  sessionID=N }          -> 暴雪 API 虚拟段
    - 黑名单 (LightDamageDB.hiddenSessionIDs / hiddenLocalIDs) 在 GetHistoryList
      构建合并列表时过滤。
]]

local addonName, ns = ...
local L = ns.L

local Segments = {}
ns.Segments = Segments

-- ============================================================
-- 数据结构
-- ============================================================
function Segments:NewSegment(segType, name)
    return {
        type      = segType,
        name      = name or segType,
        startTime = GetTime(),
        endTime   = 0,
        duration  = 0,
        isActive  = true,
        _realTime = time(),

        players = {},

        totalDamage      = 0,
        totalHealing     = 0,
        totalDamageTaken = 0,

        encounterID   = nil,
        encounterName = nil,
        difficultyID  = nil,
        success       = nil,

        deathLog = {},
        enemyDamageTakenList = {},
    }
end

-- ★ 给已归档段分配本地唯一 ID。同一会话内单调递增,跨会话用时间戳兜底。
local _localIDCounter = 0
function Segments:GenLocalID(prefix)
    _localIDCounter = _localIDCounter + 1
    return string.format("%s_%d_%d", prefix or "arch", time(), _localIDCounter)
end

function Segments:NewPlayerData(guid, name, class)
    local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
    local specID = cache.specID

    -- ★ 核心修复:如果是玩家自己,直接获取当前实时专精
    if guid == ns.state.playerGUID then
        local specIdx = GetSpecialization()
        if specIdx then
            specID = GetSpecializationInfo(specIdx)
        end
    end

    return {
        guid   = guid,
        name   = ns:ShortName(name) or "?",
        class  = class or (ns:IsNPCGUID(guid) and "NPC" or "WARRIOR"),
        specID = specID,
        specIconID = nil,
        ilvl   = cache.ilvl or 0,
        score  = cache.score or 0,

        damage      = 0, healing     = 0, overhealing = 0, absorbed    = 0, damageTaken = 0,
        deaths      = 0, interrupts  = 0, dispels     = 0,

        spells          = {},
        pets            = {},
        interruptSpells = {},
        dispelSpells    = {},
        damageTakenSpells = {},

        activeTime     = 0, lastActionTime = 0,
    }
end

function Segments:NewSpellData(spellID, spellName, school)
    return {
        id          = spellID,
        name        = spellName or "?",
        school      = school or 1,
        damage      = 0,
        healing     = 0,
        overhealing = 0,
        hits        = 0,
        crits       = 0,
        misses      = 0,
        maxHit      = 0,
        minHit      = 999999999,
        absorbed    = 0,
    }
end

-- ============================================================
-- 初始化
-- ============================================================
function Segments:Init()
    self.overall     = self:NewSegment("overall", L["总计"])
    self.current     = nil
    self.history     = {}
    self.viewIndex   = nil   -- ★ 现在是 nil 或 table {kind=..., localID/sessionID=...}
    self.bossActive  = false
    self.currentBoss = nil
    self._locked     = false
    self._preReloadOverallData = nil
end

-- ============================================================
-- ★ View key 判定/设置 helper
-- ============================================================
function Segments:IsViewingCurrent()
    return self.viewIndex == nil
end

function Segments:IsViewingOverall()
    return type(self.viewIndex) == "table" and self.viewIndex.kind == "overall"
end

function Segments:IsViewingArchived()
    return type(self.viewIndex) == "table" and self.viewIndex.kind == "archived"
end

function Segments:IsViewingVirtual()
    return type(self.viewIndex) == "table" and self.viewIndex.kind == "virtual"
end

function Segments:ViewCurrent()
    self.viewIndex = nil
end

function Segments:ViewOverall()
    self.viewIndex = { kind = "overall" }
end

function Segments:ViewArchived(localID)
    if not localID then return end
    self.viewIndex = { kind = "archived", localID = localID }
end

function Segments:ViewVirtual(sessionID)
    if not sessionID then return end
    self.viewIndex = { kind = "virtual", sessionID = sessionID }
end

-- ============================================================
-- ★ 脱战时选择最新一条 HistoryList 里的战斗
--   包括 archived / virtual，并且会自动尊重隐藏黑名单
-- ============================================================
function Segments:ViewLatestHistory()
    local merged = self:GetMergedSegmentList()
    local latest = merged and merged[1]

    if latest then
        if latest._isVirtual and latest._sessionID then
            self:ViewVirtual(latest._sessionID)
            return true
        elseif latest._localID then
            self:ViewArchived(latest._localID)
            return true
        end
    end

    self:ViewCurrent()
    return false
end

function Segments:ResetAll()
    self:Init()
    self._preReloadOverallData = nil

    if ns.db then
        ns.db.savedHistory       = nil
        ns.db.savedOverall       = nil
        ns.db.savedBaseline      = nil
        ns.db.savedLastProcessed = nil
        -- ★ Reset 时清空黑名单
        ns.db.hiddenSessionIDs   = {}
        ns.db.hiddenLocalIDs     = {}
    end

    if ns.Analysis then
        ns.Analysis:InvalidateCache()
    end

    if ns.DeathTracker then
        ns.DeathTracker:ClearBuffers()
    end

    wipe(ns.PlayerInfoCache)

    if ns.DetailView then
        ns.DetailView._lastRenderArgs = nil
        if ns.DetailView.frame and ns.DetailView.frame:IsShown() then
            ns.DetailView.frame:Hide()
        end
    end

    if ns.CombatTracker then
        ns.CombatTracker:MarkReset()
        ns.CombatTracker._bossSessionIndices = {}
    end

    if ns.HistoryList and ns.HistoryList._histItems then
        for _, item in ipairs(ns.HistoryList._histItems) do
            item.data = nil
        end
    end

    if ns.UI then
        local function wipeBars(bars)
            if not bars then return end
            for _, bar in ipairs(bars) do
                bar._data     = nil
                bar._apiData  = nil
                bar._guid     = nil
                bar._nameStr  = nil
                bar._classStr = nil
                bar._mode     = nil
                bar._isDeath  = false
            end
        end
        wipeBars(ns.UI.priBars)
        wipeBars(ns.UI.secBars)
        wipeBars(ns.UI.ovrPriBars)
        wipeBars(ns.UI.ovrSecBars)
        ns.UI._sessionCache = {}
        ns.UI:Refresh()
    end
end

-- ============================================================
-- 战斗生命周期
-- ============================================================
function Segments:OnCombatStart()
    if self.current and self.current.isActive then return end

    if ns.DeathTracker and ns.DeathTracker.ClearBuffers then
        ns.DeathTracker:ClearBuffers()
    end

    local zone    = GetZoneText() or ""
    local segName = zone

    if ns.state.inMythicPlus and self.bossActive then
        segName = self.currentBoss and self.currentBoss.name or "Boss"
    end

    self.current   = self:NewSegment("current", segName)

    -- ★ 战斗开始时如果用户停在 archived/virtual 段则不动,
    --   只在用户没主动选(viewIndex == nil)或选着 overall 时切回 current
    if self:IsViewingCurrent() or self:IsViewingOverall() then
        self:ViewCurrent()
    end

    self._locked   = true
end

function Segments:OnCombatEnd()
    if not self.current then return end
    self._locked = false
    self.current.isActive = false
    self.current.endTime  = GetTime()

    if self.current.startTime and self.current.startTime > 0 then
        self.current.duration = self.current.endTime - self.current.startTime
    end

    if ns.DeathTracker then ns.DeathTracker:ClearBuffers() end
    if ns.Analysis then ns.Analysis:InvalidateCache() end

    --   延迟一帧，让暴雪 API session 列表先稳定下来
    C_Timer.After(0, function()
        if not ns.state.inCombat and ns.Segments then
            ns.Segments:ViewLatestHistory()
            if ns.Analysis then ns.Analysis:InvalidateCache() end
            if ns.UI and ns.UI:IsVisible() then
                ns.UI:Refresh()
            end
        end
    end)
end

function Segments:OnEncounterStart(encounterID, name, difficultyID, groupSize)
    self.bossActive  = true
    self.currentBoss = {
        id         = encounterID,
        name       = name,
        difficulty = difficultyID,
        groupSize  = groupSize,
    }
    ns.state.lastCombatWasBoss = true

    if ns.state.inMythicPlus and ns.db.mythicPlus.autoSegment then
        if self.current then
            self.current.type          = "boss"
            self.current.name          = name or "Boss"
            self.current.encounterID   = encounterID
            self.current.encounterName = name
            self.current.difficultyID  = difficultyID
        end
    end
end

function Segments:OnEncounterEnd(encounterID, name, difficultyID, groupSize, success)
    self.bossActive = false
    if self.current then
        self.current.success       = (success == 1)
        self.current.encounterName = name
    end
    self.currentBoss = nil
end

-- ============================================================
-- ★ 黑名单查询
-- ============================================================
local function isSessionIDHidden(sid)
    return sid and ns.db and ns.db.hiddenSessionIDs and ns.db.hiddenSessionIDs[sid] == true
end

local function isLocalIDHidden(lid)
    return lid and ns.db and ns.db.hiddenLocalIDs and ns.db.hiddenLocalIDs[lid] == true
end

-- ============================================================
-- ★ 虚拟段构建
--   返回当前暴雪 API 中所有 session 的轻量段对象,过滤掉:
--   - 已经归档进 history 的 sessionID
--   - 在黑名单里的 sessionID
--   - 时长不足 minCombatTime 的(用户配置项)
--   注:这里不读 session 数据,只构建元信息壳。数据由 UI 走 API 路径现读。
-- ============================================================
function Segments:BuildVirtualSegments()
    if not C_DamageMeter or not C_DamageMeter.GetAvailableCombatSessions then
        return {}
    end

    local sessions = C_DamageMeter.GetAvailableCombatSessions()
    if not sessions or #sessions == 0 then return {} end

    -- 收集 history 中所有已归档段的 sessionID(归档段的原始来源)
    local archivedSIDs = {}
    for _, seg in ipairs(self.history) do
        if seg._sessionID then
            archivedSIDs[seg._sessionID] = true
        end
    end

    local minDur = (ns.db and ns.db.tracking and ns.db.tracking.minCombatTime) or 2
    local result = {}

    -- ★ 战斗中,GetAvailableCombatSessions 的最后一项是正在进行的 live session,
    --   它已经被底部"当前战斗"常驻项覆盖,不要在虚拟段列表里重复显示。
    local liveIdx = ns.state.inCombat and #sessions or nil

    for i, s in ipairs(sessions) do
        local sid = s.sessionID
        local dur = s.durationSeconds or 0

        local skip = false
        if i == liveIdx then skip = true end               -- 战斗中的 live session
        if archivedSIDs[sid] then skip = true end          -- 已经归档过
        if isSessionIDHidden(sid) then skip = true end     -- 用户黑名单
        if dur > 0 and dur < minDur then skip = true end   -- 时长太短

        if not skip then
            local now = GetTime()
            local seg = {
                type      = "virtual",
                name      = s.name or GetZoneText() or "Combat",
                _isVirtual = true,
                _sessionID = sid,
                _sessionIdx = i,
                duration  = dur,
                startTime = (dur > 0) and (now - dur) or now,
                endTime   = now,
                isActive  = false,
                _realTime = time() - math.floor(dur or 0),
                -- 数据相关字段为空,UI 走 API 路径现读
                players = {},
                totalDamage = 0, totalHealing = 0, totalDamageTaken = 0,
                deathLog = {},
                enemyDamageTakenList = {},
            }
            table.insert(result, seg)
        end
    end

    return result
end

-- ★ 把已归档段和虚拟段合并成"按时间倒序"的统一列表
--   (最新在前;current/overall 不在内)
function Segments:GetMergedSegmentList()
    local merged = {}

    -- 虚拟段（最新的在前，因为是按 sessionID 倒序拼的）
    local virtuals = self:BuildVirtualSegments()
    for i = #virtuals, 1, -1 do
        table.insert(merged, virtuals[i])
    end

    -- 已归档段（history 数组本身就是新→旧）
    for _, seg in ipairs(self.history) do
        if not isLocalIDHidden(seg._localID) then
            table.insert(merged, seg)
        end
    end

    return merged
end

-- ============================================================
-- ★ 段落数据访问
-- ============================================================
function Segments:GetViewSegment()
    -- 实时
    if self:IsViewingCurrent() then
        local seg = self.current
        if not seg then
            -- 没有当前战斗时,退回到合并列表第一项或 overall
            local merged = self:GetMergedSegmentList()
            seg = merged[1] or self.overall
        end
        return seg
    end

    -- 总计
    if self:IsViewingOverall() then
        return self.overall
    end

    -- 已归档(按 localID 反查)
    if self:IsViewingArchived() then
        local lid = self.viewIndex.localID
        for _, seg in ipairs(self.history) do
            if seg._localID == lid then
                -- 懒加载兜底:旧逻辑,继续保留。但虚拟段架构下绝大多数 archived 段
                -- 在归档时已加载完毕,这条路径很少触发。
                if seg._sessionID and (not seg._dataLoaded or (seg.totalDamage or 0) == 0) then
                    if ns.CombatTracker then
                        ns.CombatTracker:LoadSegmentData(seg)
                    end
                end
                return seg
            end
        end
        -- 反查失败:段已被裁剪/删除,退回 current
        self:ViewCurrent()
        return self.current or self.overall
    end

    -- 虚拟段(按 sessionID 反查)
    if self:IsViewingVirtual() then
        local sid = self.viewIndex.sessionID
        local merged = self:GetMergedSegmentList()
        for _, seg in ipairs(merged) do
            if seg._isVirtual and seg._sessionID == sid then
                return seg
            end
        end
        -- 反查失败:虚拟段消失了(被归档/被清/被隐藏),退回 current
        self:ViewCurrent()
        return self.current or self.overall
    end

    -- 兜底
    return self.current or self.overall
end

function Segments:GetOverallSegment()
    return self.overall
end

function Segments:GetCurrentSegment()
    return self.current
end

function Segments:SetViewSegment(viewKey)
    -- 兼容旧调用:有些地方传数字,有些传 key table
    -- 旧 0 → overall;旧 nil → current;旧 number → archived 第 N 项(尽力而为)
    if viewKey == nil then
        self:ViewCurrent()
    elseif viewKey == 0 then
        self:ViewOverall()
    elseif type(viewKey) == "number" then
        local seg = self.history[viewKey]
        if seg and seg._localID then
            self:ViewArchived(seg._localID)
        else
            self:ViewCurrent()
        end
    elseif type(viewKey) == "table" then
        self.viewIndex = viewKey
    end
    if ns.UI then ns.UI:Refresh() end
end

-- ★ CycleSegment 在合并列表上循环
function Segments:CycleSegment(direction)
    local merged = self:GetMergedSegmentList()
    local maxIdx = #merged

    -- 当前位置:0=overall, nil=current, 1..N=合并列表索引
    local curPos
    if self:IsViewingCurrent() then
        curPos = -1   -- 用 -1 代表 current 位
    elseif self:IsViewingOverall() then
        curPos = 0
    else
        curPos = nil
        local target = self:GetViewSegment()
        for i, seg in ipairs(merged) do
            if seg == target then curPos = i; break end
        end
        if not curPos then curPos = -1 end
    end

    local newPos = curPos + direction
    -- 顺序:overall(0) → 合并列表 1..N → current(-1)
    if newPos == 0 then
        self:ViewOverall()
    elseif newPos >= 1 and newPos <= maxIdx then
        local seg = merged[newPos]
        if seg._isVirtual then
            self:ViewVirtual(seg._sessionID)
        else
            self:ViewArchived(seg._localID)
        end
    elseif newPos > maxIdx then
        self:ViewCurrent()
    elseif newPos == -1 then
        self:ViewCurrent()
    else
        -- 越界:跳到 overall
        self:ViewOverall()
    end

    if ns.UI then ns.UI:Refresh() end
end

function Segments:GetViewLabel()
    local seg = self:GetViewSegment()
    if not seg then return L["无数据"] end

    if seg.type == "overall" then
        return L["|cffaaaaaa总计|r"]
    elseif seg.type == "mythicplus" then
        if ns.MythicPlus then return ns.MythicPlus:FormatSegLabel(seg) end
        return seg.name or L["大秘境"]
    elseif seg.type == "boss" then
        local icon = seg.success == true  and "|cff00ff00[Win]|r "
                  or seg.success == false and "|cffff0000[Loss]|r " or ""
        return icon .. (seg.encounterName or seg.name)
    else
        return seg.name or L["当前"]
    end
end

-- ============================================================
-- 获取/创建玩家数据(原样保留)
-- ============================================================
function Segments:GetPlayer(seg, guid, name, flags)
    if not seg or not guid then return nil end

    local pd = seg.players[guid]
    if not pd then
        local classEng
        if ns:IsNPCGUID(guid) then
            classEng = "NPC"
        else
            local ok, _, ce = pcall(GetPlayerInfoByGUID, guid)
            classEng = (ok and ce) or "WARRIOR"
        end
        pd = self:NewPlayerData(guid, name, classEng)
        seg.players[guid] = pd
    end

    if name and not (issecretvalue and issecretvalue(name)) and name ~= "" and name ~= "?" then
        pd.name = ns:ShortName(name)
    end

    return pd
end

-- ============================================================
-- 记录承伤 / 死亡 / 宠物名(原样保留,只用在 CLEU 死亡日志路径)
-- ============================================================
function Segments:RecordDamageTaken(destGUID, destName, destFlags,
        amount, spellID, spellName, school, sourceGUID, sourceName)

    amount = ns:SafeNum(amount)
    if amount <= 0 then return end

    local function writeToSeg(seg)
        if not seg then return end
        local pd = self:GetPlayer(seg, destGUID, destName, destFlags)
        if not pd then return end
        pd.damageTaken       = pd.damageTaken + amount
        seg.totalDamageTaken = seg.totalDamageTaken + amount
    end

    writeToSeg(self.current)
    writeToSeg(self.overall)

    if ns.DeathTracker then
        ns.DeathTracker:RecordIncomingDamage(destGUID, destName, destFlags,
            amount, spellID, spellName, school, sourceGUID, sourceName)
    end
end

function Segments:RecordDeath(destGUID, destName, destFlags)
    local function writeToSeg(seg)
        if not seg then return end
        local pd = self:GetPlayer(seg, destGUID, destName, destFlags)
        if not pd then return end
        pd.deaths = pd.deaths + 1
    end
    writeToSeg(self.current)
    writeToSeg(self.overall)
end

function Segments:UpdatePetName(ownerGUID, petGUID, petName)
    if not petName or petName == "" then return end
    local shortName = ns:ShortName(petName)

    local function updateInSeg(seg)
        if not seg then return end
        local pd = seg.players[ownerGUID]
        if pd and pd.pets[petGUID] then
            pd.pets[petGUID].name = shortName
        end
    end
    updateInSeg(self.current)
    updateInSeg(self.overall)
end

-- ============================================================
-- 历史列表接口 - 由 HistoryList 渲染
-- 返回顺序:历史(最旧 → 最新) + current + overall
-- 历史部分 = 已归档段 + 虚拟段(都按时间倒序;最旧在最上面)
-- ============================================================
function Segments:GetHistoryList()
    local list = {}

    local merged = self:GetMergedSegmentList()
    local maxSeg = ns.db and ns.db.tracking and ns.db.tracking.maxSegments or 30

    -- 注意:合并列表是"最新→最旧"(因为 sort 用 ae > be)。
    -- 渲染上是"最旧 → 最新 → 当前 → 总计",所以倒着遍历。
    -- 截取规则:只展示前 maxSeg 个(以"最新优先"裁剪)。
    local limit = math.min(#merged, maxSeg)

    for i = limit, 1, -1 do
        local seg = merged[i]
        local label
        if seg.type == "mythicplus" then
            label = ns.MythicPlus and ns.MythicPlus:FormatSegLabel(seg) or seg.name
        elseif seg.type == "boss" then
            local icon = seg.success == true  and "|cff00ff00[Win]|r "
                      or seg.success == false and "|cffff4444[Loss]|r " or ""
            label = icon .. (seg.encounterName or seg.name or "Boss")
        else
            label = seg.name or L["战斗"]
        end
        local dur = seg.duration or 0
        if dur > 0 then
            label = label .. " |cffaaaaaa" .. ns:FormatTime(dur) .. "|r"
        end

        local entry = { seg = seg, label = label }
        if seg._isVirtual then
            entry.key       = "virtual"
            entry.sessionID = seg._sessionID
        else
            entry.key       = "archived"
            entry.localID   = seg._localID
        end
        table.insert(list, entry)
    end

    -- current
    local currentLabel
    if self.current and self.current.isActive then
        currentLabel = L["|cff00ff00> 当前战斗|r"]
    else
        currentLabel = L["|cff666666* 当前|r"]
    end
    table.insert(list, {
        key       = "current",
        seg       = self.current,
        label     = currentLabel,
        isCurrent = true,
    })

    -- overall
    table.insert(list, {
        key   = "overall",
        seg   = self.overall,
        label = L["|cffaaaaaa* 总计|r"],
    })

    return list
end

-- ★ HistoryList 点击时调用:不再用 (key, index),改用 entry table
--    但旧签名 (key, index) 仍兼容(在 HistoryList 里改成传 entry)
function Segments:SetViewByKey(key, idOrIndex)
    if key == "current" then
        self:ViewCurrent()
    elseif key == "overall" then
        self:ViewOverall()
    elseif key == "archived" then
        self:ViewArchived(idOrIndex)   -- idOrIndex = localID
    elseif key == "virtual" then
        self:ViewVirtual(idOrIndex)    -- idOrIndex = sessionID
    elseif key == "history" then
        -- 旧调用兼容:idOrIndex 是数字 index
        local seg = self.history[idOrIndex]
        if seg and seg._localID then
            self:ViewArchived(seg._localID)
        else
            self:ViewCurrent()
        end
    end
    if ns.Analysis then ns.Analysis:InvalidateCache() end
    if ns.UI then ns.UI:Refresh() end
end

function Segments:GetViewKey()
    if self:IsViewingCurrent() then return "current", nil end
    if self:IsViewingOverall() then return "overall", nil end
    if self:IsViewingArchived() then return "archived", self.viewIndex.localID end
    if self:IsViewingVirtual() then return "virtual", self.viewIndex.sessionID end
    return "current", nil
end

-- ============================================================
-- ★ 黑名单操作
-- ============================================================
function Segments:HideSession(entry)
    if not entry then return end
    if not ns.db then return end
    if entry.key == "virtual" and entry.sessionID then
        ns.db.hiddenSessionIDs = ns.db.hiddenSessionIDs or {}
        ns.db.hiddenSessionIDs[entry.sessionID] = true
    elseif entry.key == "archived" and entry.localID then
        ns.db.hiddenLocalIDs = ns.db.hiddenLocalIDs or {}
        ns.db.hiddenLocalIDs[entry.localID] = true
    end

    -- 如果当前正在看这个段,自动跳走
    if entry.key == "virtual" and self:IsViewingVirtual() and self.viewIndex.sessionID == entry.sessionID then
        self:ViewLatestHistory()
    elseif entry.key == "archived" and self:IsViewingArchived() and self.viewIndex.localID == entry.localID then
        self:ViewLatestHistory()
    end

    if ns.Analysis then ns.Analysis:InvalidateCache() end
end

-- ★ ResetAllCombatSessions 后调用,清掉 sessionID 黑名单(那些 ID 都失效了)
function Segments:ClearHiddenSessionIDs()
    if ns.db then
        ns.db.hiddenSessionIDs = {}
    end
end

-- ★ SmartTrimHistory 调用:已归档段被裁了之后,清理孤儿 localID 黑名单条目
function Segments:GCHiddenLocalIDs()
    if not ns.db or not ns.db.hiddenLocalIDs then return end
    local alive = {}
    for _, seg in ipairs(self.history) do
        if seg._localID then alive[seg._localID] = true end
    end
    for lid in pairs(ns.db.hiddenLocalIDs) do
        if not alive[lid] then ns.db.hiddenLocalIDs[lid] = nil end
    end
end

-- ★ 归档时迁移黑名单:虚拟段 sessionID 在 hiddenSessionIDs 里 → 归档段的 localID 加进 hiddenLocalIDs
function Segments:MigrateHideOnArchive(seg)
    if not seg or not seg._localID then return end
    if not ns.db then return end
    local sid = seg._sessionID
    if sid and ns.db.hiddenSessionIDs and ns.db.hiddenSessionIDs[sid] then
        ns.db.hiddenLocalIDs = ns.db.hiddenLocalIDs or {}
        ns.db.hiddenLocalIDs[seg._localID] = true
    end
end