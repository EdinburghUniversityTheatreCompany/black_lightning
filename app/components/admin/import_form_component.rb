class Admin::ImportFormComponent < ViewComponent::Base
  def initialize(preview_path:, cancel_path:, cancel_text:, columns_description:, placeholder_text:)
    @preview_path = preview_path
    @cancel_path = cancel_path
    @cancel_text = cancel_text
    @columns_description = columns_description
    @placeholder_text = placeholder_text
  end
end
