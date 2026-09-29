local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class CouchModeAnimations
local Animations = {}
addon.Animations = Animations

---@class CouchModeProgressAnimation
---@field owner Frame
---@field duration number
---@field elapsed number
---@field index integer?
---@field Cancel fun(self: CouchModeProgressAnimation)

local active = {}
local frameNumber = 0
local driver = CreateFrame('Frame')
driver:Hide()

local function remove(animation)
    local index = animation.index
    if not index then return end

    local lastIndex = #active
    local last = active[lastIndex]
    active[index] = last
    active[lastIndex] = nil
    if index < lastIndex then last.index = index end
    animation.index = nil

    if #active == 0 then driver:Hide() end
end

function Animations.Linear(progress)
    return progress
end

function Animations.Smoothstep(progress)
    return progress * progress * (3 - 2 * progress)
end

function Animations.QuadraticOut(progress)
    return progress * (2 - progress)
end

function Animations.CubicOut(progress)
    return 1 - (1 - progress) ^ 3
end

--- Runs an eased progress callback from 0 to 1 while `owner` is visible.
--- Cancellation stops at the current state and never calls `onComplete`.
---@param owner Frame
---@param duration number
---@param easing fun(progress: number): number
---@param onUpdate fun(easedProgress: number, progress: number, elapsed: number)
---@param onComplete? fun()
---@return CouchModeProgressAnimation
function Animations.Progress(owner, duration, easing, onUpdate, onComplete)
    assert(owner, 'Animations.Progress requires an owner frame')
    assert(type(duration) == 'number' and duration > 0, 'duration must be greater than zero')
    assert(type(easing) == 'function', 'easing must be a function')
    assert(type(onUpdate) == 'function', 'onUpdate must be a function')

    local animation = {
        owner = owner,
        duration = duration,
        elapsed = 0,
        easing = easing,
        onUpdate = onUpdate,
        onComplete = onComplete,
        startedFrame = frameNumber,
    }

    function animation:Cancel()
        remove(self)
        self.onComplete = nil
        self.onUpdate = nil
    end

    active[#active + 1] = animation
    animation.index = #active
    driver:Show()
    return animation
end

--- Smoothly interpolates a frame's alpha to the requested value.
--- The owner must be visible for the duration of the fade.
---@param owner Frame
---@param targetAlpha number
---@param duration number
---@param onComplete? fun()
---@return CouchModeProgressAnimation?
function Animations.FadeTo(owner, targetAlpha, duration, onComplete)
    assert(owner and owner.GetAlpha and owner.SetAlpha, 'Animations.FadeTo requires a frame')
    assert(type(targetAlpha) == 'number', 'targetAlpha must be a number')

    targetAlpha = math.max(0, math.min(1, targetAlpha))
    local startAlpha = owner:GetAlpha()
    if math.abs(startAlpha - targetAlpha) < 0.001 then
        owner:SetAlpha(targetAlpha)
        if onComplete then onComplete() end
        return nil
    end

    return Animations.Progress(owner, duration, Animations.Smoothstep, function(progress)
        owner:SetAlpha(startAlpha + (targetAlpha - startAlpha) * progress)
    end, function()
        owner:SetAlpha(targetAlpha)
        if onComplete then onComplete() end
    end)
end

driver:SetScript('OnUpdate', function(_, elapsed)
    frameNumber = frameNumber + 1
    for i = #active, 1, -1 do
        local animation = active[i]
        if animation.startedFrame < frameNumber and animation.updatedFrame ~= frameNumber then
            animation.updatedFrame = frameNumber
            local owner = animation.owner
            if not owner.IsVisible or owner:IsVisible() then
                animation.elapsed = animation.elapsed + elapsed
                local progress = math.min(animation.elapsed / animation.duration, 1)
                animation.onUpdate(animation.easing(progress), progress, animation.elapsed)

                if animation.index and progress >= 1 then
                    local onComplete = animation.onComplete
                    remove(animation)
                    animation.onComplete = nil
                    animation.onUpdate = nil
                    if onComplete then onComplete() end
                end
            end
        end
    end
end)
