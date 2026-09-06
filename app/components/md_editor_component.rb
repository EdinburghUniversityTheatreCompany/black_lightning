class MdEditorComponent < ViewComponent::Base
  renders_one :side_content

  LAYOUTS = %i[horizontal vertical].freeze

  # layout: :horizontal is the admin forms — a label column beside the editor,
  # matching simple_form's tailwind_horizontal_form wrapper that every other
  # field on those pages uses. :vertical is the public forms, whose other fields
  # come from the vertical_form wrapper: label above, control full width.
  def initialize(f:, field:, rows: 10, input_field_args: {}, layout: :horizontal)
    raise ArgumentError, "layout must be one of #{LAYOUTS.inspect}" unless LAYOUTS.include?(layout)

    @f = f
    @field = field
    @rows = rows
    @input_field_args = input_field_args
    @layout = layout
  end

  def upload_url
    helpers.markdown_upload_path
  end

  def item_type
    @f.object.class.name
  end

  def item_id
    @f.object.id
  end

  def editor_height
    "#{@rows * 28}px"
  end

  private

  def vertical?
    @layout == :vertical
  end

  def wrapper_class
    vertical? ? "mb-4" : "flex flex-wrap mb-4 items-start"
  end

  # nil so content_tag omits the attribute rather than emitting class="".
  def control_wrapper_class
    vertical? ? nil : "w-full md:w-9/12 px-2"
  end

  # The horizontal label sits in a styled column, so the <label> carries nothing
  # itself. Stacked, it is the field's own label and takes the same rules its
  # siblings get from `col-form-label` in bootstrap_compat.css.
  def label_class
    vertical? ? FormStyles::LABEL : nil
  end
end
