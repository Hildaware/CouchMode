---@meta

--[[
    Utilize this file specifically for telling the IDE that the following functions are legit.
    It literally does nothing but make the squigglies go bye bye.
]]

---@class Size
---@field width number
---@field height number

---#region Session

---@class BagData
---@field TotalCount number
---@field Count number

---@class ViewData: BagData
---@field Resolved number
---@field ReagentCount? number
---@field Bags BagData[]

---#endregion

--#region Bank Header

---@class BankHeaderToggles: Frame
---@field bank Button
---@field warbank Button

---@class NewBankHeader: Frame
---@field purchase SimpleButtonFrame
---@field deposit SimpleButtonFrame
---@field reagentCheck CheckButton
---@field money FontString

---@class BankHeaderFrame: Frame
---@field Update function
---@field toggles BankHeaderToggles
---@field warbankHeader NewBankHeader

--#endregion
