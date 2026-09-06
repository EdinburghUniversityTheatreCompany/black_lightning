# The label/value list a show page renders under its card. `fields` is an
# ordered Hash (or pairs) of label => value, where a value is either something
# printable — rendered inline beside its label — or a Hash naming a `:type`,
# which gets a heading and a block of its own.
class FieldListComponent < ViewComponent::Base
  MARKDOWN = "markdown".freeze
  IMAGE    = "image".freeze
  CONTENT  = "content".freeze

  # admin_site only decides whether an image field offers its original for
  # download; it was an @admin_site read from inside the markup.
  def initialize(fields:, admin_site: false)
    @fields = fields
    @admin_site = admin_site
  end

  private

  # A nil value hides the field entirely. To show a placeholder instead, the
  # caller substitutes one where it builds the spec.
  def visible_fields
    @fields.reject { |_label, value| value.nil? }
  end

  def title_for(label)
    label.is_a?(Symbol) ? label.to_s.titleize : label
  end

  def block_field?(value)
    value.is_a?(Hash)
  end

  # A record with no image of its own carries a generated placeholder, which is
  # not worth showing or offering for download.
  def real_image?(value)
    image = value[:image]
    image.attached? && !image.filename.to_s.starts_with?(ActiveStorageHelper::PREFIX)
  end

  def downloadable?
    @admin_site
  end

  # Booleans read better as words than as true/false.
  def inline_value(value)
    [ true, false ].include?(value) ? helpers.bool_text(value) : value
  end
end
