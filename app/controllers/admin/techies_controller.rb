##
# Responsible for the techie family tree.
##
# Source for some of the tree: https://gist.github.com/markjlorenz/3744338
class Admin::TechiesController < AdminController
  include GenericController

  load_and_authorize_resource except: [ :tree, :mass_new, :mass_create, :by_entry_year ]

  def show
    super

    @coparents = @techie.children.flat_map(&:parents).uniq - [ @techie ]
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
    @base_techie = @q.result(distinct: true)

    version = Techie.maximum(:updated_at).to_i
    @cache_version = "#{version}-#{@base_techie.size == 1 ? @base_techie.first.id : 'all'}"

    if @base_techie.size == 1
      techies = @base_techie.first.get_relatives(10, false)
      @graph_data = compute_graph_data(techies)
    else
      @graph_data = Rails.cache.fetch("techie_tree/#{version}") do
        techies = Techie.includes(:children, :parents).to_a
        compute_graph_data(techies)
      end
    end

    @selected_id = @base_techie.size == 1 ? @base_techie.first.id.to_s : ""
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

  def by_entry_year
    authorize! :index, Techie

    @title = "Techies by Entry Year and Parents"

    by_year = Techie.includes(:parents).group_by(&:entry_year)
    @grouped_no_year = group_techies_by_parents(by_year.delete(nil) || [])
    @grouped_data = by_year.sort.reverse.to_h.transform_values { group_techies_by_parents(_1) }
  end

  private

  def compute_graph_data(techies)
    nodes = techies.map { |t| { id: t.id.to_s, label: t.name, entry_year: t.entry_year } }
    edges = techies.flat_map do |t|
      t.children.select { |c| techies.include?(c) }.map { |c| { from: t.id.to_s, to: c.id.to_s } }
    end
    { nodes: nodes, edges: edges }
  end

  def permitted_params
    [ :name, :entry_year, children_attributes: [ :id, :_destroy, :name ], parents_attributes: [ :id, :_destroy, :name ] ]
  end

  def order_args
    [ "name asc", "entry_year asc" ]
  end

  def group_techies_by_parents(techies)
    techies.group_by { |t| t.parents.map(&:name_with_entry_year).sort.join(" & ").presence || "No Parents" }.sort.to_h
  end
end
