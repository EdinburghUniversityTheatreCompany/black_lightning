class Admin::ModalComponent < ViewComponent::Base
  renders_one :footer

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
