module NewsHelper
  # find the first line break after 140 characters
  def generate_preview(content)
    begin
      preview = ''

      while content.present?
        partition = content.partition(/(\n)|(<\/p>)/)

        preview = preview.concat(partition.first)

        if preview.length < 140 && partition[2].present?
          preview = preview.concat(partition[1])
          content = partition[2]
        else
          break
        end
      end

      return preview
    rescue
      # :nocov:
      return 'There was an error rendering a preview for this news item.'
      # :nocov:
    end
  end
end
