##
# Responsible for the techie family tree.
##
class Admin::TechiesController < AdminController
  include GenericController

  load_and_authorize_resource except: :tree

  def show
    super

    @coparents = @techie.children.flat_map(&:parents).uniq - [@techie]
  end

  def tree
    authorize! :index, Techie
    @title = 'Techie Family Tree'

    @q = Techie.ransack(params[:q])

    include_siblings_of_related = false
    amount_of_generations = 10

    @base_techie = @q.result(distinct: true)

    if @base_techie.size == 1
      @techies = @base_techie.first.get_relatives(amount_of_generations, include_siblings_of_related)
    else
      @techies = @base_techie.includes(:children, :parents)
    end
  end

  private

  def permitted_params
    [:name, children_attributes: [:id, :_destroy, :name], parents_attributes: [:id, :_destroy, :name]]
  end

  def order_args
    :name
  end

  def base_index_query
    @q = @techies.ransack(params[:q])
    @q.sorts = ['name asc'] if @q.sorts.empty?

    return @q.result(distinct: true)
  end
end
