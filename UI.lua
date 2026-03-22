--[[
    LD Combat Stats - UI.lua
    主界面
]]

local addonName, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local BAR_H   = 18
local BAR_GAP = 1
local TITLE_H = 22
local SUMM_H  = 16
local SECTH_H = 18
local TAB_H   = 20
local MAX_BARS = 40

-- ★ 修复：补充原本缺失的颜色表，解决 RefreshHead 报错
local T = {
    dmgC   = {1.0, 0.82, 0.0},
    healC  = {0.4, 1.0, 0.4},
    takenC = {1.0, 0.3, 0.3},
    accent = {0.0, 0.65, 1.0},
}

local MODE_TO_DM = {
    damage      = Enum.DamageMeterType.DamageDone,
    healing     = Enum.DamageMeterType.HealingDone,
    damageTaken = Enum.DamageMeterType.DamageTaken,
    interrupts  = Enum.DamageMeterType.Interrupts,
    dispels     = Enum.DamageMeterType.Dispels,
    deaths      = Enum.DamageMeterType.Deaths,
}
local COUNT_MODES = { deaths=true, interrupts=true, dispels=true }

local function SafeSetMinMax(sb, mn, mx) sb:SetMinMaxValues(mn, mx) end
local function SafeSetValue(sb, val) sb:SetValue(val) end
local function SafeSetText(fs, val) fs:SetText(AbbreviateNumbers(val)) end
local function SafeSetFormattedText(fs, ps, tot) fs:SetFormattedText("%s(%s)", AbbreviateNumbers(ps), AbbreviateNumbers(tot)) end

function UI:FillBg(f, c)
    local t = f:CreateTexture(nil,"BACKGROUND"); t:SetAllPoints()
    t:SetColorTexture(unpack(c)); return t
end

function UI:FS(p, sz, fl)
    local f = p:CreateFontString(nil,"OVERLAY")
    -- ★ 修改这行：
    f:SetFont(STANDARD_TEXT_FONT, sz, fl or "")
    f:SetTextColor(1, 1, 1, 0.93); return f
end

function UI:Btn(p, lbl, sz, fn)
    local b = CreateFrame("Button", nil, p); b:SetSize(18, TITLE_H)
    b.text = self:FS(b, sz, "OUTLINE"); b.text:SetPoint("CENTER")
    b.text:SetText(lbl); b.text:SetTextColor(0.55, 0.55, 0.55)
    b:SetScript("OnClick", fn)
    b:SetScript("OnEnter", function() b.text:SetTextColor(1,1,1) end)
    b:SetScript("OnLeave", function() b.text:SetTextColor(0.55,0.55,0.55) end)
    return b
end

-- 图标按钮：texNormal/texHover 为贴图路径（不含扩展名）
function UI:IconBtn(p, texNormal, texHover, btnW, fn)
    local iconSize = TITLE_H - 6
    local b = CreateFrame("Button", nil, p)
    b:SetSize(btnW or 20, TITLE_H)
    b:EnableMouse(true)

    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetSize(iconSize, iconSize)
    t:SetPoint("CENTER")
    t:SetTexture(texNormal)
    t:SetVertexColor(0.65, 0.65, 0.65, 1)
    b.iconTex   = t
    b.texNormal = texNormal
    b.texHover  = texHover or texNormal

    b:SetScript("OnEnter", function()
        t:SetTexture(b.texHover)
        t:SetVertexColor(1, 1, 1, 1)
    end)
    b:SetScript("OnLeave", function()
        t:SetTexture(b.texNormal)
        t:SetVertexColor(0.65, 0.65, 0.65, 1)
    end)
    b:SetScript("OnClick", fn)
    return b
end

function UI:IsOverallColumnActive()
    if not ns.db or not ns.db.split then return false end 
    if not ns.db.split.showOverall then return false end
    
    local cat = ns.state.instanceCategory or "outdoor"
    if cat == "mplus" and ns.db.split.overallShowMPlus then return true end
    if cat == "raid" and ns.db.split.overallShowRaid then return true end
    if cat == "dungeon" and ns.db.split.overallShowDungeon then return true end
    if cat == "outdoor" and ns.db.split.overallShowOutdoor then return true end
    
    return false
end

function UI:IsSplitActiveInCurrentScene()
    if not ns.db or not ns.db.split then return false end
    if not ns.db.split.enabled then return false end
    
    local cat = ns.state.instanceCategory or "outdoor"
    if cat == "mplus" and ns.db.split.splitShowMPlus then return true end
    if cat == "raid" and ns.db.split.splitShowRaid then return true end
    if cat == "dungeon" and ns.db.split.splitShowDungeon then return true end
    if cat == "outdoor" and ns.db.split.splitShowOutdoor then return true end
    
    return false
end

function UI:ApplyTheme()
    local dbw = ns.db.window
    local tc = dbw.themeColor or {0.08, 0.08, 0.12, 1}
    local bc = dbw.bgColor    or {0.04, 0.04, 0.05, 0.90}

    if self.frame    then self.frame:SetBackdropColor(unpack(bc)) end
    if self.titleBg  then self.titleBg:SetColorTexture(unpack(tc)) end
    if self.tabBg    then self.tabBg:SetColorTexture(unpack(tc)) end
    if self.summBg   then self.summBg:SetColorTexture(tc[1]*0.8, tc[2]*0.8, tc[3]*0.8, tc[4]) end

    local sc = {tc[1]*0.9, tc[2]*0.9, tc[3]*0.9, tc[4]}
    if self.priHead    then self.priHead.bg:SetColorTexture(unpack(sc)) end
    if self.secHead    then self.secHead.bg:SetColorTexture(unpack(sc)) end
    if self.ovrPriHead then self.ovrPriHead.bg:SetColorTexture(unpack(sc)) end
    if self.ovrSecHead then self.ovrSecHead.bg:SetColorTexture(unpack(sc)) end

    -- ★ 右侧容器背景
    if self.ovrContainer then
        local c = dbw.ovrBgColor or {0.02, 0.04, 0.08, 0.95}
        self.ovrContainer:SetBackdropColor(unpack(c))
    end
end

function UI:EnsureCreated() if self.frame then return end; self:Build() end

function UI:Build()
    local db = ns.db.window
    BAR_H = ns.db.display.barHeight or 18

    local f = CreateFrame("Frame","LDStatsFrame",UIParent,"BackdropTemplate")
    f:SetSize(db.width, db.height)
    f:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    f:SetScale(db.scale); f:SetAlpha(db.alpha)
    f:SetFrameStrata("MEDIUM"); f:SetFrameLevel(10)
    f:SetClampedToScreen(true); f:EnableMouse(true)
    f:SetMovable(true); f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(250, 180, 1000, 900) end
    
    f:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile=nil, edgeSize=0 })
    f:SetClipsChildren(true)
    self.frame = f

    self:BuildTitle(); self:BuildMPlusSummary(); self:BuildBody()
    self:BuildTabs(); self:BuildResize(); self:SetupDrag()
    
    self:ApplyTheme()
    f:HookScript("OnSizeChanged", function() self:OnResize() end)
    
    -- ★ 新增：根据保存的可见性状态决定是否显示
    if ns.db.window.visible == false then
        f:Hide()
    else
        f:Show()
        self:Layout()
    end
    
    self:CheckAutoCollapse(true)

    self._lastFontHash = nil
    self._sessionCache = {}

    -- ★ 渐隐系统初始化
    self._faded = false
    self._fadeAnimating = false
    self._wasMouseOver = false

    -- 鼠标悬停检测（OnUpdate 轮询，子控件不会误触）
    local fadeHoverFrame = CreateFrame("Frame")
    fadeHoverFrame._timer = 0
    fadeHoverFrame:SetScript("OnUpdate", function(frame, elapsed)
        -- ★ 性能优化：每 0.1 秒检测一次，而不是每帧
        frame._timer = frame._timer + elapsed
        if frame._timer < 0.1 then return end
        frame._timer = 0

        if not self._faded then return end
        if not ns.db or not ns.db.fade then return end
        if not (ns.db.fade.fadeBars or ns.db.fade.fadeBody) then return end
        if not ns.db.fade.unfadeOnHover then return end
        if not self.frame or not self.frame:IsShown() then return end

        local isOver = self.frame:IsMouseOver()
        if isOver and not self._wasMouseOver then
            self:ApplyFadeAlpha(false, false)
        elseif not isOver and self._wasMouseOver then
            self:CheckAutoFade(true)
        end
        self._wasMouseOver = isOver
    end)
    self._fadeHoverFrame = fadeHoverFrame

    --   解决登录后从未进入战斗时，渐隐永远不生效的问题
    C_Timer.After(0.5, function()
        if self.frame and self.frame:IsShown() and not ns.state.inCombat then
            self:CheckAutoFade(true)
        end
    end)
end

local TEX = "Interface\\AddOns\\LDCombatStats\\Textures\\"

function UI:BuildTitle()
    local b = CreateFrame("Frame", nil, self.frame)
    b:SetHeight(TITLE_H); b:SetPoint("TOPLEFT",0,0); b:SetPoint("TOPRIGHT",0,0)
    self.titleBg = self:FillBg(b, {0.08, 0.08, 0.12, 1})
    self.titleBar = b

    -- [=] 历史列表按钮（保持文字，无需图标）
    local listBtn = self:Btn(b, "[=]", 12, function()
        if ns.HistoryList then ns.HistoryList:Toggle(b) end
    end)
    listBtn:SetPoint("LEFT", 4, 0); listBtn:SetSize(22, TITLE_H)
    self.listBtn = listBtn

    -- 标题文字
    self.titleText = self:FS(b, 10, "OUTLINE")
    self.titleText:SetPoint("LEFT", listBtn, "RIGHT", 4, 0)
    self.titleText:SetPoint("RIGHT", b, "RIGHT", -72, 0)
    self.titleText:SetJustifyH("LEFT"); self.titleText:SetWordWrap(false)

    -- 标题栏整体可拖拽区域
    local titleBtn = CreateFrame("Button", nil, b)
    titleBtn:SetPoint("LEFT", listBtn, "RIGHT", 0, 0)
    titleBtn:SetPoint("RIGHT", b, "RIGHT", -72, 0)
    titleBtn:SetHeight(TITLE_H)
    titleBtn:SetScript("OnClick", function()
        if ns.HistoryList then ns.HistoryList:Toggle(b) end
    end)
    titleBtn:RegisterForDrag("LeftButton")
    titleBtn:SetScript("OnDragStart", function()
        if not ns.db.window.locked then self.frame:StartMoving() end
    end)
    
    titleBtn:SetScript("OnDragStop", function()
        self.frame:StopMovingOrSizing()
        local db = ns.db.window
        
        -- 获取完整的锚点信息
        local point, relativeTo, relPoint, x, y = self.frame:GetPoint()
        
        -- 保存到数据库
        db.point = point
        db.relPoint = relPoint
        db.x = x
        db.y = y
        
        -- ★ 修复：如果处于折叠状态下拖拽，同步更新 _savedAnchor
        -- 这样再次展开时，就会从当前新拖放的位置向下展开，而不会“弹回”老位置
        if self._collapsed then
            self._savedAnchor = { point, relativeTo, relPoint, x, y }
        end
    end)

    -- ★ 折叠/展开 按钮（最右侧，图标切换）
    self._collapsed = false
    local colBtn
    colBtn = self:IconBtn(b,
        TEX .. "btn_collapse",
        TEX .. "btn_collapse",
        20,
        function()
            self:ToggleCollapse(not self._collapsed)
        end
    )

    colBtn:SetPoint("RIGHT", -4, 0)
    self.collapseBtn = colBtn

    -- ★ 设置 按钮
    local cfgBtn = self:IconBtn(b,
        TEX .. "btn_settings",
        TEX .. "btn_settings",
        20,
        function() if ns.Config then ns.Config:Toggle() end end
    )
    cfgBtn:SetPoint("RIGHT", colBtn, "LEFT", -2, 0)
    self.cfgBtn = cfgBtn

    -- ★ 清空 按钮
    local rstBtn = self:IconBtn(b,
        TEX .. "btn_reset",
        TEX .. "btn_reset",
        20,
        function() if ns.Segments then ns.Segments:ResetAll() end end
    )
    rstBtn:SetPoint("RIGHT", cfgBtn, "LEFT", -2, 0)
    self.rstBtn = rstBtn
end

function UI:ToggleCollapse(collapse, skipAnim)
    if collapse == self._collapsed then return end
    self._collapsed = collapse
    
    local db = ns.db.window
    local cdb = ns.db.collapse
    
    local targetHeight = collapse and TITLE_H or (self._savedHeight or db.height)
    local targetAlpha  = collapse and cdb.alpha or db.alpha
    
    if collapse then
        -- 折叠前：保存原锚点，并强制改为 TOPLEFT 保证向上收缩
        self._savedHeight = self.frame:GetHeight()
        self._savedAnchor = { self.frame:GetPoint() }
        
        local left = self.frame:GetLeft()
        local top  = self.frame:GetTop()
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        
        self.collapseBtn.iconTex:SetTexture(TEX .. "btn_expand")
        self.collapseBtn.iconTex:SetVertexColor(0.65, 0.65, 0.65, 1)
        self.collapseBtn.texNormal = TEX .. "btn_expand"
        self.collapseBtn.texHover  = TEX .. "btn_expand"
        
        if self.resizeHandle then self.resizeHandle:Hide() end
    else
        -- 展开时：保持 TOPLEFT 锚点，让它乖乖地从上往下伸展
        self.collapseBtn.iconTex:SetTexture(TEX .. "btn_collapse")
        self.collapseBtn.iconTex:SetVertexColor(0.65, 0.65, 0.65, 1)
        self.collapseBtn.texNormal = TEX .. "btn_collapse"
        self.collapseBtn.texHover  = TEX .. "btn_collapse"
        
        self.bodyFrame:Show()
        self.tabBar:Show()
        if self:IsOverallColumnActive() and (ns.db.mythicPlus and ns.db.mythicPlus.dualDisplay) and ns.state.isInInstance then
            self.summaryBar:Show()
        end
        if self.resizeHandle then self.resizeHandle:Show() end
    end
    
    -- 动画/状态结束后的回调函数
    local function onAnimComplete()
        if self._collapsed then
            self.bodyFrame:Hide()
            self.tabBar:Hide()
            self.summaryBar:Hide()
        else
            -- 展开动画彻底结束后，再恢复原本的锚点，保证排版正常
            self.frame:ClearAllPoints()
            if self._savedAnchor then
                self.frame:SetPoint(unpack(self._savedAnchor))
            end
            self:Layout()
            -- ★ 展开后若脱战，恢复渐隐
            if not ns.state.inCombat then
                C_Timer.After(0.1, function() self:CheckAutoFade(true) end)
            end
        end
    end

    -- ★ 关键修改：如果传入了 skipAnim，则直接跳过动画
    if cdb.enableAnim and not skipAnim then
        self:StartCollapseAnim(targetHeight, targetAlpha, onAnimComplete)
    else
        self.frame:SetHeight(targetHeight)
        self.frame:SetAlpha(targetAlpha)
        onAnimComplete()
    end
