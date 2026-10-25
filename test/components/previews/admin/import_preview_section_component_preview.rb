class Admin::ImportPreviewSectionComponentPreview < Admin::ApplicationComponentPreview
  # A bucket of two rows; the rows are the block's.
  def default
    render_with_template
  end
end
