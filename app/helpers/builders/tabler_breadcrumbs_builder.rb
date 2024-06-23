# Formats breadcrumbs according to the tabler specification: https://tabler.io/docs/components/breadcrumb
class Builders::TablerBreadcrumbsBuilder < BreadcrumbsOnRails::Breadcrumbs::Builder
    def render
        content = @elements.collect { |element| render_element(element) }.join("\n")

        return "<ol class=\"breadcrumb\" aria-label=\"breadcrumbs\">\n#{content}\n</ol>".html_safe
    end

    def render_element(element)
        if element.path.nil?
            content = compute_name(element)
        else
            content = @context.link_to_unless_current(compute_name(element), compute_path(element), element.options)
        end

        return @context.content_tag(:li, content, class: "breadcrumb-item #{'active' if @context.current_page?(compute_path(element))}", 'aria-current': 'page')
    end
end
