# PaperTrail history and diffs for an editable block.
class Admin::VersionHistoriesController < AdminController
  before_action :load_parent_record

  def index
    @title = "Version History - #{helpers.get_object_name(@parent_record, include_class_name: true)}"
    @versions = @parent_record.versions.order(created_at: :desc)
  end

  def show
    @version = @parent_record.versions.find(params[:id])
    @title = "Version #{@version.id} - #{@version.event.titleize}"
    @diff = @parent_record.diff_for_version(@version)
  end

  private

  def load_parent_record
    @parent_record = Admin::EditableBlock.find(params[:editable_block_id])
    authorize! :show, @parent_record
  end
end
