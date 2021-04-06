class Archives::WorkshopsController < ArchivesController
  include GenericController

  private

  def includes_args
    [image_attachment: :blob]
  end

  def items_per_page
    15
  end
end
