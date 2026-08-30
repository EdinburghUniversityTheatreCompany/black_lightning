##
# For the controllers whose whole page is one Admin::EditableBlock -- /about/*,
# /get_involved/* and /archives/*.
#
# The block already knows what the page is called and what it says, so the page has no reason to
# fall back to <title>Bedlam Theatre</title> and the site-wide boilerplate description. Twenty
# pages did exactly that.
##
module EditableBlockPage
  extend ActiveSupport::Concern

  private

  def set_meta_from_editable_block
    return if @editable_block.nil?

    @title = @editable_block.name.presence || @title

    description = helpers.render_plain(@editable_block.content).squish
    # A block whose body is only a nav redirect has no prose to describe the page with, and
    # "EXTERNAL_URL https://..." describes it worse than the site description does.
    @meta[:description] = description if description.present? && !description.start_with?(SubpageHelper::EXTERNAL_URL_PREFIX)
  end
end
