class MarkdownController < ApplicationController
  include MdHelper

  def preview
    render :inline => render_markdown(request.body.read)
  end
end
