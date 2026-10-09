class MdEditorComponent < ViewComponent::Base
  renders_one :side_content

  LAYOUTS = %i[horizontal vertical].freeze

  # layout: :horizontal is the admin forms (label column beside the editor, like the
  # other fields there); :vertical is the public forms (label above, full width).
  # uploads: false hides image upload, which needs a signed-in user (MarkdownController#upload).
  def initialize(f:, field:, rows: 10, input_field_args: {}, layout: :horizontal, uploads: true)
    raise ArgumentError, "layout must be one of #{LAYOUTS.inspect}" unless LAYOUTS.include?(layout)

    @f = f
    @field = field
    @rows = rows
    @input_field_args = input_field_args
    @layout = layout
    @uploads = uploads
  end

  private

  def editor_height
    "#{@rows * 28}px"
  end

  # Without an upload URL the editor offers no image upload at all.
  def editor_data
    data = {
      controller: "markdown-editor",
      markdown_editor_height_value: editor_height,
      markdown_editor_primary_button_class_value: ButtonComponent.classes_for(variant: :primary, size: :sm),
      markdown_editor_secondary_button_class_value: ButtonComponent.classes_for(variant: :secondary, size: :sm)
    }
    return data unless @uploads

    data.merge(
      markdown_editor_upload_url_value: helpers.markdown_upload_path,
      markdown_editor_item_type_value: @f.object.class.name,
      markdown_editor_item_id_value: @f.object.id
    )
  end

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
end
