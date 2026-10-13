# For controllers whose page is one Admin::EditableBlock (/about/*, /get_involved/*, /archives/*).
module EditableBlockPage
  def page
    @editable_block = Admin::EditableBlock.find_by!(url: @current_path.delete_prefix("/"))
    @title = @editable_block.name

    description = helpers.render_plain(@editable_block.content).squish
    # A nav-redirect block ("EXTERNAL_URL:...") has no prose to describe the page with.
    @meta[:description] = description if description.present? && !description.start_with?(SubpageHelper::EXTERNAL_URL_PREFIX)
  end
end
