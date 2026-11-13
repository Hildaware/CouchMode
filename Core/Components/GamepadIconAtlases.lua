-- Native normal-state atlases from Blizzard SharedXML InputIconTexture.lua.
local _, addon = ...
local atlases = {
    DIRPAD = { Letters = 'gamepad-xbox1-dpadall-normal', Shapes = 'gamepad-ps-dpadall-normal', Reverse = 'gamepad-switch-128x-dpad-all-normal' },
    DIRPADHORIZONTAL = { Letters = 'gamepad-xbox1-dpadleftright-normal', Shapes = 'gamepad-ps-dpadleftright-normal', Reverse = 'gamepad-switch-128x-dpad-leftright-normal' },
    DIRPADVERTICAL = { Letters = 'gamepad-xbox1-dpadupdown-normal', Shapes = 'gamepad-ps-dpadupdown-normal', Reverse = 'gamepad-switch-128x-dpad-updown-normal' },
    PAD1 = { Letters = 'gamepad-xbox1-buttona-normal', Shapes = 'gamepad-ps-buttoncrox-normal', Reverse = 'gamepad-switch-128x-face-b-normal' },
    PAD2 = { Letters = 'gamepad-xbox1-buttonb-normal', Shapes = 'gamepad-ps-buttoncircle-normal', Reverse = 'gamepad-switch-128x-face-a-normal' },
    PAD3 = { Letters = 'gamepad-xbox1-buttonx-normal', Shapes = 'gamepad-ps-buttonsquare-normal', Reverse = 'gamepad-switch-128x-face-y-normal' },
    PAD4 = { Letters = 'gamepad-xbox1-buttony-normal', Shapes = 'gamepad-ps-buttontriangle-normal', Reverse = 'gamepad-switch-128x-face-x-normal' },
    PADBACK = { Letters = 'gamepad-xbox1-view-normal', Shapes = 'gamepad-ps-touchpad-normal', Reverse = 'gamepad-switch-128x-minus-normal' },
    PADDDOWN = { Letters = 'gamepad-xbox1-dpaddown-normal', Shapes = 'gamepad-ps-dpaddown-normal', Reverse = 'gamepad-switch-128x-dpad-down-normal' },
    PADDLEFT = { Letters = 'gamepad-xbox1-dpadleft-normal', Shapes = 'gamepad-ps-dpadleft-normal', Reverse = 'gamepad-switch-128x-dpad-left-normal' },
    PADDRIGHT = { Letters = 'gamepad-xbox1-dpadright-normal', Shapes = 'gamepad-ps-dpadright-normal', Reverse = 'gamepad-switch-128x-dpad-right-normal' },
    PADDUP = { Letters = 'gamepad-xbox1-dpadup-normal', Shapes = 'gamepad-ps-dpadup-normal', Reverse = 'gamepad-switch-128x-dpad-up-normal' },
    PADFORWARD = { Letters = 'gamepad-xbox1-menu-normal', Shapes = 'gamepad-ps-menu-normal', Reverse = 'gamepad-switch-128x-plus-normal' },
    PADLSHOULDER = { Letters = 'gamepad-xbox1-trigger-lb-normal', Shapes = 'gamepad-ps-triggerl1-normal', Reverse = 'gamepad-switch-128x-shoulder-l-normal' },
    PADLSTICK = { Letters = 'gamepad-xbox1-stick-l3-normal', Shapes = 'gamepad-ps-stickl3-normal', Reverse = 'gamepad-switch-128x-stick-l3-normal' },
    PADLSTICKAXIS = { Letters = 'gamepad-xbox1-stick-l-normal', Shapes = 'gamepad-ps-stickl-normal', Reverse = 'gamepad-switch-128x-stick-l-normal' },
    PADLTRIGGER = { Letters = 'gamepad-xbox1-trigger-lt-normal', Shapes = 'gamepad-ps-triggerl2-normal', Reverse = 'gamepad-switch-128x-zl-normal' },
    PADRSHOULDER = { Letters = 'gamepad-xbox1-trigger-rb-normal', Shapes = 'gamepad-ps-triggerr1-normal', Reverse = 'gamepad-switch-128x-shoulder-r-normal' },
    PADRSTICK = { Letters = 'gamepad-xbox1-stick-r3-normal', Shapes = 'gamepad-ps-stickr3-normal', Reverse = 'gamepad-switch-128x-stick-r3-normal' },
    PADRSTICKAXIS = { Letters = 'gamepad-xbox1-stick-r-normal', Shapes = 'gamepad-ps-stickr-normal', Reverse = 'gamepad-switch-128x-stick-r-normal' },
    PADRTRIGGER = { Letters = 'gamepad-xbox1-trigger-rt-normal', Shapes = 'gamepad-ps-triggerr2-normal', Reverse = 'gamepad-switch-128x-zr-normal' },
}

addon.Components.GamepadIconAtlases = atlases
