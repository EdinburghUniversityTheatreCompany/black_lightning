##
# Controller to render a markdown preview.
#
# Use POST /markdown/preview with the post body set to the content
# to be rendered.
##

class MarkdownController < ApplicationController
  include MdHelper

  def preview
    render :inline => render_markdown(request.body.read)
  end
end
