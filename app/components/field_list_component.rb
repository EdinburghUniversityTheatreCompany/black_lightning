# The label/value list under a show page's card. `fields` maps label => value:
# a printable value renders inline, a Hash naming a `:type` gets a block of its own.
class FieldListComponent < ViewComponent::Base
  MARKDOWN = "markdown".freeze
  IMAGE    = "image".freeze
  CONTENT  = "content".freeze

  # admin_site only controls whether an image field links its original for download.
  def initialize(fields:, admin_site: false)
    @fields = fields
    @admin_site = admin_site
  end

  private

  # A nil value hides the field; a caller wanting a placeholder substitutes one.
  def visible_fields
    @fields.reject { |_label, value| value.nil? }
  end

  def title_for(label)
    label.is_a?(Symbol) ? label.to_s.titleize : label
  end

  def block_field?(value)
    value.is_a?(Hash)
  end

  # A generated placeholder is not a real image: not shown, not offered for download.
  def real_image?(value)
    image = value[:image]
    image.attached? && !image.filename.to_s.starts_with?(ActiveStorageHelper::PREFIX)
  end

  def downloadable?
    @admin_site
  end

  def inline_value(value)
    [ true, false ].include?(value) ? helpers.bool_text(value) : value
  end
end
