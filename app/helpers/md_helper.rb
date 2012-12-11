module MdHelper

    def render_markdown (md)
        if md == nil then
          return ""
        end

        return Kramdown::Document.new(md).to_html.html_safe
    end

end
