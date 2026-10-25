# One bucket of an import preview: a card headed by the bucket's name, its row count and what
# confirming does with its rows, over a table of the rows. The rows go in as the block, which
# gets the component (loop over `section.items`). An empty bucket renders nothing.
class Admin::ImportPreviewSectionComponent < ViewComponent::Base
  # A light count badge vanishes into a warning card's yellow header.
  BADGE_TYPES = { warning: :dark }.freeze

  attr_reader :items

  # headers: the column labels; a [label, width] pair fixes that column's width.
  def initialize(items:, title:, variant:, hint:, headers:)
    @items = items
    @title = title
    @variant = variant
    @hint = hint
    @headers = headers
  end

  def render?
    @items.any?
  end

  private

  def badge_type
    BADGE_TYPES.fetch(@variant, :light)
  end
end
