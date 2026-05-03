class Admin::ModalComponentPreview < Admin::ApplicationComponentPreview
  # The native <dialog> element is hidden by default until showModal() is called.
  # For previews, we force it open with the HTML `open` attribute so the content
  # is visible without JavaScript.
  def default
    render Admin::ModalComponent.new(id: "preview_modal", title: "Example Modal") do |modal|
      modal.with_footer do
        tag.div(class: "flex gap-2 ml-auto") do
          tag.button("Cancel", type: "button", class: "btn btn-secondary") +
          tag.button("Confirm", type: "button", class: "btn btn-primary")
        end
      end

      tag.p("Modal body content goes here.", class: "text-sm text-gray-700")
    end
  end

  def with_form_content
    render Admin::ModalComponent.new(id: "preview_modal_form", title: "Select Questions from Template") do |modal|
      modal.with_footer do
        tag.button("Edit Templates", type: "button", class: "btn btn-secondary") +
        tag.div(class: "flex gap-2") do
          tag.button("Close", type: "button", class: "btn btn-secondary") +
          tag.button("Load Template", type: "button", class: "btn btn-primary opacity-50 cursor-not-allowed", disabled: true)
        end
      end

      tag.div do
        tag.div(class: "text-sm text-gray-500 mb-2") { "Select an option..." } +
        tag.div(class: "border border-gray-200 rounded p-3 mt-3") do
          tag.p("Preview", class: "text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1") +
          tag.ul(class: "space-y-1") do
            [
              [ "What show are you applying for?", "short_answer" ],
              [ "Why do you want to join?", "long_answer" ],
              [ "Are you available on weekends?", "yes_no" ]
            ].map do |question, type|
              tag.li(class: "flex items-start gap-2 text-sm py-1 border-b border-gray-100") do
                tag.span(question, class: "flex-1 text-gray-800") +
                tag.span(type.gsub("_", " "), class: "text-xs px-1.5 py-0.5 rounded bg-gray-100 text-gray-500 shrink-0 font-mono")
              end
            end.join.html_safe
          end
        end
      end
    end
  end
end
