local addonName = ...

-- AceGUI's embedded checkbox widget still calls this legacy global. WoW
-- Forever removed it, while the texture method it delegated to remains.
if type(_G.SetDesaturation) ~= "function" then
    function _G.SetDesaturation(texture, desaturated)
        texture:SetDesaturated(desaturated)
    end
end
