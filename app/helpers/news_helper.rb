module NewsHelper
  # find the first line break after 140 characters
  def generate_preview(content)
    /.{,140}.+?<\/p>/m.match(content)[0]
rescue
  'There was an error rendering a preview for this news item.'
  end
end
