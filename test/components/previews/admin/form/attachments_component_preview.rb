class Admin::Form::AttachmentsComponentPreview < Admin::ApplicationComponentPreview
  # Attachments section on a Show form
  def default
    render_with_template(locals: { record: Show.first! })
  end
end
