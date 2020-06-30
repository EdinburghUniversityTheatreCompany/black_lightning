# Based on this concept, but heavily modified: https://code.eventtus.com/generic-rails-controllers-7a170d507e66
# Should be included as a mix-in in any controllers you want to use it in. Use:
# includes GenericController
module GenericController
  # You will have to use load the resources yourself in the controller.
  # You can use load_and_authorize_resource.

  def index
    @title ||= helpers.get_formatted_class_name(resource_class, false)

    resources = load_index_resources

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: resources }
    end
  end

  def show
    @title ||= helpers.get_object_name(get_resource, include_class_name: include_class_name_in_show_page_title)

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: get_resource }
    end
  end

  def new
    # The title should be set by the view so it doesn't have to be set in both new and create.

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: get_resource }
    end
  end

  def create
    respond_to do |format|
      if get_resource.save
        on_create_success

        format.html { redirect_to(create_redirect_url) }
        format.json { render json: get_resource, status: :created }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: get_resource.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
    # The title should be set by the view so it doesn't have to be set in both edit and update.

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: get_resource }
    end
  end
  
  def update
    respond_to do |format|
      if get_resource.update(update_params)
        on_update_success

        format.html { redirect_to(update_redirect_url) }
        format.json { render json: [:admin, get_resource], status: :updated }
      else
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: get_resource.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    url = unsuccessful_destroy_redirect_url

    if helpers.destroy_with_flash_message(get_resource)
      url = successful_destroy_redirect_url
    end

    respond_to do |format|
      format.html { redirect_to(url) }
      format.json { format.json { render json: flash[:error] } }
    end
  end

  private

  def get_resource
    instance_variable_get("@#{resource_name}")
  end

  ##
  # Resource parameters
  # Do not use this method directly, as it does not permit resources. Use create_params and update_params instead.
  ##

  def resource_params
    @resource_params ||= params.require(resource_class.name.underscore.gsub('/', '_'))
  end

  def permitted_params
    # I don't know why it thinks this one is not covered.
    # :nocov:
    return []
    # :nocov:
  end

  def permitted_create_params
    permitted_params
  end

  def permitted_update_params
    permitted_params
  end

  def create_params
    resource_params.permit(permitted_create_params)
  end

  def update_params
    resource_params.permit(permitted_update_params)
  end

  ##
  # Resource Name
  ##

  def resource_name
    @resource_name ||= self.controller_name.demodulize.singularize
  end

  def resource_class
    @resource_class ||= controller_name.classify.constantize
  end

  ##
  # Redirection urls
  ##

  def create_redirect_url
    return url_for(controller: self.controller_path, action: :show, id: get_resource)
  end

  def update_redirect_url
    return url_for(controller: self.controller_path, action: :show, id: get_resource)
  end

  def successful_destroy_redirect_url
    url_for(controller: self.controller_path, action: :index)
  end

  def unsuccessful_destroy_redirect_url
    update_redirect_url
  end

  ##
  # On Success
  ## 

  def on_create_success
    helpers.append_to_flash(:success, "The #{helpers.get_object_name(get_resource, include_class_name: true)} was successfully created.")
  end

  def on_update_success
    helpers.append_to_flash(:success, "The #{helpers.get_object_name(get_resource, include_class_name: true)} was successfully updated.")
  end

  ##
  # Index Query
  ##

  def base_index_query
    return instance_variable_get("@#{resource_name.pluralize}")
  end

  def load_index_resources
    resources = base_index_query.includes(*includes_args)
                                .where(index_query_params)
                                .accessible_by(current_ability)
                                .order(order_args)
    # Order will not override any ordering from scopes!

    resources = resources.paginate(page: params[:page], per_page: items_per_page) if should_paginate

    instance_variable_set("@#{resource_name.pluralize}", resources)

    return resources
  end

  def includes_args
    [nil]
  end

  def index_query_params
    {}
  end
  
  def order_args
    :created_at
  end

  def should_paginate
    true
  end

  def items_per_page
    30
  end

  ##
  # Miscellaneous
  ##

  def include_class_name_in_show_page_title
    false
  end
end
