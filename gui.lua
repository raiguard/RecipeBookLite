local flib_dictionary = require("__flib__/dictionary-lite")
local flib_format = require("__flib__/format")
local flib_gui = require("__flib__/gui-lite")
local flib_math = require("__flib__/math")

--- @alias InfoType
--- | "ingredient"
--- | "product"

--- @param num number
--- @return string
local function format_number(num)
  return flib_format.number(flib_math.round(num, 0.01))
end

local function build_dictionaries()
  flib_dictionary.new("search")
  for _, item in pairs(game.item_prototypes) do
    flib_dictionary.add("search", "item/" .. item.name, { "?", item.localised_name, item.name })
  end
  for _, fluid in pairs(game.fluid_prototypes) do
    flib_dictionary.add("search", "fluid/" .. fluid.name, { "?", fluid.localised_name, fluid.name })
  end
end

--- @param obj Ingredient|Product
--- @param include_icon boolean?
--- @return LocalisedString
local function build_caption(obj, include_icon)
  --- @type LocalisedString
  local caption = { "", "            " }
  if include_icon then
    caption[#caption + 1] = "[img=" .. obj.type .. "/" .. obj.name .. "]  "
  end
  if obj.probability and obj.probability < 1 then
    caption[#caption + 1] = {
      "",
      "[font=default-semibold]",
      { "format-percent", flib_math.round(obj.probability * 100, 0.01) },
      "[/font] ",
    }
  end
  if obj.amount then
    caption[#caption + 1] = {
      "",
      "[font=default-semibold]",
      format_number(obj.amount),
      " ×[/font]  ",
    }
  elseif obj.amount_min and obj.amount_max then
    caption[#caption + 1] = {
      "",
      "[font=default-semibold]",
      format_number(obj.amount_min),
      " - ",
      format_number(obj.amount_max),
      " ×[/font]  ",
    }
  end
  -- TODO: Optimize this
  caption[#caption + 1] = game[obj.type .. "_prototypes"][obj.name].localised_name

  return caption
end

-- This is needed in update_info_page
local on_search_result_clicked

--- @param self GuiData
local function update_info_page(self)
  local recipe = self.recipes[self.index]

  self.elems.info_recipe_count_label.caption = "[" .. self.index .. "/" .. #self.recipes .. "]"
  self.elems.info_type_label.caption = self.info_type == "product" and "Product of" or "Ingredient in"

  local ingredients_frame = self.elems.info_ingredients_frame
  ingredients_frame.clear()
  flib_gui.add(ingredients_frame, {
    type = "sprite-button",
    style = "rbl_list_box_item",
    sprite = "quantity-time",
    caption = { "", "            ", recipe.energy },
  })
  local item_ingredients = 0
  for _, ingredient in pairs(recipe.ingredients) do
    if ingredient.type == "item" then
      item_ingredients = item_ingredients + 1
    end
    flib_gui.add(ingredients_frame, {
      type = "sprite-button",
      style = "rbl_list_box_item",
      sprite = ingredient.type .. "/" .. ingredient.name,
      caption = build_caption(ingredient),
      handler = on_search_result_clicked,
    })
  end

  local products_frame = self.elems.info_products_frame
  products_frame.clear()
  for _, product in pairs(recipe.products) do
    flib_gui.add(products_frame, {
      type = "sprite-button",
      style = "rbl_list_box_item",
      sprite = product.type .. "/" .. product.name,
      caption = build_caption(product),
      handler = on_search_result_clicked,
    })
  end

  local made_in_frame = self.elems.info_made_in_frame
  made_in_frame.clear()
  flib_gui.add(made_in_frame, {
    type = "sprite-button",
    style = "slot_button",
    sprite = "utility/hand",
    hovered_sprite = "utility/hand_black",
    clicked_sprite = "utility/hand_black",
    number = recipe.energy,
  })
  for _, machine in
    pairs(game.get_filtered_entity_prototypes({
      { filter = "crafting-category", crafting_category = recipe.category },
    }))
  do
    local ingredient_count = machine.ingredient_count
    if ingredient_count == 0 or ingredient_count >= item_ingredients then
      flib_gui.add(made_in_frame, {
        type = "sprite-button",
        style = "slot_button",
        sprite = "entity/" .. machine.name,
        number = recipe.energy / machine.crafting_speed,
      })
    end
  end

  local unlocked_by_frame = self.elems.info_unlocked_by_frame
  unlocked_by_frame.clear()
  for _, technology in
    pairs(game.get_filtered_technology_prototypes({ { filter = "unlocks-recipe", recipe = recipe.name } }))
  do
    flib_gui.add(
      unlocked_by_frame,
      { type = "sprite-button", style = "slot_button", sprite = "technology/" .. technology.name }
    )
  end
end

--- @param e EventData.on_gui_text_changed
local function on_search_textfield_changed(e)
  local text = string.lower(e.text)
  local self = global.gui[e.player_index]
  local dictionary = flib_dictionary.get(e.player_index, "search") or {}
  for _, button in pairs(self.elems.search_table.children) do
    local search_key = dictionary[button.sprite] or button.name
    button.visible = not not string.find(string.lower(search_key), text, nil, true)
  end
end

--- @param e EventData.on_gui_click
on_search_result_clicked = function(e)
  local result = e.element.sprite
  local result_type, result_name = string.match(result, "(.-)/(.*)")
  local self = global.gui[e.player_index]
  self.info_type = e.button == defines.mouse_button_type.left and "product" or "ingredient"

  local recipes = game.get_filtered_recipe_prototypes({
    {
      filter = "has-" .. self.info_type .. "-" .. result_type,
      elem_filters = {
        { filter = "name", name = result_name },
      },
    },
  })
  local recipes_array = {}
  for _, recipe in pairs(recipes) do
    recipes_array[#recipes_array + 1] = recipe
  end
  if not next(recipes_array) then
    self.player.create_local_flying_text({ text = "No recipes to display", create_at_cursor = true })
    self.player.play_sound({ path = "utility/cannot_build" })
    return
  end

  self.recipes = recipes_array
  self.index = 1

  local prototype = game[result_type .. "_prototypes"][result_name]
  self.elems.info_result_caption.sprite = result
  self.elems.info_result_caption.caption = { "", "            ", prototype.localised_name }
  self.elems.search_pane.visible = false
  self.elems.info_pane.visible = true
  self.elems.back_to_search_button.visible = true

  update_info_page(self)
end

--- @param e EventData.on_gui_click
local function on_back_to_search_clicked(e)
  local self = global.gui[e.player_index]
  self.elems.back_to_search_button.visible = false
  self.elems.info_pane.visible = false
  self.elems.search_pane.visible = true
end

--- @param e EventData.on_gui_click
local function on_recipe_nav_clicked(e)
  local self = global.gui[e.player_index]
  self.index = self.index + e.element.tags.nav_offset
  if self.index == 0 then
    self.index = #self.recipes --[[@as uint]]
  elseif self.index > #self.recipes then
    self.index = 1
  end
  update_info_page(self)
end

--- @param player LuaPlayer
local function create_gui(player)
  local buttons = {}
  for _, item in pairs(game.item_prototypes) do
    table.insert(buttons, {
      type = "sprite-button",
      style = "slot_button",
      sprite = "item/" .. item.name,
      tooltip = item.localised_name,
      handler = on_search_result_clicked,
    })
  end
  for _, fluid in pairs(game.fluid_prototypes) do
    table.insert(buttons, {
      type = "sprite-button",
      style = "slot_button",
      sprite = "fluid/" .. fluid.name,
      tooltip = fluid.localised_name,
      handler = on_search_result_clicked,
    })
  end
  local elems = flib_gui.add(player.gui.screen, {
    type = "frame",
    name = "rbl_main_window",
    direction = "vertical",
    elem_mods = { auto_center = true },
    {
      type = "flow",
      style = "flib_titlebar_flow",
      drag_target = "rbl_main_window",
      { type = "label", style = "frame_title", caption = "Recipe Book Lite", ignored_by_interaction = true },
      { type = "empty-widget", style = "flib_titlebar_drag_handle", ignored_by_interaction = true },
      {
        type = "sprite-button",
        name = "back_to_search_button",
        style = "frame_action_button",
        sprite = "rbl_nav_backward_white",
        hovered_sprite = "rbl_nav_backward_black",
        clicked_sprite = "rbl_nav_backward_black",
        tooltip = "Back to search",
        visible = false,
        handler = on_back_to_search_clicked,
      },
      {
        type = "sprite-button",
        style = "frame_action_button",
        sprite = "utility/close_white",
        hovered_sprite = "utility/close_black",
        clicked_sprite = "utility/close_black",
      },
    },
    {
      type = "frame",
      name = "search_pane",
      style = "inside_deep_frame",
      direction = "vertical",
      {
        type = "frame",
        style = "subheader_frame",
        style_mods = { horizontally_stretchable = true },
        { type = "label", style = "subheader_caption_label", caption = "Search" },
        { type = "empty-widget", style = "flib_horizontal_pusher" },
        {
          type = "textfield",
          name = "search_textfield",
          lose_focus_on_confirm = true,
          clear_and_focus_on_right_click = true,
          handler = { [defines.events.on_gui_text_changed] = on_search_textfield_changed },
        },
      },
      {
        type = "scroll-pane",
        style = "flib_naked_scroll_pane_no_padding",
        style_mods = { maximal_height = 40 * 12, width = 40 * 12 + 12 },
        { type = "table", name = "search_table", style = "slot_table", column_count = 12, children = buttons },
      },
    },
    {
      type = "frame",
      name = "info_pane",
      style = "inside_shallow_frame",
      direction = "vertical",
      visible = false,
      {
        type = "frame",
        style = "subheader_frame",
        style_mods = { horizontally_stretchable = true },
        {
          type = "sprite-button",
          name = "info_result_caption",
          style = "rbl_subheader_caption_button",
          enabled = false,
        },
        { type = "empty-widget", style = "flib_horizontal_pusher" },
        { type = "label", name = "info_type_label", style = "bold_label" },
        {
          type = "label",
          name = "info_recipe_count_label",
          style = "info_label",
          style_mods = { font = "default-semibold", right_margin = 4 },
        },
        {
          type = "sprite-button",
          style = "tool_button",
          style_mods = { padding = 0, size = 24, top_margin = 1 },
          sprite = "rbl_nav_backward_black",
          tooltip = "Previous recipe",
          tags = { nav_offset = -1 },
          handler = on_recipe_nav_clicked,
        },
        {
          type = "sprite-button",
          style = "tool_button",
          style_mods = { padding = 0, size = 24, top_margin = 1, right_margin = 4 },
          sprite = "rbl_nav_forward_black",
          tooltip = "Next recipe",
          tags = { nav_offset = 1 },
          handler = on_recipe_nav_clicked,
        },
      },
      {
        type = "flow",
        style_mods = { padding = 12, top_padding = 8, vertical_spacing = 12 },
        direction = "vertical",
        {
          type = "flow",
          style_mods = { horizontal_spacing = 12 },
          {
            type = "flow",
            direction = "vertical",
            {
              type = "label",
              style = "caption_label",
              caption = "Ingredients",
            },
            {
              type = "frame",
              name = "info_ingredients_frame",
              style = "deep_frame_in_shallow_frame",
              style_mods = { width = 240 },
              direction = "vertical",
            },
          },
          {
            type = "flow",
            direction = "vertical",
            {
              type = "label",
              style = "caption_label",
              caption = "Products",
            },
            {
              type = "frame",
              name = "info_products_frame",
              style = "deep_frame_in_shallow_frame",
              style_mods = { width = 240 },
              direction = "vertical",
            },
          },
        },
        {
          type = "flow",
          style_mods = { vertical_align = "center", horizontal_spacing = 12 },
          { type = "label", style = "caption_label", caption = "Made in" },
          { type = "frame", name = "info_made_in_frame", style = "slot_button_deep_frame" },
        },
        {
          type = "flow",
          name = "info_unlocked_by_flow",
          style_mods = { vertical_align = "center", horizontal_spacing = 12 },
          { type = "label", style = "caption_label", caption = "Unlocked by" },
          { type = "frame", name = "info_unlocked_by_frame", style = "slot_button_deep_frame" },
        },
      },
    },
  })

  --- @class GuiData
  global.gui[player.index] = {
    elems = elems,
    --- @type uint
    index = 1,
    --- @type InfoType
    info_type = "product",
    --- @type LuaRecipePrototype[]?
    recipes = nil,
    player = player,
  }
end

--- @param e EventData.on_player_created
local function on_player_created(e)
  local player = game.get_player(e.player_index)
  if not player then
    return
  end
  create_gui(player)
end

local gui = {}

gui.on_init = function()
  --- @type table<uint, GuiData>
  global.gui = {}
  build_dictionaries()
end
gui.on_configuration_changed = build_dictionaries

gui.events = {
  [defines.events.on_player_created] = on_player_created,
}

flib_gui.add_handlers({
  on_back_to_search_clicked = on_back_to_search_clicked,
  on_recipe_nav_clicked = on_recipe_nav_clicked,
  on_search_result_clicked = on_search_result_clicked,
  on_search_textfield_changed = on_search_textfield_changed,
})

return gui