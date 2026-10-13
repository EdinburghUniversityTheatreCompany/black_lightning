class Admin::ModalComponentPreview < Admin::ApplicationComponentPreview
  # The dialog stays closed until showModal() is called on it.
  def default
    render Admin::ModalComponent.new(id: "preview_modal", title: "Example Modal") do |modal|
      modal.with_footer do
        tag.div(class: "flex gap-2 ml-auto") do
          tag.button("Cancel", type: "button", class: ButtonComponent.classes_for(variant: :secondary)) +
          tag.button("Confirm", type: "button", class: ButtonComponent.classes_for(variant: :primary))
        end
      end

      tag.p("Modal body content goes here.", class: "text-sm text-gray-700")
    end
  end
end
