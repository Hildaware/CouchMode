local _, addon = ...
local qol = addon.QualityOfLife
local EditMode = addon.EditMode
local function db() return addon.db.profile.qualityOfLife.quickThanks end

function qol:GetDefaults()
    return {
        qualityOfLife = {
            quickThanks = { enabled = true, positions = {}, fontFace = 'Arial Narrow' },
        },
    }
end

function qol:GetOptions()
    return 'qualityOfLife', {
        name = 'Quality of Life', type = 'group', order = 13, childGroups = 'tab',
        hidden = function() return not addon.Utils.IsFlavor('forever') end,
        args = { quickThanks = self:BuildQuickThanksOptions() },
    }
end

function qol:BuildQuickThanksOptions()
    return {
        name = 'Quick Thanks', type = 'group', order = 55,
        hidden = function() return not addon.Utils.IsFlavor('forever') end,
        args = {
            description = {
                type = 'description', order = 1,
                name = 'When someone outside your group gives you a buff lasting at least five minutes, '
                    .. 'a prompt offers to say Thanks! for five seconds, including during combat. '
                    .. 'Further buffs restart the countdown. Press your Chat Composer binding or click the prompt '
                    .. 'to say Thanks! While the prompt is visible, that binding sends thanks instead of opening '
                    .. 'the Composer. Nothing is sent automatically.',
            },
            enabled = {
                type = 'toggle', name = 'Enable Quick Thanks', order = 2,
                get = function() return db().enabled end,
                set = function(_, value)
                    db().enabled = value
                    qol:ConfigureQuickThanks()
                end,
            },
            font = {
                type = 'select', name = 'Font', order = 2.5,
                values = addon.Media.GetFontOptions,
                get = function() return db().fontFace end,
                set = function(_, value)
                    db().fontFace = value
                    qol:RefreshQuickThanksBinding()
                end,
            },
            unavailable = {
                type = 'description', order = 3,
                name = 'Buff detection is unavailable on this client: readable auras and combat-log events are required.',
                hidden = function()
                    return qol:QuickThanksAvailable()
                        and addon.Utils.EventExists('COMBAT_LOG_EVENT_UNFILTERED') ~= false
                end,
            },
            preview = {
                type = 'execute', name = 'Preview Quick Thanks', order = 4,
                desc = 'Show the card for five seconds. Clicking or pressing the binding previews the confirmation without sending chat.',
                disabled = function() return not qol:IsQuickThanksEnabled() end,
                func = function() qol:ShowQuickThanks('preview', 'Preview', true, 1243) end,
            },
            move = {
                type = 'execute', name = 'Move Quick Thanks', order = 5,
                desc = 'Open Edit Mode, then drag CouchMode Quick Thanks. Position is saved for each layout.',
                disabled = function()
                    return not qol:IsQuickThanksEnabled() or not qol.quickThanksEditRegistered
                        or (InCombatLockdown and InCombatLockdown())
                        or not EditModeManagerFrame
                        or (not EditModeManagerFrame:IsShown() and not EditModeManagerFrame:CanEnterEditMode())
                end,
                func = function() EditMode:EditLayout('QualityOfLife') end,
            },
        },
    }
end
