--[[
    Light Damage - UICollapse.lua
    折叠/展开 + 渐隐系统
]]
local addonName, ns = ...
local L = ns.L
local UI = ns.UI
local TEX = UI.TEX
local TITLE_H = UI.TITLE_H

function UI:ToggleCollapse(collapse, skipAnim)
    if collapse == self._collapsed then return end
    self._collapsed = collapse
    local db = ns.db.window; local cdb = ns.db.collapse
    local targetHeight = collapse and TITLE_H or (self._savedHeight or db.height)
    if collapse then
        self._savedHeight = self.frame:GetHeight(); self._savedAnchor = { self.frame:GetPoint() }
        if self._savedHeight > TITLE_H then
            db.height = self._savedHeight
            db.width  = self.frame:GetWidth()
            if db.rememberSceneSize then
                local cat = ns.state.instanceCategory or "outdoor"
                if not db.sceneSizes then db.sceneSizes = {} end
                db.sceneSizes[cat] = { width = db.width, height = self._savedHeight }
            end
        end
        local left = self.frame:GetLeft(); local top = self.frame:GetTop()
        self.frame:ClearAllPoints(); self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        self.collapseBtn.iconTex:SetTexture(TEX.."btn_expand"); self.collapseBtn.iconTex:SetVertexColor(0.65,0.65,0.65,1)
        self.collapseBtn.texNormal = TEX.."btn_expand"; self.collapseBtn.texHover = TEX.."btn_expand"
        if self.resizeHandle then self.resizeHandle:Hide() end
    else
        self.collapseBtn.iconTex:SetTexture(TEX.."btn_collapse"); self.collapseBtn.iconTex:SetVertexColor(0.65,0.65,0.65,1)
        self.collapseBtn.texNormal = TEX.."btn_collapse"; self.collapseBtn.texHover = TEX.."btn_collapse"
        self.bodyFrame:Show(); self.tabBar:Show()
        if self:IsOverallColumnActive() and (ns.db.mythicPlus and ns.db.mythicPlus.dualDisplay) and ns.state.isInInstance then self.summaryBar:Show() end
        if self.resizeHandle then self.resizeHandle:Show() end
    end
    local function onAnimComplete()
        if self._collapsed then self.bodyFrame:Hide(); self.tabBar:Hide(); self.summaryBar:Hide()
        else
            self.frame:ClearAllPoints()
            if self._savedAnchor then self.frame:SetPoint(unpack(self._savedAnchor)) end
            self:Layout()
        end
        self:CheckAutoFade(true)
    end
    if cdb.enableAnim and not skipAnim then self:StartCollapseAnim(targetHeight, onAnimComplete)
    else self.frame:SetHeight(targetHeight); onAnimComplete() end
end

function UI:StartCollapseAnim(targetHeight, onComplete)
    if not self.animFrame then self.animFrame = CreateFrame("Frame") end
    local startHeight = self.frame:GetHeight()
    local duration = ns.db.collapse.animDuration or 0.5; local elapsed = 0
    self.animFrame:SetScript("OnUpdate", function(f, dt)
        elapsed = elapsed + dt; local progress = math.min(elapsed / duration, 1)
        local ease = math.sin(progress * math.pi / 2)
        self.frame:SetHeight(startHeight + (targetHeight - startHeight) * ease)
        if progress >= 1 then f:SetScript("OnUpdate", nil); if onComplete then onComplete() end end
    end)
end

function UI:CheckAutoCollapse(skipAnim)
    local cdb = ns.db.collapse; if not cdb then return end
    local mustExpand = false
    if ns.state.inCombat then mustExpand = true end
    if cdb.neverInInstance and ns.state.isInInstance then mustExpand = true end
    if mustExpand then if self._collapsed then self:ToggleCollapse(false, skipAnim) end; return end
    if cdb.autoCollapse then if not self._collapsed then self:ToggleCollapse(true, skipAnim) end end
end