end

function UI:StartCollapseAnim(targetHeight, targetAlpha, onComplete)
    if not self.animFrame then
        self.animFrame = CreateFrame("Frame")
    end
    
    local startHeight = self.frame:GetHeight()
    local startAlpha  = self.frame:GetAlpha()
    local duration    = ns.db.collapse.animDuration or 0.5
    local elapsed     = 0
    
    self.animFrame:SetScript("OnUpdate", function(f, dt)
        elapsed = elapsed + dt
        local progress = math.min(elapsed / duration, 1)
        
        -- 线性运动与平滑过渡
        local easeProgress = math.sin(progress * math.pi / 2)
        
        local curHeight = startHeight + (targetHeight - startHeight) * easeProgress
        local curAlpha  = startAlpha + (targetAlpha - startAlpha) * easeProgress
        
        self.frame:SetHeight(curHeight)
        self.frame:SetAlpha(curAlpha)
        
        if progress >= 1 then
            f:SetScript("OnUpdate", nil)
            -- ★ 动画结束后调用回调
            if onComplete then onComplete() end
        end
    end)
end

function UI:CheckAutoCollapse(skipAnim)
    local cdb = ns.db.collapse
    if not cdb then return end
    
    -- 1. 判断是否“必须展开”（优先级最高）
    local mustExpand = false
    
    -- 如果在战斗中，必须展开
    if ns.state.inCombat then 
        mustExpand = true 
    end
    
    -- 如果在副本内，且勾选了“副本中永不折叠”，必须展开
    if cdb.neverInInstance and ns.state.isInInstance then 
        mustExpand = true 
    end

    if mustExpand then
        -- 如果当前是折叠状态，则主动展开
        if self._collapsed then
            self:ToggleCollapse(false, skipAnim)
        end
        return
    end

    -- 2. 否则，脱离了必须展开的环境后，如果开启了自动折叠，就乖乖折叠
    if cdb.autoCollapse then
        if not self._collapsed then
            self:ToggleCollapse(true, skipAnim)
        end
    end
end

-- ============================================================
-- 渐隐系统
-- ============================================================
function UI:CheckAutoFade(force)
    local fdb = ns.db and ns.db.fade
    if not fdb then return end
    if not self.frame or not self.frame:IsShown() then return end

    -- 折叠状态下不处理渐隐
    if self._collapsed then
        if self._faded then
            self._faded = false
            self:ApplyFadeAlpha(false, false)
        end
        return
    end

    local anyFadeEnabled = fdb.fadeBars or fdb.fadeBody
    if not anyFadeEnabled then
        -- 没有任何渐隐开关, 恢复全透明
        if self._faded or force then
            self._faded = false
            self:ApplyFadeAlpha(false, false)
        end
        return
    end

    -- ★ 分别计算两个组件是否应该渐隐
    local shouldFadeBars = false
    if fdb.fadeBars then
        if fdb.barsWhen == "always" then
            shouldFadeBars = true
        else -- "ooc"
            shouldFadeBars = not ns.state.inCombat
        end
        -- 副本中永不隐藏
        if shouldFadeBars and fdb.barsNeverInInstance and ns.state.isInInstance then
            shouldFadeBars = false
        end
    end

    local shouldFadeBody = false
    if fdb.fadeBody then
        if fdb.bodyWhen == "always" then
            shouldFadeBody = true
        else -- "ooc"
            shouldFadeBody = not ns.state.inCombat
        end
        if shouldFadeBody and fdb.bodyNeverInInstance and ns.state.isInInstance then
            shouldFadeBody = false
        end
    end

    -- 鼠标悬停时取消渐隐
    if fdb.unfadeOnHover and self.frame:IsMouseOver() then
        shouldFadeBars = false
        shouldFadeBody = false
    end

    local newFaded = shouldFadeBars or shouldFadeBody
    if newFaded ~= self._faded or force then
        self._faded = newFaded
        self:ApplyFadeAlpha(shouldFadeBars, shouldFadeBody)
    end
end

function UI:ApplyFadeAlpha(shouldFadeBars, shouldFadeBody)
    local fdb = ns.db and ns.db.fade
    if not fdb then return end

    -- 取消正在进行的渐隐动画
    if self._fadeAnimFrame then
        self._fadeAnimFrame:SetScript("OnUpdate", nil)
    end
    self._fadeAnimating = false

    local barsAlpha = shouldFadeBars and fdb.barsAlpha or 1.0
    local bodyAlpha = shouldFadeBody and fdb.bodyAlpha or 1.0

    local barsTargets = {}
    local bodyTargets = {}

    if fdb.fadeBars then
        if self.titleBar then table.insert(barsTargets, self.titleBar) end
        if self.tabBar   then table.insert(barsTargets, self.tabBar)   end
        if self.resizeHandle then table.insert(barsTargets, self.resizeHandle) end  -- ★ 新增

    end
    if fdb.fadeBody then
        if self.bodyFrame   then table.insert(bodyTargets, self.bodyFrame)   end
        if self.summaryBar  then table.insert(bodyTargets, self.summaryBar)  end
    end

    -- 如果没有渐隐目标但需要恢复，也要执行
    if not shouldFadeBars and not shouldFadeBody then
        -- 恢复所有可能被渐隐过的目标
        if self.titleBar   then table.insert(barsTargets, self.titleBar) end
        if self.tabBar     then table.insert(barsTargets, self.tabBar)   end
        if self.resizeHandle then table.insert(barsTargets, self.resizeHandle) end  -- ★ 新增
        if self.bodyFrame  then table.insert(bodyTargets, self.bodyFrame)  end
        if self.summaryBar then table.insert(bodyTargets, self.summaryBar) end
    end

    if #barsTargets == 0 and #bodyTargets == 0 then return end

    if fdb.enableAnim and not self._fadeAnimating then
        self:StartFadeAnim(barsTargets, barsAlpha, bodyTargets, bodyAlpha)
    else
        for _, f in ipairs(barsTargets) do f:SetAlpha(barsAlpha) end
        for _, f in ipairs(bodyTargets) do f:SetAlpha(bodyAlpha) end
    end
end

function UI:StartFadeAnim(barsTargets, barsAlpha, bodyTargets, bodyAlpha)
    if not self._fadeAnimFrame then
        self._fadeAnimFrame = CreateFrame("Frame")
    end

    self._fadeAnimating = true

    -- 记录每个目标的起始 alpha
    local barsStart = {}
    for i, f in ipairs(barsTargets) do barsStart[i] = f:GetAlpha() end
    local bodyStart = {}
    for i, f in ipairs(bodyTargets) do bodyStart[i] = f:GetAlpha() end

    local duration = (ns.db.fade and ns.db.fade.animDuration) or 0.5
    local elapsed = 0

    self._fadeAnimFrame:SetScript("OnUpdate", function(frame, dt)
        elapsed = elapsed + dt
        local progress = math.min(elapsed / duration, 1)
        local ease = math.sin(progress * math.pi / 2)  -- ease-out

        for i, f in ipairs(barsTargets) do
            f:SetAlpha(barsStart[i] + (barsAlpha - barsStart[i]) * ease)
        end
        for i, f in ipairs(bodyTargets) do
            f:SetAlpha(bodyStart[i] + (bodyAlpha - bodyStart[i]) * ease)
        end

        if progress >= 1 then
            frame:SetScript("OnUpdate", nil)
            self._fadeAnimating = false
        end
    end)
end

function UI:BuildMPlusSummary()
    local b = CreateFrame("Frame", nil, self.frame)
    b:SetHeight(SUMM_H); b:SetPoint("TOPLEFT", self.titleBar,"BOTTOMLEFT", 0,0); b:SetPoint("TOPRIGHT", self.titleBar,"BOTTOMRIGHT", 0,0)
    self.summBg = self:FillBg(b, {0.06, 0.06, 0.10, 1})
    self.summText = self:FS(b, 9, "OUTLINE"); self.summText:SetPoint("LEFT",6,0); self.summText:SetPoint("RIGHT",-6,0)
    self.summText:SetJustifyH("LEFT"); self.summText:SetTextColor(0.3, 0.8, 1.0, 0.90)
    b:Hide(); self.summaryBar = b
end

function UI:MakeScrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    sf:SetScrollChild(child)

    local sb = CreateFrame("Slider", nil, sf)
    sb:SetWidth(3); sb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 0); sb:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 0)
    sb:SetOrientation("VERTICAL"); sb:SetMinMaxValues(0,0); sb:SetValue(0)
    
    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(); track:SetColorTexture(0, 0, 0, 0.2)
    
    sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = sb:GetThumbTexture()
    thumb:SetVertexColor(0.4, 0.4, 0.4, 0.8); thumb:SetSize(3, 30)

    sf:SetScript("OnMouseWheel", function(_, delta)
        local cur = sb:GetValue()
        local _, mx = sb:GetMinMaxValues()
        sb:SetValue(math.max(0, math.min(mx, cur - delta * (BAR_H * 2))))
    end)
    sb:SetScript("OnValueChanged", function(_, val) sf:SetVerticalScroll(val) end)

    return { sf = sf, child = child, sb = sb }
end

function UI:BuildBody()
    self.bodyFrame = CreateFrame("Frame", nil, self.frame)
    self.bodyFrame:SetClipsChildren(true)

    self.ovrSepLine = self.bodyFrame:CreateTexture(nil, "ARTWORK")
    self.ovrSepLine:SetWidth(1)
    self.ovrSepLine:SetColorTexture(0, 0, 0, 0.8)
    self.ovrSepLine:Hide()

    -- 左侧容器
    self.leftContainer = CreateFrame("Frame", nil, self.bodyFrame)
    self.leftContainer:SetClipsChildren(true)

    -- ★ 右侧独立容器，有自己的背景
    self.ovrContainer = CreateFrame("Frame", nil, self.bodyFrame, "BackdropTemplate")
    self.ovrContainer:SetClipsChildren(true)
    self.ovrContainer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = nil, edgeSize = 0 })
    local c = ns.db.window.ovrBgColor or {0.02, 0.04, 0.08, 0.95}
    self.ovrContainer:SetBackdropColor(unpack(c))
    self.ovrContainer:Hide()

    -- 左侧：主栏 + 副栏
    self.priHead = self:MakeSectHead(self.leftContainer)
    self.priList = self:MakeScrollArea(self.leftContainer)
    self.priBars = {}
    for i = 1, MAX_BARS do self.priBars[i] = self:MakeBar(self.priList.child, "primary", i) end

    self.secHead = self:MakeSectHead(self.leftContainer)
    self.secList = self:MakeScrollArea(self.leftContainer)
    self.secBars = {}
    for i = 1, MAX_BARS do self.secBars[i] = self:MakeBar(self.secList.child, "secondary", i) end

    -- ★ 右侧：全程栏，父级改为 ovrContainer
    self.ovrPriHead = self:MakeSectHead(self.ovrContainer)
    self.ovrPriList = self:MakeScrollArea(self.ovrContainer)
    self.ovrPriBars = {}
    for i = 1, MAX_BARS do self.ovrPriBars[i] = self:MakeBar(self.ovrPriList.child, "ovrPri", i) end

    self.ovrSecHead = self:MakeSectHead(self.ovrContainer)
    self.ovrSecList = self:MakeScrollArea(self.ovrContainer)
    self.ovrSecBars = {}
    for i = 1, MAX_BARS do self.ovrSecBars[i] = self:MakeBar(self.ovrSecList.child, "ovrSec", i) end

    self._pinnedSelf = {
        pri    = self:MakePinnedSelfBar(self.leftContainer, self.priList.sf,    "primary"),
        sec    = self:MakePinnedSelfBar(self.leftContainer, self.secList.sf,    "secondary"),
        ovrPri = self:MakePinnedSelfBar(self.ovrContainer,  self.ovrPriList.sf, "ovrPri"),
        ovrSec = self:MakePinnedSelfBar(self.ovrContainer,  self.ovrSecList.sf, "ovrSec"),
    }

    -- ★ 滚动钩子：滚动时实时判断固定栏显隐
    local function hookScroll(listObj, listKey)
        local origOnWheel = listObj.sf:GetScript("OnMouseWheel")
        listObj.sf:SetScript("OnMouseWheel", function(frame, delta)
            if origOnWheel then origOnWheel(frame, delta) end
            if self._pinnedSelfCache and self._pinnedSelfCache[listKey] then
                local args = self._pinnedSelfCache[listKey]
                if args.type == "bars" then
                    self:CheckPinnedSelfForBars(listKey, listObj, args.data, args.dur, args.mode, args.count)
                elseif args.type == "api" then
                    self:CheckPinnedSelfForAPI(listKey, listObj, args.sources, args.mode, args.maxAmt, args.sType)
                end
            end
        end)
    end
    hookScroll(self.priList,    "pri")
    hookScroll(self.secList,    "sec")
    hookScroll(self.ovrPriList, "ovrPri")
    hookScroll(self.ovrSecList, "ovrSec")
end

