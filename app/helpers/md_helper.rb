require "#{Rails.root}/lib/kramdown/parser/b_kramdown"

module MdHelper

    def render_markdown (md)
        if md == nil then
          return ""
        end

        return Kramdown::Document.new(md, :input => 'BKramdown').to_html.html_safe
    end

end
