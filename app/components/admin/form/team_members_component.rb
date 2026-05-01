class Admin::Form::TeamMembersComponent < ViewComponent::Base
  def initialize(f:)
    @f = f
  end

  private

  def show_bulk_import_link?
    @f.object.is_a?(Event) && @f.object.persisted? && helpers.can?(:update, @f.object)
  end

  def bulk_import_path
    helpers.new_admin_show_show_crew_import_path(@f.object)
  end
end