function UI:MakeSectHead(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(SECTH_H)
    h.bg = self:FillBg(h, {0.06, 0.06, 0.08, 0.9})
    h.label = self:FS(h, 9, "OUTLINE"); h.label:SetPoint("LEFT",6,0); h.label:SetJustifyH("LEFT")
    h.info = self:FS(h, 9, "OUTLINE"); h.info:SetJustifyH("RIGHT"); h.info:SetTextColor(0.55, 0.55, 0.55, 0.9)
    local line = h:CreateTexture(nil,"ARTWORK"); line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT",0,0); line:SetPoint("BOTTOMRIGHT",0,0); line:SetColorTexture(0.3,0.3,0.35,0.4)
    return h
end

function UI:MakeBar(parent, section, index)
    local bar = {}
    bar.frame = CreateFrame("Button", nil, parent)
    bar.frame:SetHeight(BAR_H); bar.frame:RegisterForClicks("LeftButtonUp","RightButtonUp"); bar.frame:Hide()

    bar.bg = bar.frame:CreateTexture(nil,"BACKGROUND"); bar.bg:SetAllPoints(); bar.bg:SetColorTexture(0.1, 0.1, 0.12, 0)
    bar.fill = bar.frame:CreateTexture(nil,"BORDER"); bar.fill:SetPoint("TOPLEFT"); bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetTexture("Interface\\Buttons\\WHITE8X8"); bar.fill:SetWidth(1)

    bar.statusbar = CreateFrame("StatusBar", nil, bar.frame)
    bar.statusbar:SetPoint("TOPLEFT"); bar.statusbar:SetPoint("BOTTOMRIGHT")
    bar.statusbar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar.statusbar:SetMinMaxValues(0, 1); bar.statusbar:Hide()

    bar.textFrame = CreateFrame("Frame", nil, bar.frame)
    bar.textFrame:SetAllPoints()
    bar.textFrame:SetFrameLevel(bar.statusbar:GetFrameLevel() + 2)

    -- ★ 新增：专精图标挂载在 frame 上，而不是 textFrame 上，这样数据条平移时它不受影响
    bar.specIcon = bar.frame:CreateTexture(nil, "OVERLAY")
    bar.specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.specIcon:Hide()

    bar.rank = self:FS(bar.textFrame, 9, "OUTLINE"); bar.rank:SetPoint("LEFT",3,0)
    bar.rank:SetJustifyH("RIGHT"); bar.rank:SetTextColor(1.0, 1.0, 1.0, 0.9)
    bar.name = self:FS(bar.textFrame, 10, "OUTLINE"); bar.name:SetJustifyH("LEFT"); bar.name:SetWordWrap(false)
    bar.value = self:FS(bar.textFrame, 9, "OUTLINE"); bar.value:SetJustifyH("RIGHT")
    
    bar.hl = bar.frame:CreateTexture(nil,"HIGHLIGHT"); bar.hl:SetAllPoints(); bar.hl:SetColorTexture(1, 1, 1, 0.05)

    bar.section = section; bar.index = index

    bar.frame:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            ns.db.display.mode = ns:NextMode(ns.db.display.mode)
            if ns.UI then ns.UI:Layout() end
        else
            if not bar._guid then return end
            if bar._isDeath then
                if ns.DetailView then ns.DetailView:ShowDeathDetail(bar._data) end
            else
                if ns.DetailView then
                    if bar._data and bar._data.isAPI then
                        -- print("|cffff0000[LD DEBUG Click]|r isAPI=true, isLocalPlayer=", bar._data.isLocalPlayer, "type=", type(bar._data.isLocalPlayer))
                        local cleanGUID = nil
                        if bar._data.isLocalPlayer then
                            cleanGUID = UnitGUID("player")
                            -- print("|cffff0000[LD DEBUG Click]|r cleanGUID=", cleanGUID)
                        end
                        if cleanGUID then
                            -- print("|cffff0000[LD DEBUG Click]|r calling ShowSpellBreakdownFromAPI")
                            ns.DetailView:ShowSpellBreakdownFromAPI(
                                cleanGUID, nil,
                                bar._nameStr, bar._classStr, bar._mode,
                                bar._data.sessionType
                            )
                        else
                            -- print("|cffff0000[LD DEBUG Click]|r no cleanGUID, showing locked")
                            ns.DetailView:ShowCombatLocked(bar._nameStr)
                        end
                    else
                        -- print("|cffff0000[LD DEBUG Click]|r isAPI=", bar._data and bar._data.isAPI, "data=", bar._data ~= nil)
                        local isOvr = bar.section and bar.section:sub(1, 3) == "ovr"
                        local seg = isOvr and (ns.Segments and ns.Segments:GetOverallSegment()) or nil
                        ns.DetailView:ShowSpellBreakdown(bar._guid, bar._nameStr, bar._classStr, bar._mode, seg)
                    end
                end
            end
        end
    end)
    
    bar.frame:SetScript("OnEnter", function() UI:ShowTooltip(bar, bar.section) end)
    bar.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return bar
end

function UI:MakePinnedSelfBar(container, sf, section)
    local bar = self:MakeBar(container, section, 0)
    bar.frame:SetFrameLevel(sf:GetFrameLevel() + 10)
    bar._isPinned = true
    bar.frame:Hide()
    return bar
end

function UI:BuildTabs()
    local tb = CreateFrame("Frame", nil, self.frame)
    tb:SetHeight(TAB_H); tb:SetPoint("BOTTOMLEFT",0,0); tb:SetPoint("BOTTOMRIGHT",0,0)
    self.tabBg = self:FillBg(tb, {0.05, 0.05, 0.07, 1}); self.tabBar = tb

    local st = CreateFrame("Button", nil, tb)
    st.abg = st:CreateTexture(nil,"BORDER"); st.abg:SetAllPoints(); st.abg:SetColorTexture(0,0.65,1,0.22); st.abg:Hide()
    st.text = self:FS(st, 9, "OUTLINE"); st.text:SetPoint("CENTER"); st.text:SetTextColor(0.55, 0.55, 0.55, 0.9)
    -- ★ 修复：现在点击双栏只切换模式为 split，不更改全局 enabled
    st:SetScript("OnClick", function() ns.db.display.mode = "split"; self:Layout() end)
    self.splitTab = st

    local defs = { {m="damage",l=L["伤害"]},{m="healing",l=L["治疗"]},{m="damageTaken",l=L["承伤"]}, {m="deaths",l=L["死亡"]},{m="interrupts",l=L["打断"]},{m="dispels",l=L["驱散"]} }
    self.tabs = {}
    for i, d in ipairs(defs) do
        local t = CreateFrame("Button", nil, tb)
        t.abg = t:CreateTexture(nil,"BORDER"); t.abg:SetAllPoints(); t.abg:SetColorTexture(0, 0.65, 1, 0.3); t.abg:Hide()
        t.text = self:FS(t, 9, "OUTLINE"); t.text:SetPoint("CENTER"); t.text:SetText(d.l); t.text:SetTextColor(0.55, 0.55, 0.55, 0.9)
        t.mode = d.m
        -- ★ 修复：单栏Tab点击也只切换模式，不再暴力禁用全局双栏
        t:SetScript("OnClick", function() ns.db.display.mode = d.m; self:Layout() end)
        self.tabs[i] = t
    end
end

function UI:LayoutTabs()
    if not self.tabs or not self.splitTab then return end
    local w  = self.tabBar:GetWidth(); if w <= 0 then return end
    local sp = ns.db and ns.db.split
    local visible = {}

    local isSplitActive = self:IsSplitActiveInCurrentScene()
    if sp and isSplitActive then
        local pName = L[ns.MODE_NAMES[sp.primaryMode] or sp.primaryMode]
        local sName = L[ns.MODE_NAMES[sp.secondaryMode] or sp.secondaryMode]
        self.splitTab.text:SetText(pName .. "|" .. sName)
        self.splitTab:Show()
        table.insert(visible, self.splitTab)
    else
        self.splitTab:Hide()
    end

    for _, t in ipairs(self.tabs) do
        -- ★ 双栏启用时，隐藏组成双栏的那两个 tab
        if t.mode and ns.MODE_NAMES[t.mode] then
            t.text:SetText(L[ns.MODE_NAMES[t.mode]])
        end

        if sp and isSplitActive
           and (t.mode == sp.primaryMode or t.mode == sp.secondaryMode) then
            t:Hide()
        else
            t:Show()
            table.insert(visible, t)
        end
    end

    local tw = w / #visible
    for i, t in ipairs(visible) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", self.tabBar, "TOPLEFT", (i-1)*tw, 0)
        t:SetSize(tw, TAB_H)
    end
end

function UI:BuildResize()
    local g = CreateFrame("Frame", nil, self.frame)
    self.resizeHandle = g
    g:SetSize(16,16); g:SetPoint("BOTTOMRIGHT", 0, 0)
    g:SetFrameLevel(self.frame:GetFrameLevel() + 15); g:EnableMouse(true)
    local t = g:CreateTexture(nil,"OVERLAY"); t:SetAllPoints(); t:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    g:SetScript("OnMouseDown", function() if ns.db.window.locked then return end; self.frame:StartSizing("BOTTOMRIGHT"); self._resizing = true end)
    g:SetScript("OnMouseUp", function() 
        if not self._resizing then return end; self._resizing = false; self.frame:StopMovingOrSizing()
        ns.db.window.width = self.frame:GetWidth(); ns.db.window.height = self.frame:GetHeight()
        self:Layout()
    end)
end

function UI:SetupDrag()
    self.titleBar:EnableMouse(true); self.titleBar:RegisterForDrag("LeftButton")
    self.titleBar:SetScript("OnDragStart", function() if not ns.db.window.locked then self.frame:StartMoving() end end)
    self.titleBar:SetScript("OnDragStop", function() self.frame:StopMovingOrSizing(); local db = ns.db.window; db.point,_,db.relPoint,db.x,db.y = self.frame:GetPoint() end)
end

function UI:OnResize() self:LayoutTabs(); self:Layout() end

function UI:Layout()
    if not self.frame or not self.frame:IsShown() then return end

    -- ★ 防抖：如果已有一个 DoLayout 在等待执行，直接返回，不重复创建
    if self._layoutPending then return end
    self._layoutPending = true
 
    if ns.db.display.mode == "split" and not self:IsSplitActiveInCurrentScene() then
        ns.db.display.mode = (ns.db.split and ns.db.split.primaryMode) or "damage"
    end

    self:LayoutTabs()

    local showSumm = (ns.db and ns.db.mythicPlus and ns.db.mythicPlus.dualDisplay)
                     and ns.state.isInInstance
                     and self:IsOverallColumnActive() or false
    if showSumm then
        self.summaryBar:Show()
        self.bodyFrame:SetPoint("TOPLEFT", self.summaryBar, "BOTTOMLEFT", 0, 0)
    else
        self.summaryBar:Hide()
        self.bodyFrame:SetPoint("TOPLEFT", self.titleBar, "BOTTOMLEFT", 0, 0)
    end
    self.bodyFrame:SetPoint("BOTTOMRIGHT", self.tabBar, "TOPRIGHT", 0, 0)

    C_Timer.After(0, function()
        self._layoutPending = false  -- ★ 执行前解锁，允许下一次 Layout
        self:DoLayout(0)
    end)

    self:UpdateLockState()
end

-- ============================================================
-- ★ 外观与字体动态工具
-- ============================================================
function UI:GetBarConfig()
    local db = ns.db.display
    return db.barHeight or 18, db.barGap or 1, db.barAlpha or 0.85, 
           -- ★ 修改这行：
           db.font or STANDARD_TEXT_FONT, db.fontSizeBase or 12, 
           db.fontOutline or "OUTLINE", db.fontShadow or false
end

function UI:ApplyFont(fs, font, size, outline, shadow)
    -- ★ 性能优化：参数没变时跳过 SetFont
    local hash = font .. "|" .. size .. "|" .. (outline or "") .. "|" .. (shadow and "1" or "0")
    if fs._fontHash == hash then return end
    fs._fontHash = hash

    fs:SetFont(font, size, outline)
    if shadow then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- ============================================================
-- ★ 滑动条动态排版计算
-- ============================================================
function UI:UpdateScrollState(listObj, dataCount)
    local bh, gap = self:GetBarConfig()
    local totalH = dataCount * (bh + gap)
    listObj.child:SetHeight(math.max(10, totalH))
    
    local viewH = listObj.sf:GetHeight()
    local maxScroll = math.max(0, totalH - viewH)
    listObj.sb:SetMinMaxValues(0, maxScroll)
    
    if maxScroll > 0 then
        listObj.sb:Show()
        listObj.child:SetWidth(listObj.sf:GetWidth() - 4) -- 为滚动条让路
    else
        listObj.sb:Hide()
        listObj.sb:SetValue(0)
        listObj.child:SetWidth(listObj.sf:GetWidth())
    end
end

-- ============================================================
-- ★ 固定自己排名的辅助函数
-- ============================================================

-- 计算当前列表可视区域能显示多少行
function UI:GetVisibleBarCount(listObj)
    local bh, gap = self:GetBarConfig()
    local viewH = listObj.sf:GetHeight()
    if viewH <= 0 then return 999 end
    return math.floor(viewH / (bh + gap))
end


-- ★ 返回 "visible" / "above" / "below"
function UI:GetSelfViewportPosition(listObj, selfIdx)
    local bh, gap = self:GetBarConfig()
    local rowH = bh + gap
    if rowH <= 0 then return "visible" end

    local viewH = listObj.sf:GetHeight()
    local scrollOffset = listObj.sf:GetVerticalScroll() or 0

    local selfTop    = (selfIdx - 1) * rowH
    local selfBottom = selfTop + bh

    local viewTop    = scrollOffset
    local viewBottom = scrollOffset + viewH

    if selfBottom <= viewTop then return "above" end
    if selfTop >= viewBottom then return "below" end
    return "visible"
end

function UI:PositionPinnedBar(pinnedBar, listObj, position)
    local bh, gap, _, font, fSz, fOut, fShad = self:GetBarConfig()
    pinnedBar.frame:ClearAllPoints()
    pinnedBar.frame:SetHeight(bh)
    if position == "top" then
        pinnedBar.frame:SetPoint("BOTTOMLEFT",  listObj.sf, "TOPLEFT",  0, 0)
        pinnedBar.frame:SetPoint("BOTTOMRIGHT", listObj.sf, "TOPRIGHT", 0, 0)
    else
        pinnedBar.frame:SetPoint("TOPLEFT",  listObj.sf, "BOTTOMLEFT",  0, 0)
        pinnedBar.frame:SetPoint("TOPRIGHT", listObj.sf, "BOTTOMRIGHT", 0, 0)
    end
    self:AnchorBarTexts(pinnedBar)
    self:ApplyFont(pinnedBar.rank,  font, fSz - 1, fOut, fShad)
    self:ApplyFont(pinnedBar.name,  font, fSz,     fOut, fShad)
    self:ApplyFont(pinnedBar.value, font, fSz - 1, fOut, fShad)
end

