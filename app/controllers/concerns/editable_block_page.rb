# For controllers whose whole page is one Admin::EditableBlock (/about, /get_involved, /archives):
# the block supplies the title and meta description.
module EditableBlockPage
  extend ActiveSupport::Concern

  private

  def set_meta_from_editable_block
    return if @editable_block.nil?

    @title = @editable_block.name.presence || @title

    description = helpers.render_plain(@editable_block.content).squish
    # A nav-redirect block has no prose, and "EXTERNAL_URL https://..." is a worse description than the site's.
    @meta[:description] = description if description.present? && !description.start_with?(SubpageHelper::EXTERNAL_URL_PREFIX)
  end
end
