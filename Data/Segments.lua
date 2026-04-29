--[[
    LD Combat Stats - Segments.lua
    段落管理系统
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

function Segments:NewPlayerData(guid, name, class)
    local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
    local specID = cache.specID
    
    -- ★ 核心修复：如果是玩家自己，直接获取当前实时专精，确保战斗记录中绝对准确
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
        specID = specID,              -- ★ 新增
        specIconID = nil, 
        ilvl   = cache.ilvl or 0,     -- ★ 新增
        score  = cache.score or 0,    -- ★ 新增

        damage      = 0, healing     = 0, overhealing = 0, absorbed    = 0, damageTaken = 0,
        deaths      = 0, interrupts  = 0, dispels     = 0,

        spells          = {},
        pets            = {},
        interruptSpells = {},
        dispelSpells    = {},
        damageTakenSpells = {}, -- ★ 新增

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
    self.viewIndex   = nil
    self.bossActive  = false
    self.currentBoss = nil
    self._locked     = false  -- 战斗中禁止切换 session
    self._preReloadOverallData = nil
end

function Segments:ResetAll()
    self:Init()
    self._preReloadOverallData = nil

    if ns.db then
        ns.db.savedHistory       = nil
        ns.db.savedOverall       = nil
        ns.db.savedBaseline      = nil
        ns.db.savedLastProcessed = nil
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
    -- 只有当前停在 current（viewIndex=nil）时才自动跳到新 current
    -- 如果用户手动切到了总计或历史，保持不动
    if self.viewIndex ~= 0 and not (self.viewIndex and self.history[self.viewIndex]) then
        self.viewIndex = nil
    end
    self._locked   = true   -- 战斗中锁定历史 session
end

function Segments:OnCombatEnd()
    if not self.current then return end
    self._locked = false
    self.current.isActive = false
    self.current = nil
    if ns.DeathTracker then ns.DeathTracker:ClearBuffers() end
    if ns.Analysis then ns.Analysis:InvalidateCache() end
end

function Segments:OnEncounterStart(encounterID, name, difficultyID, groupSize)
    self.bossActive  = true
    self.currentBoss = {
        id         = encounterID,
        name       = name,
        difficulty = difficultyID,
        groupSize  = groupSize,
    }
    ns.state.lastCombatWasBoss = true  -- 标记当前战斗是 boss 战

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
    -- lastCombatWasBoss 保留到 processArchivedSessions 读取后再清除
end

-- ============================================================
-- 段落数据访问
-- ============================================================
function Segments:GetViewSegment()
    local seg
    if self.viewIndex == 0 then
        seg = self.overall
    elseif self.viewIndex and self.history[self.viewIndex] then
        seg = self.history[self.viewIndex]
    else
        seg = self.current or self.history[1] or self.overall
    end

    -- 懒加载：只有用户实际查看到的段才加载完整数据
    if seg and seg._sessionID and not seg._dataLoaded then
        if ns.CombatTracker then
            ns.CombatTracker:LoadSegmentData(seg)
        end
    end

    return seg
end

function Segments:GetOverallSegment()
    return self.overall
end

function Segments:GetCurrentSegment()
    return self.current
end

function Segments:SetViewSegment(index)
    self.viewIndex = index
    if ns.UI then ns.UI:Refresh() end
end

function Segments:CycleSegment(direction)
    local maxIdx = #self.history
    if not self.viewIndex then
        self.viewIndex = direction > 0 and 0 or (maxIdx > 0 and 1 or 0)
    elseif self.viewIndex == 0 then
        self.viewIndex = direction > 0 and (maxIdx > 0 and 1 or nil) or nil
    else
        local newIdx = self.viewIndex + direction
        if newIdx < 1 then
            self.viewIndex = 0
        elseif newIdx > maxIdx then
            self.viewIndex = nil
        else
            self.viewIndex = newIdx
        end
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
-- 获取/创建玩家数据
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
-- 记录承伤
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

-- ============================================================
-- 记录死亡 / 打断 / 驱散
-- ============================================================
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


-- ============================================================
-- 宠物名称延迟更新
-- ============================================================
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
-- 历史列表接口 (按时间顺序排列：最旧 -> 最新 -> 当前 -> 总计)
-- ============================================================
function Segments:GetHistoryList()
    local list = {}

    -- 1. 历史记录：最旧的在最上面，最新的紧挨着“当前”
    local maxSeg = ns.db and ns.db.tracking and ns.db.tracking.maxSegments or 30
    local limit = math.min(#self.history, maxSeg)

    -- 从 limit 开始倒着遍历（不展示 limit 之后隐藏的记录）
    for i = limit, 1, -1 do
        local seg = self.history[i]
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
        table.insert(list, { key = "history", index = i, seg = seg, label = label })
    end

    -- 2. 当前：放在历史记录的正下方
    local currentLabel
    if self.current and self.current.isActive then
        currentLabel = L["|cff00ff00> 当前战斗|r"]
    else
        currentLabel = L["|cff666666* 当前|r"]
    end
    table.insert(list, {
        key       = "current",
        index     = nil,
        seg       = self.current,
        label     = currentLabel,
        isCurrent = true,
    })

    -- 3. 总计：永远垫底
    table.insert(list, {
        key = "overall", index = 0, seg = self.overall,
        label = L["|cffaaaaaa* 总计|r"],
    })

    return list
end

function Segments:SetViewByKey(key, index)
    if key == "current" then self.viewIndex = nil
    elseif key == "overall" then self.viewIndex = 0
    elseif key == "history" then self.viewIndex = index end
    if ns.Analysis then ns.Analysis:InvalidateCache() end
    if ns.UI then ns.UI:Refresh() end
end

function Segments:GetViewKey()
    if self.viewIndex == nil then return "current", nil
    elseif self.viewIndex == 0 then return "overall", nil
    else return "history", self.viewIndex end
end