function UI:FillPinnedFromData(pinnedBar, listObj, d, rank, dur, mode, maxV, position)
    self:PositionPinnedBar(pinnedBar, listObj, position)
    local bh, gap, alpha = self:GetBarConfig()
    local texPath  = ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8"
    local textMode = ns.db.display.textColorMode or "class"
    local CLASS_ICONS = { WARRIOR=132355, PALADIN=135490, HUNTER=132222, ROGUE=132320, PRIEST=135940, DEATHKNIGHT=135771, SHAMAN=135962, MAGE=135932, WARLOCK=136145, MONK=608951, DRUID=132115, DEMONHUNTER=1260827, EVOKER=4567212 }

    pinnedBar.statusbar:Hide(); pinnedBar.fill:Show()
    local cc = ns:GetClassColor(d.class) or {0.5, 0.5, 0.5}
    local offset = ns.db.display.showSpecIcon and (bh + 4) or 0
    local maxBarW = math.max(1, listObj.child:GetWidth() - offset)
    pinnedBar.fill:SetWidth(math.max(1, maxBarW * (maxV > 0 and (d.value / maxV) or 0)))
    pinnedBar.fill:SetTexture(texPath)
    pinnedBar.fill:SetVertexColor(cc[1], cc[2], cc[3], alpha)
    pinnedBar.statusbar:SetStatusBarTexture(texPath)

    pinnedBar.rank:SetText(ns.db.display.showRank and (rank .. ".") or "")
    pinnedBar.name:SetText(ns:DisplayName(d.name))
    do
        local nr, ng, nb
        if textMode == "white" then nr, ng, nb = 1, 1, 1
        elseif textMode == "custom" then local c = ns.db.display.textColor or {1,1,1}; nr, ng, nb = c[1], c[2], c[3]
        else nr, ng, nb = cc[1], cc[2], cc[3] end
        pinnedBar.name:SetTextColor(nr, ng, nb)
    end
    pinnedBar.value:SetText(self:MakeValueStr(d.value, dur, mode, d.perSec, d.percent))

    pinnedBar._data = d; pinnedBar._mode = mode; pinnedBar._isDeath = false
    pinnedBar._guid = d.guid; pinnedBar._nameStr = d.name; pinnedBar._classStr = d.class

    if pinnedBar.specIcon then
        local specID = d.specID
        if d.guid == ns.state.playerGUID then
            local idx = GetSpecialization(); if idx then specID = GetSpecializationInfo(idx) end
        end
        local icon = nil
        if specID then _, _, _, icon = GetSpecializationInfoByID(specID) end
        if not icon and d.class then icon = CLASS_ICONS[d.class] end
        if ns.db.display.showSpecIcon and icon then
            pinnedBar.specIcon:SetTexture(icon); pinnedBar.specIcon:Show()
        else pinnedBar.specIcon:Hide() end
    end
    pinnedBar.frame:Show()
end

function UI:FillPinnedFromAPI(pinnedBar, listObj, src, rank, mode, maxAmt, sType, position)
    self:PositionPinnedBar(pinnedBar, listObj, position)
    local bh, gap, alpha = self:GetBarConfig()
    local texPath  = ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8"
    local textMode = ns.db.display.textColorMode or "class"
    local CLASS_ICONS = { WARRIOR=132355, PALADIN=135490, HUNTER=132222, ROGUE=132320, PRIEST=135940, DEATHKNIGHT=135771, SHAMAN=135962, MAGE=135932, WARLOCK=136145, MONK=608951, DRUID=132115, DEMONHUNTER=1260827, EVOKER=4567212 }

    pinnedBar.fill:Hide(); pinnedBar.statusbar:Show()
    local cls = src.classFilename or "WARRIOR"
    local cc = ns:GetClassColor(cls) or {0.5, 0.5, 0.5}
    pinnedBar.statusbar:SetStatusBarTexture(texPath)
    pinnedBar.statusbar:SetStatusBarColor(cc[1], cc[2], cc[3], alpha)
    pcall(function()
        pinnedBar.statusbar:SetMinMaxValues(0, maxAmt or 1)
        pinnedBar.statusbar:SetValue(src.totalAmount)
    end)

    pinnedBar.rank:SetText(ns.db.display.showRank and (rank .. ".") or "")
    local nameStr = ""; pcall(function() nameStr = tostring(src.name or "") end)
    pinnedBar.name:SetText(ns:DisplayName(nameStr))
    do
        local nr, ng, nb
        if textMode == "white" then nr, ng, nb = 1, 1, 1
        elseif textMode == "custom" then local c = ns.db.display.textColor or {1,1,1}; nr, ng, nb = c[1], c[2], c[3]
        else nr, ng, nb = cc[1], cc[2], cc[3] end
        pinnedBar.name:SetTextColor(nr, ng, nb)
    end

    if COUNT_MODES[mode] then
        pinnedBar.value:SetFormattedText("%s" .. L["次"], AbbreviateNumbers(src.totalAmount))
    else
        pcall(function()
            if ns.db.display.showPerSecond then
                pinnedBar.value:SetFormattedText("%s (%s)", AbbreviateNumbers(src.totalAmount), AbbreviateNumbers(src.amountPerSecond))
            else
                pinnedBar.value:SetText(AbbreviateNumbers(src.totalAmount))
            end
        end)
    end

    if not pinnedBar._apiData then pinnedBar._apiData = {} end
    pinnedBar._apiData.isAPI = true
    pinnedBar._apiData.sourceGUID = src.sourceGUID
    pinnedBar._apiData.sourceCreatureID = src.sourceCreatureID
    pinnedBar._apiData.isLocalPlayer = true
    pinnedBar._apiData.totalAmount = src.totalAmount
    pinnedBar._apiData.amountPerSecond = src.amountPerSecond
    pinnedBar._apiData.sessionType = sType
    pinnedBar._data = pinnedBar._apiData
    pinnedBar._mode = mode; pinnedBar._isDeath = false
    pinnedBar._guid = src.sourceGUID; pinnedBar._nameStr = src.name; pinnedBar._classStr = cls

    if pinnedBar.specIcon then
        local specIdx = GetSpecialization()
        local specID = specIdx and GetSpecializationInfo(specIdx) or nil
        local icon = nil
        if specID then _, _, _, icon = GetSpecializationInfoByID(specID) end
        if not icon and cls then icon = CLASS_ICONS[cls] end
        if ns.db.display.showSpecIcon and icon then
            pinnedBar.specIcon:SetTexture(icon); pinnedBar.specIcon:Show()
        else pinnedBar.specIcon:Hide() end
    end
    pinnedBar.frame:Show()
end

-- ★ 固定自己排名时，给滚动内容底部加 padding，防止最后一行 bar 被固定栏遮挡
function UI:ApplyPinnedPadding(listObj, dataCount)
    local bh, gap = self:GetBarConfig()
    local padH = bh + gap
    local totalH = dataCount * (bh + gap) + padH
    listObj.child:SetHeight(math.max(10, totalH))
    local viewH = listObj.sf:GetHeight()
    local maxScroll = math.max(0, totalH - viewH)
    listObj.sb:SetMinMaxValues(0, maxScroll)
    if maxScroll > 0 then
        listObj.sb:Show()
        listObj.child:SetWidth(listObj.sf:GetWidth() - 4)
    end
end

function UI:GetDataCountForList(listObj)
    if     listObj == self.priList    then return self._pinnedDataCount_pri    or 0
    elseif listObj == self.secList    then return self._pinnedDataCount_sec    or 0
    elseif listObj == self.ovrPriList then return self._pinnedDataCount_ovrPri or 0
    elseif listObj == self.ovrSecList then return self._pinnedDataCount_ovrSec or 0
    end
    return 0
end

function UI:SetDataCountForList(listObj, count)
    if     listObj == self.priList    then self._pinnedDataCount_pri    = count
    elseif listObj == self.secList    then self._pinnedDataCount_sec    = count
    elseif listObj == self.ovrPriList then self._pinnedDataCount_ovrPri = count
    elseif listObj == self.ovrSecList then self._pinnedDataCount_ovrSec = count
    end
end


-- ★ 固定自己排名：缩小 ScrollFrame 腾出空间
function UI:ShrinkSfForPinned(listKey, listObj, dataCount)
    if not self._pinnedSfOrigH then self._pinnedSfOrigH = {} end
    if not self._pinnedSfOrigH[listKey] then
        self._pinnedSfOrigH[listKey] = listObj.sf:GetHeight()
    end
    local bh = self:GetBarConfig()
    listObj.sf:SetHeight(math.max(1, self._pinnedSfOrigH[listKey] - bh))
    self:UpdateScrollState(listObj, dataCount)
end

function UI:RestoreSfForPinned(listKey, listObj, dataCount)
    if self._pinnedSfOrigH and self._pinnedSfOrigH[listKey] then
        listObj.sf:SetHeight(self._pinnedSfOrigH[listKey])
        self._pinnedSfOrigH[listKey] = nil
        self:UpdateScrollState(listObj, dataCount)
    end
end
-- ★ 缩小 ScrollFrame 腾出空间给固定栏
function UI:ShrinkSfForPinned(listKey, listObj, dataCount, position)
    if not self._pinnedSfOrigH then self._pinnedSfOrigH = {} end
    if not self._pinnedSfOrigH[listKey] then
        self._pinnedSfOrigH[listKey] = listObj.sf:GetHeight()
    end
    local bh = self:GetBarConfig()
    local newH = math.max(1, self._pinnedSfOrigH[listKey] - bh)

    if position == "top" then
        -- 保存原始锚点，把 sf 顶部往下推 bh
        if not self._pinnedSfSavedAnchors then self._pinnedSfSavedAnchors = {} end
        if not self._pinnedSfSavedAnchors[listKey] then
            local n = listObj.sf:GetNumPoints()
            local anchors = {}
            for i = 1, n do anchors[i] = { listObj.sf:GetPoint(i) } end
            self._pinnedSfSavedAnchors[listKey] = anchors
            listObj.sf:ClearAllPoints()
            for _, a in ipairs(anchors) do
                local point, rel, relPoint, x, y = unpack(a)
                if point:find("TOP") then
                    listObj.sf:SetPoint(point, rel, relPoint, x, y - bh)
                else
                    listObj.sf:SetPoint(point, rel, relPoint, x, y)
                end
            end
        end
    end

    listObj.sf:SetHeight(newH)
    self:UpdateScrollState(listObj, dataCount)
end

function UI:RestoreSfForPinned(listKey, listObj, dataCount)
    local restored = false

    if self._pinnedSfOrigH and self._pinnedSfOrigH[listKey] then
        listObj.sf:SetHeight(self._pinnedSfOrigH[listKey])
        self._pinnedSfOrigH[listKey] = nil
        restored = true
    end

    if self._pinnedSfSavedAnchors and self._pinnedSfSavedAnchors[listKey] then
        listObj.sf:ClearAllPoints()
        for _, a in ipairs(self._pinnedSfSavedAnchors[listKey]) do
            listObj.sf:SetPoint(unpack(a))
        end
        self._pinnedSfSavedAnchors[listKey] = nil
        restored = true
    end

    if restored then
        self:UpdateScrollState(listObj, dataCount)
    end
end

function UI:CheckPinnedSelfForBars(listKey, listObj, data, dur, mode, count)
    if not self._pinnedSelf then return end
    local pinnedBar = self._pinnedSelf[listKey]
    if not pinnedBar then return end

    if not self._pinnedSelfCache then self._pinnedSelfCache = {} end
    self._pinnedSelfCache[listKey] = { type = "bars", data = data, dur = dur, mode = mode, count = count }

    -- ★ 先恢复 sf 到原始状态，用完整视口判断可见性
    self:RestoreSfForPinned(listKey, listObj, count)

    if not ns.db.display.alwaysShowSelf or mode == "deaths" then
        pinnedBar.frame:Hide(); return
    end

    local selfIdx, selfData = nil, nil
    for i, d in ipairs(data) do
        if d.guid == ns.state.playerGUID then selfIdx = i; selfData = d; break end
    end
    if not selfIdx or not selfData then pinnedBar.frame:Hide(); return end

    local position = self:GetSelfViewportPosition(listObj, selfIdx)
    if position == "visible" then
        pinnedBar.frame:Hide(); return
    end

    -- ★ 缩小 sf 腾出一行，固定栏放在对应方向
    self:ShrinkSfForPinned(listKey, listObj, count, position)
    local maxV = data[1] and data[1].value or 0
    self:FillPinnedFromData(pinnedBar, listObj, selfData, selfIdx, dur, mode, maxV, position)
end

