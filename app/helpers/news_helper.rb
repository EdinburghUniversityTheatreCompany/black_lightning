module NewsHelper
  # find the first line break after 140 characters
  def generate_preview(content)
    begin
      return /.{,140}.+?<\/p>/m.match(content)[0]
    rescue
      # :nocov:
      return 'There was an error rendering a preview for this news item.'
      # :nocov:
    end
  end
end
