##
# Controller to render a markdown preview.
#
# Use POST /markdown/preview with the post body set to the content
# to be rendered.
##

class MarkdownController < ApplicationController
  include MdHelper

  def preview
    body = ActiveSupport::JSON.decode(request.body.read)
    input_html = URI.unescape(body["input_html"])

    response = { rendered_md: render_markdown(input_html) }

    render :json => response
  end
end