function UI:CheckPinnedSelfForAPI(listKey, listObj, sources, mode, maxAmt, sType)
    if not self._pinnedSelf then return end
    local pinnedBar = self._pinnedSelf[listKey]
    if not pinnedBar then return end

    local count = math.min(#sources, MAX_BARS)

    if not self._pinnedSelfCache then self._pinnedSelfCache = {} end
    self._pinnedSelfCache[listKey] = { type = "api", sources = sources, mode = mode, maxAmt = maxAmt, sType = sType }

    -- ★ 先恢复 sf 到原始状态
    self:RestoreSfForPinned(listKey, listObj, count)

    if not ns.db.display.alwaysShowSelf or mode == "deaths" then
        pinnedBar.frame:Hide(); return
    end

    local selfIdx, selfSrc = nil, nil
    for i, src in ipairs(sources) do
        if src.isLocalPlayer then selfIdx = i; selfSrc = src; break end
    end
    if not selfIdx or not selfSrc then pinnedBar.frame:Hide(); return end

    local position = self:GetSelfViewportPosition(listObj, selfIdx)
    if position == "visible" then
        pinnedBar.frame:Hide(); return
    end

    -- ★ 缩小 sf 腾出一行
    self:ShrinkSfForPinned(listKey, listObj, count, position)
    self:FillPinnedFromAPI(pinnedBar, listObj, selfSrc, selfIdx, mode, maxAmt, sType, position)
end

function UI:ApplyAllFontsIfNeeded()
    local db = ns.db.display
    local hash = (db.font or "") .. "|" .. (db.fontSizeBase or 10) .. "|" .. (db.fontOutline or "")
    if hash == self._lastFontHash then return end
    self._lastFontHash = hash
    self:ApplyAllFonts()
end

function UI:DoLayout(retryCount)
    if not self.bodyFrame then return end
    retryCount = retryCount or 0
    self:ApplyAllFontsIfNeeded()
    self._pinnedSfOrigH = {}
    self._pinnedSfSavedAnchors = {}

    local bodyH = self.bodyFrame:GetHeight()
    local bodyW = self.bodyFrame:GetWidth()

    if bodyW <= 0 or bodyH <= 0 then
        if retryCount < 20 then
            C_Timer.After(0.05, function() self:DoLayout(retryCount + 1) end)
        end
        return
    end

    local sp = ns.db.split
    local useOvr = self:IsOverallColumnActive()
    local isSplitView = self:IsSplitActiveInCurrentScene() and (ns.db.display.mode == "split")

    -- 1. 计算四大容器的边界 (当前 vs 总计)
    local curW, curH = bodyW, bodyH
    local ovrW, ovrH = 0, 0
    local curX, curY = 0, 0
    local ovrX, ovrY = 0, 0

    if useOvr then
        if sp.overallDir == "LR" then
            local lrRatio = sp.lrRatio or 0.5
            local w1 = bodyW * lrRatio
            local gap = 2  -- ★ 留白宽度，防止进度条贴脸
            local sepW = 1 -- ★ 分割线宽度
            local w2 = bodyW - w1 - sepW - gap 
            ovrH = bodyH  
            
            if sp.currentPos == 1 then
                curW, ovrW = w1 - gap, w2
                curX, ovrX = 0, w1 + sepW + gap
            else
                ovrW, curW = w1 - gap, w2
                ovrX, curX = 0, w1 + sepW + gap
            end
            
            self.ovrSepLine:ClearAllPoints()
            self.ovrSepLine:SetPoint("TOPLEFT", self.bodyFrame, "TOPLEFT", w1, 0)
            self.ovrSepLine:SetPoint("BOTTOMLEFT", self.bodyFrame, "BOTTOMLEFT", w1, 0)
            self.ovrSepLine:SetSize(sepW, bodyH)
            self.ovrSepLine:Show()
        else -- TB
            local tbRatio = sp.tbRatio or 0.5
            local h1 = bodyH * tbRatio
            local sepW = 1
            local gap = 2
            local h2 = bodyH - h1 - sepW - gap
            ovrW = bodyW  
            
            if sp.currentPos == 1 then
                curH, ovrH = h1 - gap, h2
                curY, ovrY = 0, -(h1 + sepW + gap)
            else
                ovrH, curH = h1 - gap, h2
                ovrY, curY = 0, -(h1 + sepW + gap)
            end
            
            self.ovrSepLine:ClearAllPoints()
            self.ovrSepLine:SetPoint("TOPLEFT", self.bodyFrame, "TOPLEFT", 0, -h1)
            self.ovrSepLine:SetPoint("TOPRIGHT", self.bodyFrame, "TOPRIGHT", 0, -h1)
            self.ovrSepLine:SetSize(bodyW, sepW)
            self.ovrSepLine:Show()
        end
        
        self.ovrContainer:ClearAllPoints()
        self.ovrContainer:SetPoint("TOPLEFT", self.bodyFrame, "TOPLEFT", ovrX, ovrY)
        self.ovrContainer:SetSize(ovrW, ovrH)
        self.ovrContainer:Show()
    else
        self.ovrSepLine:Hide()
        self.ovrContainer:Hide()
    end

    self.leftContainer:ClearAllPoints()
    self.leftContainer:SetPoint("TOPLEFT", self.bodyFrame, "TOPLEFT", curX, curY)
    self.leftContainer:SetSize(curW, curH)

    -- 2. 内部双数据的划分算法 (主模式 vs 副模式)
    local function LayoutInner(container, head1, list1, head2, list2, w, h, isSplit, mode1, mode2)
        if not isSplit then
            head1:Show(); head1:ClearAllPoints()
            head1:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            head1:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
            
            list1.sf:Show(); list1.sf:ClearAllPoints()
            list1.sf:SetPoint("TOPLEFT", head1, "BOTTOMLEFT", 0, 0)
            list1.sf:SetPoint("TOPRIGHT", head1, "BOTTOMRIGHT", 0, 0)
            list1.sf:SetHeight(math.max(1, h - SECTH_H))
            
            head2:Hide(); list2.sf:Hide()
            return
        end

        local splitDir = sp.splitDir or "TB"
        head1:Show(); head2:Show(); list1.sf:Show(); list2.sf:Show()

        if splitDir == "TB" then
            local tbRatio = sp.tbRatio or 0.5
            local h1 = h * tbRatio
            local gap = 2
            local h2 = h - h1 - gap
            
            local topHead, bottomHead, topList, bottomList
            if sp.primaryPos == 1 then
                topHead, bottomHead = head1, head2
                topList, bottomList = list1, list2
            else
                topHead, bottomHead = head2, head1
                topList, bottomList = list2, list1
            end
            
            topHead:ClearAllPoints()
            topHead:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            topHead:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
            
            topList.sf:ClearAllPoints()
            topList.sf:SetPoint("TOPLEFT", topHead, "BOTTOMLEFT", 0, 0)
            topList.sf:SetPoint("TOPRIGHT", topHead, "BOTTOMRIGHT", 0, 0)
            topList.sf:SetHeight(math.max(1, h1 - gap - SECTH_H))

            bottomHead:ClearAllPoints()
            bottomHead:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -h1)
            bottomHead:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -h1)

            bottomList.sf:ClearAllPoints()
            bottomList.sf:SetPoint("TOPLEFT", bottomHead, "BOTTOMLEFT", 0, 0)
            bottomList.sf:SetPoint("TOPRIGHT", bottomHead, "BOTTOMRIGHT", 0, 0)
            bottomList.sf:SetHeight(math.max(1, h2 - SECTH_H))
        else -- LR
            local lrRatio = sp.lrRatio or 0.5
            local gap = 2 -- ★ 内部的双数据左右分栏留白
            local w1 = w * lrRatio
            local w2 = w - w1 - gap
            
            local leftHead, rightHead, leftList, rightList
            if sp.primaryPos == 1 then
                leftHead, rightHead = head1, head2
                leftList, rightList = list1, list2
            else
                leftHead, rightHead = head2, head1
                leftList, rightList = list2, list1
            end

            leftHead:ClearAllPoints()
            leftHead:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            leftHead:SetWidth(w1 - gap) -- ★ 减去留白宽度，收缩最右侧边缘
            
            leftList.sf:ClearAllPoints()
            leftList.sf:SetPoint("TOPLEFT", leftHead, "BOTTOMLEFT", 0, 0)
            leftList.sf:SetPoint("TOPRIGHT", leftHead, "BOTTOMRIGHT", 0, 0)
            leftList.sf:SetHeight(math.max(1, h - SECTH_H))

            rightHead:ClearAllPoints()
            rightHead:SetPoint("TOPLEFT", container, "TOPLEFT", w1, 0)
            rightHead:SetWidth(w2)

            rightList.sf:ClearAllPoints()
            rightList.sf:SetPoint("TOPLEFT", rightHead, "BOTTOMLEFT", 0, 0)
            rightList.sf:SetPoint("TOPRIGHT", rightHead, "BOTTOMRIGHT", 0, 0)
            rightList.sf:SetHeight(math.max(1, h - SECTH_H))
        end
    end

    LayoutInner(self.leftContainer, self.priHead, self.priList, self.secHead, self.secList, curW, curH, isSplitView, sp.primaryMode, sp.secondaryMode)
    
    if useOvr then
        LayoutInner(self.ovrContainer, self.ovrPriHead, self.ovrPriList, self.ovrSecHead, self.ovrSecList, ovrW, ovrH, isSplitView, sp.primaryMode, sp.secondaryMode)
        
        self.ovrPriHead.info:Hide()
        self.ovrSecHead.info:Hide()
        
        local ovrTitleWord = L["总计"]
        if ns.Segments and ns.Segments.overall and ns.Segments.overall._isMerged then
            ovrTitleWord = L["全程"]
        end
        
        if isSplitView then
            self.ovrPriHead.label:SetText(string.format(L["|cff4cb8e8[%s%s]|r"], ovrTitleWord, L[ns.MODE_NAMES[sp.primaryMode] or ""]))
            self.ovrSecHead.label:SetText(string.format(L["|cff4cb8e8[%s%s]|r"], ovrTitleWord, L[ns.MODE_NAMES[sp.secondaryMode] or ""]))
        else
            self.ovrPriHead.label:SetText(string.format(L["|cff4cb8e8[%s%s]|r"], ovrTitleWord, L[ns.MODE_NAMES[ns.db.display.mode] or ""]))
        end
    end

    self:Refresh()
end

function UI:AnchorBarTexts(bar)
    local rowH = ns.db.display.barHeight or 18
    local iconSize = rowH

    local hash = (ns.db.display.showSpecIcon and "1" or "0")
              .. "|" .. rowH
              .. "|" .. (ns.db.display.barThickness or rowH)
              .. "|" .. (ns.db.display.barVOffset or 0)
    if bar._anchorHash == hash then return end
    bar._anchorHash = hash
    
    -- 读取新的厚度和偏移量配置（如果没有设置旧配置兜底，则默认填满整行）
    local thickness = ns.db.display.barThickness or rowH
    local vOffset   = ns.db.display.barVOffset or 0

    if ns.db.display.showSpecIcon then
        bar.specIcon:SetSize(iconSize, iconSize)
        bar.specIcon:ClearAllPoints()
        bar.specIcon:SetPoint("LEFT", bar.frame, "LEFT", 2, 0)
        
        local offset = iconSize + 4
        
        -- ★ 背景、填充、状态条改为由 BOTTOMLEFT 和 SetHeight 决定，实现解绑
        bar.bg:ClearAllPoints()
        bar.bg:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", offset, vOffset)
        bar.bg:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset)
        bar.bg:SetHeight(thickness)

        bar.fill:ClearAllPoints()
        bar.fill:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", offset, vOffset)
        bar.fill:SetHeight(thickness)

        bar.statusbar:ClearAllPoints()
        bar.statusbar:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", offset, vOffset)
        bar.statusbar:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset)
        bar.statusbar:SetHeight(thickness)

        -- 文字框依然充满整行高度，保证文字/点击区域垂直居中不变
        bar.textFrame:ClearAllPoints()
        bar.textFrame:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", offset, 0)
        bar.textFrame:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, 0)
    else
        bar.specIcon:Hide()

        bar.bg:ClearAllPoints()
        bar.bg:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", 0, vOffset)
        bar.bg:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset)
        bar.bg:SetHeight(thickness)

        bar.fill:ClearAllPoints()
        bar.fill:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", 0, vOffset)
        bar.fill:SetHeight(thickness)

        bar.statusbar:ClearAllPoints()
        bar.statusbar:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", 0, vOffset)
        bar.statusbar:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset)
        bar.statusbar:SetHeight(thickness)

        -- 文字框依然充满整行高度
        bar.textFrame:ClearAllPoints()
        bar.textFrame:SetAllPoints(bar.frame)
    end

    bar.rank:ClearAllPoints()
    bar.rank:SetPoint("LEFT", bar.textFrame, "LEFT", 3, 0)

    bar.value:ClearAllPoints()
    bar.value:SetPoint("RIGHT", bar.textFrame, "RIGHT", -2, 0)
    
    bar.name:ClearAllPoints()
    bar.name:SetPoint("LEFT", bar.rank, "RIGHT", 3, 0)
    bar.name:SetPoint("RIGHT", bar.value, "LEFT", -5, 0) 
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then return end

    if self._sessionCache then
        wipe(self._sessionCache)
    else
        self._sessionCache = {}
    end -- ← 加这一行，每次刷新清空缓存

    local seg  = ns.Segments and ns.Segments:GetViewSegment()
    local dur  = ns.Analysis  and ns.Analysis:GetSegmentDuration(seg) or 0
    local sp   = ns.db.split
    local mode = ns.db.display.mode
    local useOvr = self:IsOverallColumnActive()
    
    -- local isSplitView = sp.enabled and (mode == "split")
    local isSplitView = self:IsSplitActiveInCurrentScene() and (ns.db.display.mode == "split")

    self:RefreshTitle()

    -- ============================================================
    -- Summary 栏（M+ 全程摘要）
    -- ============================================================
    if self.summaryBar:IsShown() then

        local ovrTitleWord = L["总计"]
        local ovrSeg = ns.Segments and ns.Segments.overall
        if ovrSeg and ovrSeg._isMerged then
            ovrTitleWord = L["全程"]
        end
        
        if ns.state.inCombat then
            -- 战斗中：从暴雪 Overall API 读实时数据（Secret Value，只能用 AbbreviateNumbers）
            local durSafe = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall) or 0

            local dmDmg  = self:GetCachedSession(Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.DamageDone)
            local dmHeal = self:GetCachedSession(Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.HealingDone)
            local ok1, ok2 = dmDmg ~= nil, dmHeal ~= nil

            local dmgStr, healStr = "0", "0"
            if ok1 and dmDmg then
                local ok3, s = pcall(AbbreviateNumbers, dmDmg.totalAmount)
                if ok3 and s then dmgStr = s end
            end
            if ok2 and dmHeal then
                local ok4, s = pcall(AbbreviateNumbers, dmHeal.totalAmount)
                if ok4 and s then healStr = s end
            end

            self.summText:SetFormattedText(
                L["全程 %s  |  Damage |cffffd100%s|r  Heal |cff66ff66%s|r"],
                ns:FormatTime(durSafe), dmgStr, healStr)
        else
            local ovrDmg  = ovrSeg and ovrSeg.totalDamage  or 0
            local ovrHeal = ovrSeg and ovrSeg.totalHealing  or 0
            local ovrDur  = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall)
                            or (ovrSeg and ovrSeg.duration or 0)
            if ovrDmg > 0 or ovrHeal > 0 then
                self.summText:SetText(string.format(
                    L["%s %s  |  Damage |cffffd100%s|r  Heal |cff66ff66%s|r"],
                    ovrTitleWord,
                    ns:FormatTime(ovrDur),
                    ns:FormatNumber(ovrDmg),
                    ns:FormatNumber(ovrHeal)))
            else
                self.summText:SetText(string.format(L["%s 0:00  |  Damage 0  Heal 0"], ovrTitleWord))
            end
        end
    end

    -- ============================================================
    -- Tab 高亮状态
    -- ============================================================
    if self.splitTab then
        if isSplitView then
            self.splitTab.abg:Show()
            self.splitTab.text:SetTextColor(0, 0.75, 1)
        else
            self.splitTab.abg:Hide()
            self.splitTab.text:SetTextColor(0.55, 0.55, 0.55)
        end
    end
    for _, t in ipairs(self.tabs) do
        local act = (mode == t.mode)
        if act then
            t.abg:Show(); t.text:SetTextColor(1, 1, 1)
        else
            t.abg:Hide(); t.text:SetTextColor(0.55, 0.55, 0.55)
        end
    end

    -- ============================================================
    -- 数据路径判断
    -- ============================================================
    local isDeathMode   = (mode == "deaths")
    local forceDataMode = isDeathMode
    local isOverall     = ns.Segments and ns.Segments.viewIndex == 0

    local showingCurrent = ns.state.inCombat
        and ns.Segments
        and not isOverall
        and not (ns.Segments.viewIndex and ns.Segments.history[ns.Segments.viewIndex])

    local showingOverallInCombat = ns.state.inCombat and isOverall

    -- ============================================================
    -- 路径一：战斗中，显示当前段实时 API 数据
    -- ============================================================
    if showingCurrent and not forceDataMode then
        local sType = Enum.DamageMeterSessionType.Current
        if isSplitView then
            self:RefreshHead(self.priHead, sp.primaryMode,   nil, 0, sType)
            self:RefreshHead(self.secHead, sp.secondaryMode, nil, 0, sType)
            self:FillBarsFromAPI(self.priBars, self.priList, sp.primaryMode,   sType)
            self:FillBarsFromAPI(self.secBars, self.secList, sp.secondaryMode, sType)
            if useOvr then
                self:FillOvrBars(isSplitView, sp, mode)  -- ★ 修复：不用 Overall API
            end
        else
            self:RefreshHead(self.priHead, mode, nil, 0, sType)
            self:FillBarsFromAPI(self.priBars, self.priList, mode, sType)
            if useOvr then
                self:FillOvrBars(isSplitView, sp, mode)  -- ★ 修复：不用 Overall API
            end
        end

    -- ============================================================
    -- 路径二：战斗中，用户切到了总计视图
    -- ============================================================
    elseif showingOverallInCombat and not forceDataMode then
        local sType = Enum.DamageMeterSessionType.Overall
        if isSplitView then
            self:RefreshHead(self.priHead, sp.primaryMode,   nil, 0, sType)
            self:RefreshHead(self.secHead, sp.secondaryMode, nil, 0, sType)
            self:FillBarsFromAPI(self.priBars, self.priList, sp.primaryMode,   sType)
            self:FillBarsFromAPI(self.secBars, self.secList, sp.secondaryMode, sType)
            if useOvr then
                self:FillOvrBars(isSplitView, sp, mode)  -- ★ 修复：不用 Overall API
            end
        else
            self:RefreshHead(self.priHead, mode, nil, 0, sType)
            self:FillBarsFromAPI(self.priBars, self.priList, mode, sType)
            if useOvr then
                self:FillOvrBars(isSplitView, sp, mode)  -- ★ 修复：不用 Overall API
            end
        end

    -- ============================================================
    -- 路径三：脱战后，从历史数据结构读取（不变）
    -- ============================================================
    else
        if isSplitView then
            local priMode, secMode = sp.primaryMode, sp.secondaryMode
            local priD = ns.Analysis and ns.Analysis:GetSorted(seg, priMode) or {}
            local secD = ns.Analysis and ns.Analysis:GetSorted(seg, secMode) or {}
            self:RefreshHead(self.priHead, priMode, seg, dur)
            self:RefreshHead(self.secHead, secMode, seg, dur)
            self:FillBars(self.priBars, self.priList, priD, dur, priMode)
            self:FillBars(self.secBars, self.secList, secD, dur, secMode)

            if useOvr then
                local ovrSeg  = ns.Segments and ns.Segments:GetOverallSegment()
                local ovrDur  = ovrSeg and ovrSeg.duration or 0
                local ovrPriD = ns.Analysis and ns.Analysis:GetSorted(ovrSeg, priMode) or {}
                local ovrSecD = ns.Analysis and ns.Analysis:GetSorted(ovrSeg, secMode) or {}
                self:FillBars(self.ovrPriBars, self.ovrPriList, ovrPriD, ovrDur, priMode)
                self:FillBars(self.ovrSecBars, self.ovrSecList, ovrSecD, ovrDur, secMode)
            end
        else
            self:RefreshHead(self.priHead, mode, seg, dur)
            if isDeathMode then
                self:FillDeathBars(seg)
            else
                local d = ns.Analysis and ns.Analysis:GetSorted(seg, mode) or {}
                self:FillBars(self.priBars, self.priList, d, dur, mode)
            end
            if useOvr then
                local ovrSeg = ns.Segments and ns.Segments:GetOverallSegment()
                if isDeathMode then
                    self:FillDeathBars(ovrSeg, self.ovrPriBars, self.ovrPriList)
                else
                    local ovrD = ns.Analysis and ns.Analysis:GetSorted(ovrSeg, mode) or {}
                    self:FillBars(self.ovrPriBars, self.ovrPriList, ovrD, (ovrSeg and ovrSeg.duration or 0), mode)
                end
            end
        end
    end
