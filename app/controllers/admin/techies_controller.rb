##
# Responsible for the techie family tree.
##
# Source for some of the tree: https://gist.github.com/markjlorenz/3744338
class Admin::TechiesController < AdminController
  include GenericController

  load_and_authorize_resource except: [ :tree, :bush, :mass_new, :mass_create ]

  def show
    super

    @coparents = @techie.children.flat_map(&:parents).uniq - [ @techie ]
  end

  def bush
    authorize! :index, Techie

    @q = Techie.ransack(params[:q], auth_object: current_ability)

    @title = "Techie Family Tree - New but sucks"
  end

  def tree_data
    nodes = @techies.select(:id, :name)
    edges = @techies.includes(:children).flat_map { |techie| techie.children.ids.uniq.map { |child_id| [ techie.id, child_id ] } }

    json = { edges: edges, nodes: nodes }.to_json

    render json: json
  end

  # Remember to remove Dracula and stuff when you finally get rid of this one.
  def tree
    authorize! :index, Techie

    @title = "Techie Family Tree"

    @q = Techie.ransack(params[:q], auth_object: current_ability)

    include_siblings_of_related = false
    amount_of_generations = 10

    @base_techie = @q.result(distinct: true)

    if @base_techie.size == 1
      @techies = @base_techie.first.get_relatives(amount_of_generations, include_siblings_of_related)
    else
      @techies = @base_techie.includes(:children, :parents)
    end
  end

  def mass_new
    authorize! :new, Techie
  end

  def mass_create
    authorize! :create, Techie

    relationships_data = params[:techie][:relationships_data]

    if Techie.mass_create(relationships_data)
      helpers.append_to_flash(:success, "The mass create of techies was successfull.")

      redirect_to(admin_techies_url)
    else
      render "mass_new", status: :unprocessable_entity
    end
  end

  private

  def permitted_params
    [ :name, children_attributes: [ :id, :_destroy, :name ], parents_attributes: [ :id, :_destroy, :name ] ]
  end

  def order_args
    [ "name asc" ]
  end
end
