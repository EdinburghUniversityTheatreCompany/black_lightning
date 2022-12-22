require "#{Rails.root}/lib/kramdown/parser/b_kramdown"

module MdHelper
  def render_markdown(md)
    return '' if md.nil?

    # BOOTSTRAP VERYNICETOHAVE: Get rid of the bottom margin in rendered markdown. If you can add a mb-0 class to the wrapping <p> tag you're fine
    return Kramdown::Document.new(md, input: 'BKramdown').to_html.html_safe
  end

  def render_plain(md)
    return '' if md.nil?

    return ActionController::Base.helpers.strip_tags(Kramdown::Document.new(md, input: 'BKramdown').to_html)
  end

  def truncate_markdown(content, length = 100)
    return ActionController::Base.helpers.truncate(render_plain(content).strip, length: length)
  end
end