end


function UI:GetCachedSession(sessionType, dmType)
    local key = tostring(sessionType) .. "|" .. tostring(dmType)
    if not self._sessionCache[key] then
        self._sessionCache[key] = C_DamageMeter.GetCombatSessionFromType(sessionType, dmType)
    end
    return self._sessionCache[key]
end


function UI:FillOvrBars(isSplitView, sp, mode)
    if ns.state.inCombat then
        local ovr = ns.Segments and ns.Segments.overall
        local hasPriorData = ovr and (ovr.totalDamage > 0 or ovr.totalHealing > 0)
        local sType = hasPriorData
            and Enum.DamageMeterSessionType.Overall
            or  Enum.DamageMeterSessionType.Current
        if isSplitView then
            self:FillBarsFromAPI(self.ovrPriBars, self.ovrPriList, sp.primaryMode,   sType)
            self:FillBarsFromAPI(self.ovrSecBars, self.ovrSecList, sp.secondaryMode, sType)
        else
            self:FillBarsFromAPI(self.ovrPriBars, self.ovrPriList, mode, sType)
        end
    else
        local ovrSeg = ns.Segments and ns.Segments:GetOverallSegment()
        local ovrDur = ns.Analysis and ns.Analysis:GetSegmentDuration(ovrSeg) or 0
        if isSplitView then
            local ovrPriD = ns.Analysis and ns.Analysis:GetSorted(ovrSeg, sp.primaryMode)   or {}
            local ovrSecD = ns.Analysis and ns.Analysis:GetSorted(ovrSeg, sp.secondaryMode) or {}
            self:FillBars(self.ovrPriBars, self.ovrPriList, ovrPriD, ovrDur, sp.primaryMode)
            self:FillBars(self.ovrSecBars, self.ovrSecList, ovrSecD, ovrDur, sp.secondaryMode)
        else
            local ovrD = ns.Analysis and ns.Analysis:GetSorted(ovrSeg, mode) or {}
            self:FillBars(self.ovrPriBars, self.ovrPriList, ovrD, ovrDur, mode)
        end
    end
end

function UI:RefreshTitle()
    if not self.frame or not self.frame:IsShown() then return end
    if not self.titleText then return end

    -- 当前段标签
    local segL = ns.Segments and ns.Segments:GetViewLabel() or L["无数据"]

    -- 战斗状态点
    local dot = ns.state.inCombat and L["|cff00ff00[战]|r "] or ""

    -- 时长计算
    local dur = 0
    if ns.state.inCombat and ns.state.combatStartTime and ns.state.combatStartTime > 0 then
        local isViewingOverall = ns.Segments and ns.Segments.viewIndex == 0
        if isViewingOverall then
            dur = C_DamageMeter.GetSessionDurationSeconds(
                    Enum.DamageMeterSessionType.Overall) or 0
        else
            dur = C_DamageMeter.GetSessionDurationSeconds(
                    Enum.DamageMeterSessionType.Current) or 0
        end
    else
        local seg = ns.Segments and ns.Segments:GetViewSegment()
        -- M+ 段用钥石通关时间展示，其他段用战斗时间
        if seg and seg._keystoneTime and seg._keystoneTime > 0 then
            dur = seg._keystoneTime
        else
            dur = seg and (seg.duration or 0) or 0
        end
    end
    local tStr = dur > 0 and (" |cffaaaaaa" .. ns:FormatTime(dur) .. "|r") or ""

    -- ★ M+ 信息：格式改为 "+2 水闸行动" 紧跟段标签后面
    local mpStr = ""
    if ns.MythicPlus and ns.MythicPlus:IsActive() and ns.state.inMythicPlus then
        local info = ns.MythicPlus:GetHeaderInfo()
        if info then
            local levelStr = (info.level and info.level > 0)
                            and string.format("|cff4cb8e8+%d|r ", info.level) or ""
            local nameStr  = info.name and ("|cff4cb8e8" .. info.name .. "|r") or ""
            self.titleText:SetText(dot .. segL .. " " .. levelStr .. nameStr .. tStr)
            return
        end
    end

    -- 非 M+ 普通格式
    self.titleText:SetText(dot .. segL .. tStr)
end

-- ★ 新增：将字体设置强行应用到 UI 所有外围组件（解决你觉得实时没生效的错觉）
function UI:ApplyAllFonts()
    if not self.frame then return end
    local _, _, _, font, fSz, fOut, fShad = self:GetBarConfig()
    
    if self.titleText then self:ApplyFont(self.titleText, font, fSz, fOut, fShad) end
    if self.summText then self:ApplyFont(self.summText, font, fSz - 1, fOut, fShad) end
    
    local function applyHead(h)
        if h then
            self:ApplyFont(h.label, font, fSz - 1, fOut, fShad)
            self:ApplyFont(h.info, font, fSz - 1, fOut, fShad)
        end
    end
    applyHead(self.priHead); applyHead(self.secHead)
    applyHead(self.ovrPriHead); applyHead(self.ovrSecHead)
    
    if self.tabs then
        for _, t in ipairs(self.tabs) do
            self:ApplyFont(t.text, font, fSz - 1, fOut, fShad)
        end
    end
    if self.splitTab then self:ApplyFont(self.splitTab.text, font, fSz - 1, fOut, fShad) end
end

function UI:OnCombatStateChanged(inCombat)
    self:RefreshTitle(); self:Refresh()

    if inCombat then
        self:CheckAutoCollapse()
        self:CheckAutoFade(true)   -- 进战时，让 CheckAutoFade 自动判断是否需要取消渐隐
    else
        -- 折叠延迟
        local collapseDelay = ns.db.collapse.delay or 1.5
        if collapseDelay <= 0 then
            self:CheckAutoCollapse()
        else
            C_Timer.After(collapseDelay, function() self:CheckAutoCollapse() end)
        end

        -- 渐隐延迟
        local fadeDelay = (ns.db.fade and ns.db.fade.delay) or 1.5
        if fadeDelay <= 0 then
            self:CheckAutoFade(true)
        else
            C_Timer.After(fadeDelay, function() self:CheckAutoFade(true) end)
        end
    end
end

function UI:RefreshHead(h, mode, seg, dur, apiSessionType)
    if not h:IsShown() then return end
    local mn   = L[ns.MODE_NAMES[mode] or mode]
    local ac   = mode=="damage" and T.dmgC or mode=="healing" and T.healC or mode=="damageTaken" and T.takenC or T.accent
    h.label:SetText(string.format("|cff%02x%02x%02x%s|r", ac[1]*255, ac[2]*255, ac[3]*255, mn))

    local total = 0
    if seg then
        if COUNT_MODES[mode] then
            for _, p in pairs(seg.players) do total = total + (p[mode] or 0) end
        else
            total = mode=="damage" and seg.totalDamage or mode=="healing" and seg.totalHealing or mode=="damageTaken" and seg.totalDamageTaken or 0
        end
        -- 替换：AbbreviateNumbers 改为 ns:FormatNumber
        local valStr = COUNT_MODES[mode] and (ns:FormatNumber(total)..L["次"]) or ns:FormatNumber(total)
        h.info:SetText(string.format(L["团队总%s: %s"], mn, valStr))
    elseif apiSessionType then
        local dmType = MODE_TO_DM[mode]
        if dmType then
            local session = self:GetCachedSession(apiSessionType, dmType)
            if session and session.totalAmount then
                total = session.totalAmount
                -- ★ 改用 SetFormattedText 把秘密数值直接扔给底层处理，避免 Lua 报错
                if COUNT_MODES[mode] then
                    h.info:SetFormattedText(L["团队总%s: %s次"], mn, AbbreviateNumbers(total))
                else
                    h.info:SetFormattedText(L["团队总%s: %s"], mn, AbbreviateNumbers(total))
                end
            else h.info:SetText("") end
        else h.info:SetText("") end
    else h.info:SetText("") end
end