-- ============================================================
-- 渐隐系统
-- ============================================================
function UI:CheckAutoFade(force)
    local fdb = ns.db and ns.db.fade; if not fdb then return end
    if not self.frame or not self.frame:IsShown() then return end
    local anyFadeEnabled = fdb.fadeBars or fdb.fadeBody
    if not anyFadeEnabled then if self._faded or force then self._faded = false; self:ApplyFadeAlpha(false, false) end; return end

    local shouldFadeBars = false
    if fdb.fadeBars then
        if fdb.barsWhen == "always" then shouldFadeBars = true else shouldFadeBars = not ns.state.inCombat end
        if shouldFadeBars and fdb.barsNeverInInstance and ns.state.isInInstance then shouldFadeBars = false end
    end
    local shouldFadeBody = false
    if fdb.fadeBody then
        if fdb.bodyWhen == "always" then shouldFadeBody = true else shouldFadeBody = not ns.state.inCombat end
        if shouldFadeBody and fdb.bodyNeverInInstance and ns.state.isInInstance then shouldFadeBody = false end
    end
    if fdb.unfadeOnHover and self.frame:IsMouseOver() then shouldFadeBars = false; shouldFadeBody = false end
    local newFaded = shouldFadeBars or shouldFadeBody
    if newFaded ~= self._faded or force then self._faded = newFaded; self:ApplyFadeAlpha(shouldFadeBars, shouldFadeBody) end
end

function UI:ApplyFadeAlpha(shouldFadeBars, shouldFadeBody)
    local fdb = ns.db and ns.db.fade; if not fdb then return end
    if self._fadeAnimFrame then self._fadeAnimFrame:SetScript("OnUpdate", nil) end
    self._fadeAnimating = false
    local barsAlpha = shouldFadeBars and fdb.barsAlpha or 1.0; local bodyAlpha = shouldFadeBody and fdb.bodyAlpha or 1.0
    local barsTargets, bodyTargets = {}, {}
    if fdb.fadeBars then
        if self.titleBar then table.insert(barsTargets, self.titleBar) end
        if self.tabBar then table.insert(barsTargets, self.tabBar) end
        if self.resizeHandle then table.insert(barsTargets, self.resizeHandle) end
    end
    if fdb.fadeBody then
        if self.bodyFrame then table.insert(bodyTargets, self.bodyFrame) end
        if self.summaryBar then table.insert(bodyTargets, self.summaryBar) end
    end
    if not shouldFadeBars and not shouldFadeBody then
        if self.titleBar then table.insert(barsTargets, self.titleBar) end
        if self.tabBar then table.insert(barsTargets, self.tabBar) end
        if self.resizeHandle then table.insert(barsTargets, self.resizeHandle) end
        if self.bodyFrame then table.insert(bodyTargets, self.bodyFrame) end
        if self.summaryBar then table.insert(bodyTargets, self.summaryBar) end
    end
    if #barsTargets == 0 and #bodyTargets == 0 then return end
    if fdb.enableAnim and not self._fadeAnimating then self:StartFadeAnim(barsTargets, barsAlpha, bodyTargets, bodyAlpha)
    else for _, f in ipairs(barsTargets) do f:SetAlpha(barsAlpha) end; for _, f in ipairs(bodyTargets) do f:SetAlpha(bodyAlpha) end end
end

function UI:StartFadeAnim(barsTargets, barsAlpha, bodyTargets, bodyAlpha)
    if not self._fadeAnimFrame then self._fadeAnimFrame = CreateFrame("Frame") end
    self._fadeAnimating = true
    local barsStart = {}; for i, f in ipairs(barsTargets) do barsStart[i] = f:GetAlpha() end
    local bodyStart = {}; for i, f in ipairs(bodyTargets) do bodyStart[i] = f:GetAlpha() end
    local duration = (ns.db.fade and ns.db.fade.animDuration) or 0.5; local elapsed = 0
    self._fadeAnimFrame:SetScript("OnUpdate", function(frame, dt)
        elapsed = elapsed + dt; local progress = math.min(elapsed / duration, 1); local ease = math.sin(progress * math.pi / 2)
        for i, f in ipairs(barsTargets) do f:SetAlpha(barsStart[i] + (barsAlpha - barsStart[i]) * ease) end
        for i, f in ipairs(bodyTargets) do f:SetAlpha(bodyStart[i] + (bodyAlpha - bodyStart[i]) * ease) end
        if progress >= 1 then frame:SetScript("OnUpdate", nil); self._fadeAnimating = false end
    end)
end
