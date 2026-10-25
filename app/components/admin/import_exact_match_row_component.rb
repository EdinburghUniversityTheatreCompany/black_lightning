# An import preview row matched to exactly one existing user, and what confirming does with it.
# The block adds a note under the user's name.
class Admin::ImportExactMatchRowComponent < ViewComponent::Base
  # value: what the row matched on, or adds (an email, an id, a position), in its own column.
  # action: the decision the row posts, or nil for a row confirming leaves alone.
  # show_row_id: the id the row carried, under its name.
  def initialize(item:, value:, badge:, badge_type:, action: nil, row_class: nil, show_row_id: false)
    @item = item
    @value = value
    @badge = badge
    @badge_type = badge_type
    @action = action
    @row_class = row_class
    @show_row_id = show_row_id
  end

  private

  def row
    @item[:row]
  end

  def user
    @item[:existing_user]
  end
end
