##
# Controller for viewing PaperTrail version history and diffs.
#
# Designed to be reusable across any PaperTrail-enabled model by
# nesting under the parent resource's routes.
#
# Example routes:
#   resources :editable_blocks do
#     resources :version_histories, only: [:index, :show]
#   end
##
class Admin::VersionHistoriesController < AdminController
  before_action :load_parent_record
  before_action :load_version, only: :show

  def index
    @title = "Version History - #{helpers.get_object_name(@parent_record, include_class_name: true)}"
    @versions = @parent_record.versions.order(created_at: :desc)
  end

  def show
    @title = "Version #{@version.id} - #{@version.event.titleize}"
    @diff = @parent_record.diff_for_version(@version)
  end

  private

  def load_parent_record
    parent_param = request.path_parameters.keys.find { |k| k.to_s.end_with?("_id") && k != :id }
    parent_class_name = parent_param.to_s.chomp("_id").classify

    # Try Admin-namespaced model first (since this controller is in the admin namespace),
    # then fall back to non-namespaced model.
    parent_class = begin
      "Admin::#{parent_class_name}".constantize
    rescue NameError
      parent_class_name.constantize
    end

    @parent_record = parent_class.find(params[parent_param])
    authorize! :show, @parent_record
  end

  def load_version
    @version = @parent_record.versions.find(params[:id])
  end
end
