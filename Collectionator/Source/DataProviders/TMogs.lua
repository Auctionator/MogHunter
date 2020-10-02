local TMOG_TABLE_LAYOUT = {
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerParameters = { "name" },
    headerText = AUCTIONATOR_L_NAME,
    cellTemplate = "AuctionatorItemKeyCellTemplate",
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerText = COLLECTIONATOR_L_CHOICES,
    headerParameters = { "quantity" },
    cellTemplate = "AuctionatorStringCellTemplate",
    cellParameters = { "quantity" },
    width = 70
  },
  {
    headerTemplate = "AuctionatorStringColumnHeaderTemplate",
    headerText = AUCTIONATOR_L_UNIT_PRICE,
    headerParameters = { "price" },
    cellTemplate = "AuctionatorPriceCellTemplate",
    cellParameters = { "price" },
    width = 150,
  },
}

CollectionatorTMogDataProviderMixin = CreateFromMixins(AuctionatorDataProviderMixin)

function CollectionatorTMogDataProviderMixin:OnLoad()
  AuctionatorDataProviderMixin.OnLoad(self)

  Auctionator.EventBus:Register(self, {
    Collectionator.Events.SourceLoadStart,
    Collectionator.Events.SourceLoadEnd,
  })

  self:GetParent().RefreshButton:Hide()

  self.processCountPerUpdate = 500
  self.dirty = false
end

function CollectionatorTMogDataProviderMixin:OnShow()
  if self.dirty then
    self:Refresh()
  end
end

function CollectionatorTMogDataProviderMixin:ReceiveEvent(eventName, eventData, eventData2)
  if eventName == Collectionator.Events.SourceLoadStart then
    self.onSearchStarted()
    self:GetParent().RefreshButton:Hide()
    self:GetParent().NoFullScanText:Hide()
  elseif eventName == Collectionator.Events.SourceLoadEnd then
    self.sources = eventData
    self.fullScan = eventData2

    if #self.sources > 0 then
      self:GetParent().RefreshButton:Show()
    end

    self.dirty = true
    if self:IsShown() then
      self:Refresh()
    end
  end
end

local COMPARATORS = {
  price = Auctionator.Utilities.NumberComparator,
  name = Auctionator.Utilities.StringComparator,
  quantity = Auctionator.Utilities.NumberComparator,
}

function CollectionatorTMogDataProviderMixin:Sort(fieldName, sortDirection)
  local comparator = COMPARATORS[fieldName](sortDirection, fieldName)

  table.sort(self.results, function(left, right)
    return comparator(left, right)
  end)

  self.onUpdate(self.results)
end

local function ColorName(link, name)
  local qualityColor = Auctionator.Utilities.GetQualityColorFromLink(link)
  return "|c" .. qualityColor .. name .. "|r"
end

local function GroupedBySourceID(array)
  local results = {}

  for _, info in ipairs(array) do
    if results[info.id] == nil then
      results[info.id] = {}
    end
    table.insert(results[info.id], info)
  end

  return results
end

local function GroupedByVisualID(array)
  local results = {}

  for _, info in ipairs(array) do
    if results[info.visual] == nil then
      results[info.visual] = {}
    end
    table.insert(results[info.visual], info)
  end

  return results
end

local function SortByPrice(array, fullScan)
  table.sort(array, function(a, b)
    return fullScan[a.index].replicateInfo[10] < fullScan[b.index].replicateInfo[10]
  end)
end
local function CombineForCheapest(array, fullScan)
  SortByPrice(array, fullScan)

  array[1].quantity = #array

  return array[1]
end

local function SelectFirstItemIDs(array, fullScan)
  SortByPrice(array, fullScan)

  local haveSeen = {}
  local result = {}
  for index, info in ipairs(array) do
    local itemID = fullScan[info.index].replicateInfo[17]
    if haveSeen[itemID] == nil then
      haveSeen[itemID] = info
      info.quantity = 1
      table.insert(result, info)
    else
      haveSeen[itemID].quantity = haveSeen[itemID].quantity + 1
    end
  end

  return result
end

function CollectionatorTMogDataProviderMixin:Refresh()
  local isUniques = self:GetParent().UniquesOnly:GetChecked()
  self.dirty = false
  self:Reset()

  if self.sources == nil or #self.sources == 0 then
    return
  end

  self.onSearchStarted()

  local grouped
  if isUniques then
    grouped = GroupedByVisualID(self.sources)
  else
    grouped = GroupedBySourceID(self.sources)
  end

  local filteredOnly = {}
  local fullScan = self.fullScan

  if self:GetParent().ShowAllItems:GetChecked() then
    for _, array in pairs(grouped) do
      for _, item in ipairs(SelectFirstItemIDs(array, fullScan)) do
        table.insert(filteredOnly, item)
      end
    end
  else
    for _, array in pairs(grouped) do
      table.insert(filteredOnly, CombineForCheapest(array, fullScan))
    end
  end
  Auctionator.Debug.Message("CollectionatorTMogDataProviderMixin:Refresh", "filtered", #filteredOnly)

  local results = {}

  for _, sourceInfo in ipairs(filteredOnly) do
    local info = fullScan[sourceInfo.index]

    local check = true

    if isUniques then
      for _, altSource in ipairs(sourceInfo.set) do
        if self:GetParent().CharacterOnly:GetChecked() then
          check = check and not C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(altSource)
        else
          local tmogInfo = C_TransmogCollection.GetSourceInfo(altSource)
          check = check and not tmogInfo.isCollected
        end
      end
    else
      if self:GetParent().CharacterOnly:GetChecked() then
        check = not C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceInfo.id)
      else
        local tmogInfo = C_TransmogCollection.GetSourceInfo(sourceInfo.id)
        check = not tmogInfo.isCollected
      end
    end

    if self:GetParent().CharacterOnly:GetChecked() then
      check = check and C_TransmogCollection.PlayerKnowsSource(sourceInfo.id)
    else
      check = check and info.replicateInfo[4] > 1
    end

    if check then
      table.insert(results, {
        index = sourceInfo.index,
        itemName = ColorName(info.itemLink, info.replicateInfo[1]),
        name = info.replicateInfo[1],
        quantity = sourceInfo.quantity,
        price = info.replicateInfo[10] or info.replicateInfo[11],
        itemLink = info.itemLink, -- Used for tooltips
        iconTexture = info.replicateInfo[2],
      })
    end
  end
  self:AppendEntries(results, true)
end

function CollectionatorTMogDataProviderMixin:UniqueKey(entry)
  return tostring(entry.index)
end

function CollectionatorTMogDataProviderMixin:GetTableLayout()
  return TMOG_TABLE_LAYOUT
end

function CollectionatorTMogDataProviderMixin:GetRowTemplate()
  return "CollectionatorTMogRowTemplate"
end