-- ============================================================
-- 滑动条动态排版与填充逻辑 (适配更新后的交互数据)
-- ============================================================
function UI:FillBars(bars, listObj, data, dur, mode)
    local count = math.min(#data, MAX_BARS)
    self:UpdateScrollState(listObj, count)
    local maxV = data[1] and data[1].value or 0
    local barMode, textMode, texPath = ns.db.display.barColorMode or "class", ns.db.display.textColorMode or "class", ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8"
    local bh, gap, alpha, font, fSz, fOut, fShad = self:GetBarConfig()
    
    -- ★ 兜底：暴雪自带的各职业图标材质ID
    local CLASS_ICONS = { WARRIOR = 132355, PALADIN = 135490, HUNTER = 132222, ROGUE = 132320, PRIEST = 135940, DEATHKNIGHT = 135771, SHAMAN = 135962, MAGE = 135932, WARLOCK = 136145, MONK = 608951, DRUID = 132115, DEMONHUNTER = 1260827, EVOKER = 4567212 }

    for i, bar in ipairs(bars) do
        if i <= count then
            bar.frame:SetHeight(bh); bar.frame:ClearAllPoints()
            bar.frame:SetPoint("TOPLEFT", listObj.child, "TOPLEFT", 0, -((i-1)*(bh+gap)))
            bar.frame:SetPoint("TOPRIGHT", listObj.child, "TOPRIGHT", 0, -((i-1)*(bh+gap)))
            self:AnchorBarTexts(bar)
            self:ApplyFont(bar.rank, font, fSz - 1, fOut, fShad)
            self:ApplyFont(bar.name, font, fSz, fOut, fShad)
            self:ApplyFont(bar.value, font, fSz - 1, fOut, fShad)

            local d = data[i]
            bar._data = d; bar._mode = mode; bar._isDeath = false
            bar._guid = d.guid; bar._nameStr = d.name; bar._classStr = d.class

            bar.statusbar:Hide(); bar.fill:Show()
            local cc = ns:GetClassColor(d.class) or {0.5, 0.5, 0.5}
            
            local offset = ns.db.display.showSpecIcon and (bh + 4) or 0
            local maxBarWidth = math.max(1, listObj.child:GetWidth() - offset)
            bar.fill:SetWidth(math.max(1, maxBarWidth * (maxV > 0 and (d.value / maxV) or 0)))
            
            bar.statusbar:SetStatusBarTexture(texPath); bar.fill:SetTexture(texPath)

            if barMode == "class" then bar.statusbar:SetStatusBarColor(cc[1], cc[2], cc[3], alpha); bar.fill:SetVertexColor(cc[1], cc[2], cc[3], alpha)
            elseif barMode == "cyan" then bar.statusbar:SetStatusBarColor(0, 0.65, 1, alpha); bar.fill:SetVertexColor(0, 0.65, 1, alpha)
            else bar.statusbar:SetStatusBarColor(0.4, 0.4, 0.45, alpha); bar.fill:SetVertexColor(0.4, 0.4, 0.45, alpha) end

            bar.rank:SetText(ns.db.display.showRank and (i..".") or "")
            bar.name:SetText(ns:DisplayName(d.name))
            do
                local nr, ng, nb
                if textMode == "white" then
                    nr, ng, nb = 1, 1, 1
                elseif textMode == "custom" then
                    local c = ns.db.display.textColor or {1, 1, 1}
                    nr, ng, nb = c[1], c[2], c[3]
                else
                    nr, ng, nb = cc[1], cc[2], cc[3]
                end
                bar.name:SetTextColor(nr, ng, nb)
            end
            
            if bar.specIcon then
                local guid = bar._guid
                local specID = d and d.specID
                
                local seg = ns.Segments and ns.Segments:GetViewSegment()
                if seg and seg.isActive then
                    if guid == ns.state.playerGUID then
                        local specIdx = GetSpecialization()
                        if specIdx then specID = GetSpecializationInfo(specIdx) end
                    else
                        local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
                        specID = specID or cache.specID
                    end
                    if d and specID then d.specID = specID end
                end

                local icon = nil
                -- ★ 如果有专精，读专精图标；如果没有，读职业图标兜底
                if specID then _, _, _, icon = GetSpecializationInfoByID(specID) end
                if not icon and bar._classStr then icon = CLASS_ICONS[bar._classStr] end

                if ns.db.display.showSpecIcon and icon then
                    bar.specIcon:SetTexture(icon)
                    bar.specIcon:Show()
                else
                    bar.specIcon:Hide()
                end
            end
            
            bar.value:SetText(self:MakeValueStr(d.value, dur, mode, d.perSec, d.percent))
            bar.frame:Show()
        else
            if bar.specIcon then bar.specIcon:Hide() end
            bar.frame:Hide(); bar._data = nil
        end
    end

    -- ★ 检查是否需要在底部固定自己的排名
    local listKey = nil
    if     listObj == self.priList    then listKey = "pri"
    elseif listObj == self.secList    then listKey = "sec"
    elseif listObj == self.ovrPriList then listKey = "ovrPri"
    elseif listObj == self.ovrSecList then listKey = "ovrSec" end
    if listKey then self:CheckPinnedSelfForBars(listKey, listObj, data, dur, mode, count) end

end

function UI:FillBarsFromAPI(bars, listObj, mode, sessionType)
    local dmType = MODE_TO_DM[mode]
    if not dmType then
        self:UpdateScrollState(listObj, 0)
        for _, bar in ipairs(bars) do bar.frame:Hide() end
        return
    end

    local sType = sessionType or Enum.DamageMeterSessionType.Current
    local session = self:GetCachedSession(sType, dmType)
    if not session or not session.combatSources then
        self:UpdateScrollState(listObj, 0)
        for _, bar in ipairs(bars) do bar.frame:Hide() end
        return
    end

    local sources, maxAmt = session.combatSources, session.maxAmount
    local sessionTotal = session.totalAmount or 0
    local count = math.min(#sources, MAX_BARS)
    self:UpdateScrollState(listObj, count)

    local barMode  = ns.db.display.barColorMode  or "class"
    local textMode = ns.db.display.textColorMode or "class"
    local texPath  = ns.db.display.barTexture    or "Interface\\Buttons\\WHITE8X8"
    local bh, gap, alpha, font, fSz, fOut, fShad = self:GetBarConfig()
    
    local CLASS_ICONS = { WARRIOR = 132355, PALADIN = 135490, HUNTER = 132222, ROGUE = 132320, PRIEST = 135940, DEATHKNIGHT = 135771, SHAMAN = 135962, MAGE = 135932, WARLOCK = 136145, MONK = 608951, DRUID = 132115, DEMONHUNTER = 1260827, EVOKER = 4567212 }

    for i, bar in ipairs(bars) do
        if i <= count then
            local src = sources[i]
            bar.frame:SetHeight(bh)
            bar.frame:ClearAllPoints()
            bar.frame:SetPoint("TOPLEFT",  listObj.child, "TOPLEFT",  0, -((i-1)*(bh+gap)))
            bar.frame:SetPoint("TOPRIGHT", listObj.child, "TOPRIGHT", 0, -((i-1)*(bh+gap)))
            self:AnchorBarTexts(bar)
            self:ApplyFont(bar.rank,  font, fSz - 1, fOut, fShad)
            self:ApplyFont(bar.name,  font, fSz,     fOut, fShad)
            self:ApplyFont(bar.value, font, fSz - 1, fOut, fShad)

            bar.fill:Hide()
            bar.statusbar:Show()

            local cls = src.classFilename or "WARRIOR"
            local cc  = ns:GetClassColor(cls) or {0.5, 0.5, 0.5}

            bar.statusbar:SetStatusBarTexture(texPath)
            bar.fill:SetTexture(texPath)

            local r, g, b = cc[1], cc[2], cc[3]
            if barMode == "cyan" then
                r, g, b = 0, 0.65, 1
            elseif barMode == "dark" then
                r, g, b = 0.4, 0.4, 0.45
            end
            bar.statusbar:SetStatusBarColor(r, g, b, alpha)
            local tex = bar.statusbar:GetStatusBarTexture()
            if tex then tex:SetVertexColor(r, g, b, alpha) end
            bar.fill:SetVertexColor(r, g, b, alpha)

            pcall(function()
                bar.statusbar:SetMinMaxValues(0, maxAmt or 1)
                bar.statusbar:SetValue(src.totalAmount)
            end)

            bar.rank:SetText(ns.db.display.showRank and (i .. ".") or "")
            local nameStr = ""
            pcall(function() nameStr = tostring(src.name or "") end)
            bar.name:SetText(ns:DisplayName(nameStr))
            bar._nameStr = nameStr

            do
                local nr, ng, nb
                if textMode == "white" then
                    nr, ng, nb = 1, 1, 1
                elseif textMode == "custom" then
                    local c = ns.db.display.textColor or {1, 1, 1}
                    nr, ng, nb = c[1], c[2], c[3]
                else
                    nr, ng, nb = cc[1], cc[2], cc[3]
                end
                bar.name:SetTextColor(nr, ng, nb)
            end

            -- ★ 实时数值赋值逻辑 (战斗中，不计算百分比，完美避开加密报错)
            if COUNT_MODES[mode] then
                bar.value:SetFormattedText("%s" .. L["次"], AbbreviateNumbers(src.totalAmount))
            else
                local showPS = ns.db.display.showPerSecond
                
                -- ★ 修改点：只保留总量和秒伤，并且在中间加了空格 "%s (%s)"
                pcall(function()
                    if showPS then
                        bar.value:SetFormattedText("%s (%s)", AbbreviateNumbers(src.totalAmount), AbbreviateNumbers(src.amountPerSecond))
                    else
                        bar.value:SetText(AbbreviateNumbers(src.totalAmount))
                    end
                end)
            end

            if not bar._apiData then bar._apiData = {} end
            bar._apiData.isAPI           = true
            bar._apiData.sourceGUID       = src.sourceGUID       -- ★ 新增
            bar._apiData.sourceCreatureID = src.sourceCreatureID 
            bar._apiData.isLocalPlayer    = src.isLocalPlayer

            -- if i == 1 then
            --     print("|cff00ff00[LD DEBUG FillAPI]|r",
            --         "i=1",
            --         "src.sourceGUID type=", type(src.sourceGUID),
            --         "src.sourceCreatureID type=", type(src.sourceCreatureID),
            --         "src.name type=", type(src.name),
            --         "src.isLocalPlayer=", src.isLocalPlayer,
            --         "sType=", sType,
            --         "mode=", mode
            --     )
            -- end

            bar._apiData.totalAmount     = src.totalAmount
            bar._apiData.amountPerSecond = src.amountPerSecond
            bar._apiData.sessionType     = sType

            bar._data = bar._apiData
            bar._mode     = mode
            bar._isDeath  = false

            local guid = src.sourceGUID
            bar._guid     = guid
            bar._apiData.sourceCreatureID = src.sourceCreatureID
            bar._nameStr  = src.name
            bar._classStr = cls
            
            -- ★ 修复：利用 API 提供的 isLocalPlayer 规避 Secret String 比较报错
            local specID = nil
            local ilvl   = 0
            local score  = 0
            
            -- 检查 guid 是否处于加密状态
            local isSecret = issecretvalue and issecretvalue(guid)

            if src.isLocalPlayer then
                -- 如果是自己：安全地获取自己的实时数据
                local specIdx = GetSpecialization()
                if specIdx then specID = GetSpecializationInfo(specIdx) end
                
                local _, equipped = GetAverageItemLevel()
                ilvl = math.floor(equipped or 0)
                
                -- 自己可以用本地未加密的 GUID 查表拿大秘境分数
                local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[ns.state.playerGUID] or {}
                score = cache.score or 0

            elseif not isSecret then
                -- 如果是队友且不在加密状态（如刚脱战/开放世界），正常查表
                local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
                specID = cache.specID
                ilvl   = cache.ilvl or 0
                score  = cache.score or 0
            end
            
            bar._apiData.specID = specID
            bar._apiData.ilvl   = ilvl
            bar._apiData.score  = score

            if bar.specIcon then
                local icon = nil
                -- 优先用我们查到的准确专精
                if specID then 
                    _, _, _, icon = GetSpecializationInfoByID(specID) 
                end
                
                -- 战斗中加密状态下拿不到队友专精，退而求其次用暴雪 API 永远不加密的 specIconID
                if not icon then icon = src.specIconID end
                -- 如果暴雪也没给，用职业图标兜底
                if not icon and cls then icon = CLASS_ICONS[cls] end

                if ns.db.display.showSpecIcon and icon then
                    bar.specIcon:SetTexture(icon)
                    bar.specIcon:Show()
                else
                    bar.specIcon:Hide()
                end
            end

            bar.frame:Show()
        else
            if bars[i].specIcon then bars[i].specIcon:Hide() end
            bar.statusbar:Hide()
            bar.fill:Show()
            bar.frame:Hide()
        end
    end

    -- ★ 检查是否需要在底部固定自己的排名
    local listKey = nil
    if     listObj == self.priList    then listKey = "pri"
    elseif listObj == self.secList    then listKey = "sec"
    elseif listObj == self.ovrPriList then listKey = "ovrPri"
    elseif listObj == self.ovrSecList then listKey = "ovrSec" end
    if listKey then self:CheckPinnedSelfForAPI(listKey, listObj, sources, mode, maxAmt, sType) end

end


function UI:MakeValueStr(value, dur, mode, perSec, percent)
    local vStr = ""
    if COUNT_MODES[mode] then
        vStr = ns:FormatNumber(value) .. L["次"]
    else
        local baseStr = ""
        if ns.db.display.showPerSecond then
            local ps = (perSec and perSec > 0) and perSec
                       or (dur and dur > 0 and (value / dur) or nil)
            if ps then
                -- ★ 修改点：在 %s 和 (%s) 之间加了一个空格
                baseStr = string.format("%s (%s)", ns:FormatNumber(value), ns:FormatNumber(ps))
            else
                baseStr = ns:FormatNumber(value)
            end
        else
            baseStr = ns:FormatNumber(value)
        end

        -- ★ 修改点：判断百分比开关。如果开启，在脱战后附加百分比，并用两个空格拉开间距
        if ns.db.display.showPercent and percent and percent > 0 then
            vStr = string.format("%s  %.1f%%", baseStr, percent)
        else
            vStr = baseStr
        end
    end
    return vStr
end

function UI:FillDeathBars(seg, bars, listObj)
    -- ★ 允许外部传入 bars 和 listObj，不传则默认用主列
    bars    = bars    or self.priBars
    listObj = listObj or self.priList

    -- ★ 死亡模式下隐藏固定自己的排名栏
    if self._pinnedSelf then
        local listKey = nil
        if     listObj == self.priList    then listKey = "pri"
        elseif listObj == self.ovrPriList then listKey = "ovrPri" end
        if listKey and self._pinnedSelf[listKey] then self._pinnedSelf[listKey].frame:Hide() end
    end

    local dl = ns.DeathTracker and ns.DeathTracker:GetDeathLog(seg) or {}
    local selfDeaths, otherDeaths = {}, {}
    for _, d in ipairs(dl) do
        if d.isSelf then table.insert(selfDeaths, d)
        else table.insert(otherDeaths, d) end
    end

    local items = {}
    if #selfDeaths > 0 then
        table.insert(items, { isSeparator=true, label=L["|cffff8888[自己的死亡]|r"], count=#selfDeaths })
        for _, d in ipairs(selfDeaths) do table.insert(items, { isSeparator=false, d=d }) end
    end
    if #otherDeaths > 0 then
        table.insert(items, { isSeparator=true, label=L["|cffaaaaaa[队友死亡]|r"], count=#otherDeaths })
        for _, d in ipairs(otherDeaths) do table.insert(items, { isSeparator=false, d=d }) end
    end

    local count = math.max(1, math.min(#items, MAX_BARS))
    self:UpdateScrollState(listObj, count)
    local cw = listObj.child:GetWidth()
    local bh, gap, alpha, font, fSz, fOut, fShad = self:GetBarConfig()
    
    -- ★ 新增：暴雪官方的职业图标兜底表
    local CLASS_ICONS = { WARRIOR = 132355, PALADIN = 135490, HUNTER = 132222, ROGUE = 132320, PRIEST = 135940, DEATHKNIGHT = 135771, SHAMAN = 135962, MAGE = 135932, WARLOCK = 136145, MONK = 608951, DRUID = 132115, DEMONHUNTER = 1260827, EVOKER = 4567212 }

    if #items == 0 then
        for _, bar in ipairs(bars) do bar.frame:Hide() end
        local bar = bars[1]; if not bar then return end
        bar.frame:SetHeight(bh)
        bar.frame:ClearAllPoints()
        bar.frame:SetPoint("TOPLEFT",  listObj.child, "TOPLEFT",  0, 0)
        bar.frame:SetPoint("TOPRIGHT", listObj.child, "TOPRIGHT", 0, 0)
        self:AnchorBarTexts(bar)
        self:ApplyFont(bar.rank,  font, fSz - 1, fOut, fShad)
        self:ApplyFont(bar.name,  font, fSz,     fOut, fShad)
        self:ApplyFont(bar.value, font, fSz - 1, fOut, fShad)
        bar._data = nil; bar._isDeath = false; bar._guid = nil
        bar.statusbar:Hide()
        bar.fill:Show()
        bar.fill:SetWidth(1)
        bar.fill:SetVertexColor(0, 0, 0, 0)
        bar.rank:SetText("")
        bar.name:SetText(L["|cff555555本段暂无死亡记录|r"])
        bar.name:SetTextColor(1, 1, 1)
        bar.value:SetText("")
        if bar.specIcon then bar.specIcon:Hide() end -- ★ 修复：空数据时隐藏残留图标
        bar.frame:Show()
        return
    end

    for i = 1, MAX_BARS do
        local bar = bars[i]
        if i <= count then
            local item = items[i]
            bar.frame:SetHeight(bh)
            bar.frame:ClearAllPoints()
            bar.frame:SetPoint("TOPLEFT",  listObj.child, "TOPLEFT",  0, -((i-1)*(bh+gap)))
            bar.frame:SetPoint("TOPRIGHT", listObj.child, "TOPRIGHT", 0, -((i-1)*(bh+gap)))
            self:AnchorBarTexts(bar)
            self:ApplyFont(bar.rank,  font, fSz - 1, fOut, fShad)
            self:ApplyFont(bar.name,  font, fSz,     fOut, fShad)
            self:ApplyFont(bar.value, font, fSz - 1, fOut, fShad)
            bar.statusbar:Hide()
            bar.fill:Show()

            if item.isSeparator then
                bar._data = nil; bar._isDeath = false; bar._guid = nil
                bar.fill:SetWidth(cw)
                bar.fill:SetVertexColor(0.06, 0.06, 0.08, 0.95)
                bar.rank:SetText("")
                bar.name:SetText(item.label .. string.format(" |cff666666(%d)|r", item.count))
                bar.name:SetTextColor(1, 1, 1)
                bar.value:SetText("")
                if bar.specIcon then bar.specIcon:Hide() end -- ★ 修复：分割线隐藏残留图标
            else
                local d = item.d
                bar._data     = d
                bar._mode     = "deaths"
                bar._isDeath  = true
                bar._guid     = d.playerGUID
                bar.fill:SetVertexColor(d.isSelf and 0.45 or 0.30, 0.05, 0.05, alpha)
                bar.fill:SetWidth(cw)
                bar.rank:SetText("|cff888888" .. (d.timestamp and date("%H:%M", d.timestamp) or "--:--") .. "|r")
                local cc = ns:GetClassColor(d.playerClass)
                bar.name:SetText(ns:DisplayName(d.playerName or "?"))
                bar.name:SetTextColor(cc[1], cc[2], cc[3])
                local killStr = "|cffff5555" .. (d.killingAbility or "?") .. "|r"
                if d.killerName and d.killerName ~= "" and d.killerName ~= "?" then
                    killStr = killStr .. " |cff888888by |r|cffcccccc" .. ns:DisplayName(d.killerName) .. "|r"
                end
                bar.value:SetText(killStr)
                
                -- ★ 修复：为死亡玩家匹配正确的专精图标
                if bar.specIcon then
                    local icon = nil
                    local guid = d.playerGUID
                    local specID = nil
                    
                    -- 1. 从缓存中获取队友的专精
                    local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
                    specID = cache.specID
                    
                    -- 2. 如果死的是自己，实时获取最新专精
                    if guid == ns.state.playerGUID then
                        local specIdx = GetSpecialization()
                        if specIdx then specID = GetSpecializationInfo(specIdx) end
                    end
                    
                    -- 3. 获取图标ID
                    if specID then 
                        _, _, _, icon = GetSpecializationInfoByID(specID) 
                    end
                    
                    -- 4. 兜底逻辑：如果在战斗中等情况没扫到专精，用基础职业图标代替
                    if not icon and d.playerClass then 
                        icon = CLASS_ICONS[d.playerClass] 
                    end

                    if ns.db.display.showSpecIcon and icon then
                        bar.specIcon:SetTexture(icon)
                        bar.specIcon:Show()
                    else
                        bar.specIcon:Hide()
                    end
                end
            end
            bar.frame:Show()
        else
            bars[i].frame:Hide()
        end
    end
end


-- ============================================================
-- ★ Tooltip 智能锚定：始终在主窗口外部展开
-- ============================================================
function UI:AnchorTooltipToWindow(bar)
    local f = self.frame
    if not f then
        GameTooltip:SetOwner(bar.frame, "ANCHOR_LEFT")
        return
    end

    GameTooltip:SetOwner(bar.frame, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()

    local scale   = f:GetEffectiveScale()
    local fLeft   = (f:GetLeft()   or 0) * scale
    local fTop    = (f:GetTop()    or 0) * scale
    local screenH = GetScreenHeight() * UIParent:GetEffectiveScale()

    -- 左侧空间足够 → 在窗口左侧展开
    if fLeft > 280 then
        GameTooltip:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, 0)
    -- 左侧不够，优先在窗口上方展开
    elseif fTop < screenH * 0.7 then
        GameTooltip:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
    -- 上方也装不下（窗口太靠顶部），才在下方展开
    else
        GameTooltip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4)
    end
end
-- ============================================================
-- ★ 修复：完美兼容战斗 API 安全提示框
-- ============================================================
function UI:ShowTooltip(bar, section)
    local d = bar._data; if not d then return end
    self:AnchorTooltipToWindow(bar)

    local guid = bar._guid
    local seg  = ns.Segments and ns.Segments:GetViewSegment()
    local specID, ilvl, score
    
    -- ★ 工具提示数据获取逻辑精简：API模式下绝对不要再去查 guid，直接读存好的数据
    if d and d.isAPI then
        specID = d.specID
        ilvl   = d.ilvl or 0
        score  = d.score or 0
    elseif seg and seg.isActive then
        local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
        specID = (d and d.specID) or cache.specID
        ilvl   = (d and d.ilvl)   or cache.ilvl or 0
        score  = (d and d.score)  or cache.score or 0
        
        if guid == ns.state.playerGUID then
            local specIdx = GetSpecialization()
            if specIdx then specID = GetSpecializationInfo(specIdx) end
        end
        
        if d then
            d.specID = specID
            d.ilvl   = ilvl
            d.score  = score
        end
    else
        specID = d and d.specID
        ilvl   = d and d.ilvl or 0
        score  = d and d.score or 0
    end

    local specName = ""
    if specID then
        local _, name = GetSpecializationInfoByID(specID)
        if name then specName = name end
    end

    local function AddPlayerInfoLines()
        -- ★ 核心修改：只有大于 0 或不为空时，才会添加这些行，否则直接跳过
        if specName ~= "" or (ilvl and ilvl > 0) or (score and score > 0) then
            GameTooltip:AddLine(" ")
            if specName ~= "" then
                GameTooltip:AddDoubleLine(L["专精"], specName, 0.7,0.7,0.7, 1,1,1)
            end
            if ilvl and ilvl > 0 then
                GameTooltip:AddDoubleLine(L["平均装等"], tostring(ilvl), 0.7,0.7,0.7, 1,0.85,0)
            end
            if score and score > 0 then
                -- ★ 修复：改用获取赛季总分颜色的 API
                local color = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
                if color then
                    GameTooltip:AddDoubleLine(L["大秘境评分"], color:WrapTextInColorCode(tostring(score)), 0.7,0.7,0.7, 1,1,1)
                else
                    GameTooltip:AddDoubleLine(L["大秘境评分"], tostring(score), 0.7,0.7,0.7, 1,0.5,0)
                end
            end
        end
    end

    if bar._isDeath then
        GameTooltip:AddLine(ns:GetClassHex(d.playerClass)..ns:DisplayName(d.playerName)..L["|r [死亡]"])
        AddPlayerInfoLines()
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["致命技能"], d.killingAbility or "?", 0.7,0.7,0.7, 1,0.3,0.3)
        GameTooltip:AddDoubleLine(L["击杀者"],   ns:DisplayName(d.killerName) or "?", 0.7,0.7,0.7, 1,1,1)
        GameTooltip:AddDoubleLine(L["死前受伤"], ns:FormatNumber(d.totalDamageTaken or 0),     0.7,0.7,0.7, 1,0.5,0.5)
        GameTooltip:AddDoubleLine(L["死前受治"], ns:FormatNumber(d.totalHealingReceived or 0), 0.7,0.7,0.7, 0.5,1,0.5)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["|cff00ccff点击查看完整死亡日志|r"], 0.4,0.4,0.4)
        GameTooltip:Show(); return
    end

    if d.isAPI then
        GameTooltip:AddLine(ns:GetClassHex(bar._classStr)..ns:DisplayName(bar._nameStr or "?").."|r")
        AddPlayerInfoLines()
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["|cffaaaaaa— 战斗中 (实时) —|r"])
        
        -- ★ 分开传递秘密数值给 GameTooltip
        if COUNT_MODES[bar._mode] then
            GameTooltip:AddDoubleLine((L[ns.MODE_NAMES[bar._mode] or bar._mode]) .. L["次"], AbbreviateNumbers(d.totalAmount), 0.7,0.7,0.7, 1,1,1)
        elseif ns.db.display.showPerSecond then
            GameTooltip:AddDoubleLine(ns.MODE_NAMES[bar._mode] or bar._mode, AbbreviateNumbers(d.totalAmount), 0.7,0.7,0.7, 1,1,1)
            GameTooltip:AddDoubleLine(L["每秒"], AbbreviateNumbers(d.amountPerSecond), 0.7,0.7,0.7, 1,0.85,0)
        else
            GameTooltip:AddDoubleLine(ns.MODE_NAMES[bar._mode] or bar._mode, AbbreviateNumbers(d.totalAmount), 0.7,0.7,0.7, 1,1,1)
        end
        
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["|cff00ccff左键: 技能细分  右键: 切换模式|r"], 0.4,0.4,0.4)
        GameTooltip:Show()
        return
    end

    local mode = bar._mode or ns.db.display.mode
    local dur  = ns.Analysis  and ns.Analysis:GetSegmentDuration(seg) or 0
    local mn   = L[ns.MODE_NAMES[mode] or mode]

    GameTooltip:AddLine(ns:GetClassHex(d.class)..ns:DisplayName(d.name or "?").."|r")
    AddPlayerInfoLines()
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["|cffaaaaaa— 本段 —|r"])
    GameTooltip:AddDoubleLine(mn, ns:FormatNumber(d.value), 0.7,0.7,0.7, 1,1,1)
    if dur > 0 and ns.MODE_UNITS[mode] then
        GameTooltip:AddDoubleLine(ns.MODE_UNITS[mode], string.format("%.1f", d.value/dur), 0.7,0.7,0.7, 1,0.85,0)
    end
    GameTooltip:AddDoubleLine(L["占比"], string.format("%.1f%%", d.percent or 0), 0.7,0.7,0.7, 1,1,1)
    if d.petDamage and d.petDamage > 0 and mode == "damage" then
        GameTooltip:AddDoubleLine(L["含宠物"], ns:FormatNumber(d.petDamage), 0.5,0.5,0.5, 0.7,0.7,0.7)
    end

    if ns.db.split.enabled and seg then
        local other = (section=="primary") and ns.db.split.secondaryMode or ns.db.split.primaryMode
        if other ~= mode and seg.players[d.guid] then
            local ov = ns.Analysis and ns.Analysis:GetPlayerValue(seg.players[d.guid], other, seg)
            if ov and ov > 0 then
                GameTooltip:AddLine(" ")
                local on2 = L[ns.MODE_NAMES[other] or other]
                GameTooltip:AddDoubleLine(on2, ns:FormatNumber(ov), 0.7,0.7,0.7, 1,1,1)
                if dur > 0 then GameTooltip:AddDoubleLine(ns.MODE_UNITS[other] or "", string.format("%.1f",ov/dur), 0.7,0.7,0.7, 1,0.85,0) end
            end
        end
    end

    if self:IsOverallColumnActive() then
        local ovd = ns.Analysis and ns.Analysis:GetOverallPlayerData(d.guid, mode)
        if ovd then
            local ac = T.accent or {0.0, 0.65, 1.0}
            GameTooltip:AddLine(" ")

            local ovrTitleWord = L["总计"]
            if ns.Segments and ns.Segments.overall and ns.Segments.overall._isMerged then
                ovrTitleWord = L["全程"]
            end
            
            GameTooltip:AddLine(string.format(L["|cff%02x%02x%02x— %s —|r"], ac[1]*255, ac[2]*255, ac[3]*255, ovrTitleWord))
            
            GameTooltip:AddDoubleLine(string.format(L["%s%s"], ovrTitleWord, mn), ns:FormatNumber(ovd.value), 0.7,0.7,0.7, 1,1,1)
            
            if ovd.dur > 0 and ns.MODE_UNITS[mode] then 
                GameTooltip:AddDoubleLine(string.format(L["%s%s"], ovrTitleWord, ns.MODE_UNITS[mode]), string.format("%.1f",ovd.perSec), 0.7,0.7,0.7, 1,0.85,0) 
            end
            
            GameTooltip:AddDoubleLine(string.format(L["%s占比"], ovrTitleWord), string.format("%.1f%%", ovd.percent), 0.7,0.7,0.7, ac[1],ac[2],ac[3])
        end
    end

    GameTooltip:AddLine(" ")
    if d.deaths and d.deaths > 0 then GameTooltip:AddDoubleLine(L["死亡"], d.deaths, 0.7,0.7,0.7, 1,0.3,0.3) end
    if d.interrupts and d.interrupts > 0 then GameTooltip:AddDoubleLine(L["打断"], d.interrupts, 0.7,0.7,0.7, 0.3,1,0.3) end
    if d.dispels and d.dispels > 0 then GameTooltip:AddDoubleLine(L["驱散"], d.dispels, 0.7,0.7,0.7, 0.3,0.8,1) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["|cff00ccff左键: 技能细分  右键: 切换模式|r"], 0.4,0.4,0.4)
    GameTooltip:Show()
end

function UI:Toggle()
    self:EnsureCreated()
    if self.frame:IsShown() then 
        self.frame:Hide()
        ns.db.window.visible = false  -- ★ 保存隐藏状态
    else 
        self.frame:Show()
        ns.db.window.visible = true   -- ★ 保存显示状态
        self:Layout() 
        C_Timer.After(0.1, function() self:CheckAutoFade(true) end)
    end
end
function UI:IsVisible()
    return self.frame and self.frame:IsShown()
end

function UI:UpdateLock() end

function UI:UpdateLockState()
    if not self.resizeHandle then return end
    
    if ns.db.window.locked then
        self.resizeHandle:Hide()
    else
        self.resizeHandle:Show()
    end
end