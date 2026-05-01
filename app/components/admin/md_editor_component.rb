class Admin::MdEditorComponent < ViewComponent::Base
  renders_one :side_content

  def initialize(f:, field:, rows: 10, input_field_args: {})
    @f = f
    @field = field
    @rows = rows
    @input_field_args = input_field_args
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
end
