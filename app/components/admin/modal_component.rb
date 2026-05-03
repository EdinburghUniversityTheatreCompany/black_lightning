class Admin::ModalComponent < ViewComponent::Base
  renders_one :footer

  # id:          the HTML id for the <dialog> element (required for JS targeting)
  # title:       modal header title text
  # dialog_data: extra data-* attributes merged onto the <dialog> element,
  #              e.g. { template_loader_target: "dialog" }
  def initialize(id:, title:, dialog_data: {})
    @id = id
    @title = title
    @extra_dialog_data = dialog_data
  end

  private

  def dialog_data
    { controller: "modal", action: "click->modal#backdropClose" }.merge(@extra_dialog_data)
  end
end
