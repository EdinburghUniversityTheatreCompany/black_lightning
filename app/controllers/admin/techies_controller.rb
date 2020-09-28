##
# Responsible for the techie family tree.
##
class Admin::TechiesController < AdminController
  include GenericController

  load_and_authorize_resource except: :tree

  def tree
    authorize! :index, Techie
    @title = 'Techie Family Tree'
    @techies = Techie.all.includes(:children, :parents)
  end

  private

  def permitted_params
    [:name, children_attributes: [:id, :_destroy, :name], parents_attributes: [:id, :_destroy, :name]]
  end

  def order_args
    :name
  end
end
