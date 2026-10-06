class MdEditorComponent < ViewComponent::Base
  renders_one :side_content

  LAYOUTS = %i[horizontal vertical].freeze

  # layout: :horizontal is the admin forms (label column beside the editor, like the
  # other fields there); :vertical is the public forms (label above, full width).
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

  # Horizontal: the column div is already styled. Vertical: the label takes the
  # rules its siblings get from `col-form-label` in bootstrap_compat.css.
  def label_class
    vertical? ? FormStyles::LABEL : nil
  end
end
