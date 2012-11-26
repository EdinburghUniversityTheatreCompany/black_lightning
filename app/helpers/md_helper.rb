module MdHelper

    def render_markdown (md)
        if md == nil then
          return ""
        end

        require 'redcarpet'
        renderer = Redcarpet::Render::HTML.new
        redcarpet = Redcarpet::Markdown.new(renderer, {})
        return redcarpet.render(md).html_safe
    end

end
