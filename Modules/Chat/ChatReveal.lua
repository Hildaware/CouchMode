--[[ ChatReveal.lua
Character-by-character text reveal and header fade-in for Chat feed lines.

Callers measure a line's height with the full text before revealing, so reveal
only ever shortens what is already laid out. Hyperlinks are revealed atomically:
a partial `|c...|H...|h[name]|h|r` sequence is never shown mid-parse.
]]

local addonName, addon = ...

local chat = addon.Chat
local Animations = addon.Animations

--#region ── DB accessor ───────────────────────────────────────────────────────

local function db() return addon.db.profile.chat end

--#endregion

local isSecret = addon.Utils.IsSecretValue

--#region ── Text reveal ────────────────────────────────────────────────────────

--- Cancels any in-flight reveal animation on a FontString.
---@param fs FontString
function chat:CancelReveal(fs)
    if fs and fs._revealTicker then
        fs._revealTicker:Cancel()
        fs._revealTicker = nil
    end
end

--- Cancels a header fade in flight.
---@param fs FontString
function chat:CancelTextFade(fs)
    if fs and fs._fadeAnimation then
        fs._fadeAnimation:Cancel()
        fs._fadeAnimation = nil
    end
end

--- Fades a channel/name label in over `duration` seconds. Gated by the same
--- setting as message reveal; skips text that has already been faded in so
--- re-renders (appending to a group) never replay the animation.
---@param fs FontString
---@param duration number?
function chat:FadeInText(fs, duration)
    if not fs then return end
    self:CancelTextFade(fs)

    local text = fs:GetText() or ''
    if not db().revealText then
        fs._fadedText = text
        fs:SetAlpha(1)
        return
    end
    if fs._fadedText == text then return end
    fs._fadedText = text

    duration = duration or 0.25
    fs:SetAlpha(0)
    local animation
    animation = Animations.Progress(fs, duration, Animations.Linear,
        function(progress)
            fs:SetAlpha(progress)
        end,
        function()
            fs:SetAlpha(1)
            if fs._fadeAnimation == animation then fs._fadeAnimation = nil end
        end
    )
    fs._fadeAnimation = animation
end

--- Sets a FontString's full text immediately, cancelling any reveal in flight.
---@param fs FontString
---@param text string?
function chat:SetTextPlain(fs, text)
    self:CancelReveal(fs)
    fs:SetText(text or '')
end

--- Returns the byte position at which the next reveal step may safely end.
--- Hyperlinks contain WoW markup (for example `|c...|Hitem:...|h[name]|h|r`)
--- that only renders as a link when FontString receives the complete sequence.
--- Keep that sequence in one reveal step so partial markup is never displayed.
---@param text string
---@param start number  first byte of the next reveal step
---@return number
local function nextRevealEnd(text, start)
    local linkStart = start

    -- A standard hyperlink is usually wrapped in a 10-byte |cAARRGGBB code.
    -- Treat the wrapper as part of its link so the color control code is never
    -- revealed by itself.
    local prefix = text:sub(start, start + 9)
    if prefix:match('^|[cC]%x%x%x%x%x%x%x%x') then
        linkStart = start + 10
        -- Inline name highlights must appear with their complete color markup.
        if text:sub(linkStart, linkStart + 1) ~= '|H' then
            local colorEnd = text:find('|r', linkStart, true)
            if colorEnd then return colorEnd + 1 end
        end
    end

    if text:sub(linkStart, linkStart + 1) ~= '|H' then
        return start
    end

    local firstClose = text:find('|h', linkStart + 2, true)
    if not firstClose then return start end
    local secondClose = text:find('|h', firstClose + 2, true)
    if not secondClose then return start end

    local linkEnd = secondClose + 1
    if text:sub(linkEnd + 1, linkEnd + 2):lower() == '|r' then
        linkEnd = linkEnd + 2
    end
    return linkEnd
end

--- Reveals `text` character-by-character when the setting is on. Fonts and
--- width must already be applied; callers measure the returned/current height
--- with the full text before calling this. Hyperlinks are revealed atomically.
---@param fs FontString
---@param text string?
function chat:Reveal(fs, text)
    if not fs then return end
    self:CancelReveal(fs)
    text = text or ''

    if not db().revealText or isSecret(text) then
        fs._revealedText = text
        fs:SetText(text)
        return
    end

    -- Already fully revealed: leave it alone (rebuilds must not re-animate).
    if fs._revealedText == text and fs:GetText() == text then return end
    fs._revealedText = text

    local total = #text
    if total == 0 then
        fs:SetText('')
        return
    end

    local speed = math.max(db().revealSpeed or 44, 1)
    local shown = 0
    fs:SetText('')
    fs._revealTicker = C_Timer.NewTicker(1 / speed, function()
        shown = nextRevealEnd(text, shown + 1)
        if shown >= total then
            chat:CancelReveal(fs)
            fs:SetText(text)
        else
            fs:SetText(text:sub(1, shown))
        end
    end)
end

--#endregion
