##
# Controller to render a markdown preview.
#
# Use POST /markdown/preview with the post body set to the content
# to be rendered.
##

# TODO: Feels quite insecure
class MarkdownController < ApplicationController
  include MdHelper

  skip_authorization_check

  def preview
    body = ActiveSupport::JSON.decode(request.body.read)
    input_html = CGI.unescape(body['input_html'])

    response = { rendered_md: render_markdown(input_html) }

    render json: response
  end
end
