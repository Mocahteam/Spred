--//=============================================================================

--- ComboBox module

--- ComboBox fields.
-- Inherits from Control.
-- @see control.Control
-- @table ComboBox
-- @tparam {"item1","item2",...} items table of items in the ComboBox, (default {"items"})
-- @int[opt=1] selected id of the selected item
-- @tparam {func1,func2,...} OnSelect listener functions for selected item changes, (default {})
ComboBox = Button:Inherit{
  classname = "combobox",
  caption = 'combobox',
  defaultWidth  = 70,
  defaultHeight = 20,
  items = { "items" },
  selected = 1,
  OnSelect = {},
  maxDropDownHeight = 200,
  minDropDownHeight = 50,
  maxDropDownWidth = 500,
  minDropDownWidth = 50,
}

local ComboBoxScrollPanel = ScrollPanel:Inherit{
  classname = "combobox_scrollpanel",
  horizontalScrollbar = false
}
function ComboBoxScrollPanel:FocusUpdate()
  local screen = self:FindParent("screen")
  -- Check if we lose the focus
  if (not self.state.focused and not CompareLinks(screen:GetFocusedControl(), self)) then
    local needToClose = true
    --Check if one of the items is focused
    local stackPanel = self.children[1]
    local items = stackPanel.children
    for i=1,#items do
      if items[i].state.focused then
        needToClose = false
      end
    end
    if needToClose then
      self.parent.mainCombo:_CloseWindow()
    end
  end
end

local ComboBoxStackPanel  = StackPanel:Inherit{
  classname = "combobox_stackpanel",
  autosize = true,
  resizeItems = false,
  borderThickness = 0,
  padding = {0,0,0,0},
  itemPadding = {0,0,0,0},
  itemMargin = {0,0,0,0}
}
local ComboBoxItem        = Button:Inherit{
  classname = "combobox_item"
}

local this = ComboBox
local inherited = this.inherited

function ComboBox:New(obj)
  obj = inherited.New(self,obj)
  obj:Select(obj.selected or 1)
  return obj
end

--- Selects an item by id
-- @int itemIdx id of the item to be selected
function ComboBox:Select(itemIdx)
  if (type(itemIdx)=="number") then
    local item = self.items[itemIdx]
    if not item then
       return
    end
    self.selected = itemIdx
    self.caption = ""

    if type(item) == "string" then
        self.caption = item
    end
    self:CallListeners(self.OnSelect, itemIdx, true)
    self:Invalidate()
    self:UpdateLayout()
  end
  --FIXME add Select(name)
end

function ComboBox:_CloseWindow()
  if self._dropDownWindow then
    self._dropDownWindow:Dispose()
    self._dropDownWindow = nil
  end
  if (self.state.pressed) then
    self.state.pressed = false
    self:Invalidate()
    return self
  end
end

function ComboBox:MouseDown(...)
  self.state.pressed = true
  if not self._dropDownWindow then
    -- drop down window doesn't exist => create it
    local sx,sy = self:LocalToScreen(0,0)

    local labels = {}
    local labelHeight = self.height
    local labelPadding = self.padding

    local width = math.max(self.width, self.minDropDownWidth)
    local height = 10
    for i = 1, #self.items do
      local item = self.items[i]
      if type(item) == "string" then
          local newBtn = ComboBoxItem:New {
            caption = item,
            width = '100%',
            height = labelHeight,
            padding = labelPadding,
            state = {selected = (i == self.selected)},
            font = {
              font = self.font.font,
              autoAdjust = self.font.autoAdjust
            },
            OnMouseUp = { function()
              self:Select(i)
              self:_CloseWindow()
            end }
          }
          labels[#labels+1] = newBtn
          height = height + labelHeight
          width = math.max(width, newBtn.font:GetTextWidth(item))
      else
          labels[#labels+1] = item
          item.OnMouseUp = { function()
              self:Select(i)
              self:_CloseWindow()
          end }
          width = math.max(width, item.width + 5)
          height = height + item.height -- FIXME: what if this height is relative?
      end
    end

    height = math.max(self.minDropDownHeight, height)
    height = math.min(self.maxDropDownHeight, height)
    width = math.min(self.maxDropDownWidth, width)

    local screen = self:FindParent("screen")
    local y = sy + self.height
    if y + height > screen.height then
      y = sy - height
    end
	
    width = math.min(screen.width, width)

    self._dropDownWindow = ComboBoxWindow:New{
      mainCombo = self,
      selected = self.selected,
      parent = screen,
      width  = width,
      height = height,
      x = width == screen.width and 0 or sx - (width - self.width),
      y = y,
      children = {
        ComboBoxScrollPanel:New{
          width  = "100%",
          height = "100%",
          children = {
            ComboBoxStackPanel:New{
              width = '100%',
              children = labels,
            },
          },
        }
      }
    }
  else
    -- drop down window exists => close it
    self:_CloseWindow()
  end

  self:Invalidate()
  return self
end

function ComboBox:MouseUp(...)
  self:Invalidate()
  return self
  -- this exists to override Button:MouseUp so it doesn't modify .state.pressed
end

function ComboBox:FocusUpdate()
  local screen = self:FindParent("screen")
  -- Check if drop down window exists and doesn't have focus
  if self._dropDownWindow and not CompareLinks(screen:GetFocusedControl(), self._dropDownWindow) then
    -- Give focus to drop down window
    screen:FocusControl(self._dropDownWindow)
  end
end
