# Based on this concept, but heavily modified: https://code.eventtus.com/generic-rails-controllers-7a170d507e66
# Should be included as a mix-in in any controllers you want to use it in. Use:
# includes GenericController
module GenericController
  # You will have to use load the resources yourself in the controller.
  # You can use load_and_authorize_resource.

  def index
    return if return_random

    @title ||= helpers.get_formatted_class_name(resource_class, false)

    resources = load_index_resources

    instance_variable_set("@#{resource_name.pluralize}", resources)

    response.headers['X-Total-Count'] = resources.count.to_s

    @editable_block_name = index_editable_block_name

    respond_to do |format|
      format.html { render index_filename }
      format.json { render json: resources } if json_enabled_for_index?
    end
  end

  def show
    @title ||= helpers.get_object_name(get_resource, include_class_name: include_class_name_in_show_page_title)

    respond_to do |format|
      format.html # show.html.erb
      # format.json { render json: get_resource }
    end
  end

  def new
    @title = new_title

    respond_to do |format|
      format.html # new.html.erb
      # format.json { render json: get_resource }
    end
  end

  def create
    # This will use create_params as cancancan will look for create_params first.

    check_for_dropzone

    respond_to do |format|
      if get_resource.save
        on_create_success

        format.html { redirect_to(create_redirect_url) }
        # format.json { render json: get_resource, status: :created }
      else
        format.html { render 'new', status: :unprocessable_entity }
        # format.json { render json: get_resource.errors, status: :unprocessable_entity }
      end
    end
  end

  def edit
    @title = edit_title

    respond_to do |format|
      format.html # new.html.erb
      # format.json { render json: get_resource }
    end
  end

  def update
    check_for_dropzone

    respond_to do |format|
      if get_resource.update(update_params)
        on_update_success

        format.html { redirect_to(update_redirect_url) }
        # format.json { render json: [:admin, get_resource], status: :updated }
      else
        @title = edit_title

        format.html { render 'edit', status: :unprocessable_entity }
        # format.json { render json: get_resource.errors, status: :unprocessable_entity }
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
      # format.json { format.json { render json: flash[:error] } }
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

  # permitted_params should be explicitly defined in each controller that includes this Generic Controller!

  def permitted_params
    raise(NoMethodError.new("The controller #{self.controller_path} should define permitted_params, or permitted_create_params and permitted_update_params directly."))
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
  # Page Titles
  ##

  def new_title
    return "New #{helpers.get_object_name(get_resource.class, include_class_name: true)}"
  end

  def edit_title
    return "Edit #{helpers.get_object_name(get_resource, include_class_name: true)}"
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

  def base_index_ransack_query
    @q = resource_class.ransack(ransack_query_param, auth_object: current_ability)

    @q.sorts = order_args unless @q.sorts.present?

    @q = process_q_before_getting_result(@q)

    return @q.result(distinct: distinct_for_ransack)
  end

  # This is what is passed to random as well, so do any extra filtering here.
  def base_index_database_query
    # Use reorder to override the default ordering in the scope.
    # We want this because we expect the default ordering to be ignored when we specify something new.
    # Use where instead of rewhere because a where in the default scope is only used for things that should never be visible.

    return base_index_ransack_query.includes(*includes_args)
                                   .where(index_query_params)
                                   .accessible_by(current_ability)
  end

  # This is what is only used by the index action.
  def load_index_resources
    resources = base_index_database_query

    resources = resources.page(params[:page]).per(items_per_page) if should_paginate

    return resources
  end

  def includes_args
    [nil]
  end

  def index_query_params
    {}
  end

  def order_args
    ['created_at']
  end

  def should_paginate
    true
  end

  def items_per_page
    30
  end

  def json_enabled_for_index?
    false
  end

  ##
  # Ransack
  ##

  def distinct_for_ransack
    true
  end

  def ransack_query_param
    params[:q]
  end

  def process_q_before_getting_result(q)
    q
  end
  ##
  # Miscellaneous
  ##

  def include_class_name_in_show_page_title
    false
  end

  def index_filename
    'index'
  end

  def index_editable_block_name
    "Index - #{@current_path.titleize} Description"
  end

  ##
  # Random
  ##

  def random_resources
    base_index_database_query.reorder('')
  end

  def should_return_random
    helpers.strip_tags(params[:commit].presence || '').strip.upcase == 'RANDOM'
  end

  def return_random
    return false unless should_return_random

    unless random_resources.present?
      helpers.append_to_flash(:error, 'There are no results from the search, so I could not select a random instance. HAL is sorry.')
      return false
    end

    instance = resource_class.find_by(id: random_resources.pluck(:id).sample)
 
    # Primarily so the test works.
    instance_variable_set("@#{resource_name}", instance)

    redirect_to(url_for(instance_url_hash(instance)))

    return true
  end

  # Hash with the instance and :admin if the url should go to the admin site.
  # Used by the return_random method above.
  def instance_url_hash(instance)
    instance_url_hash = if @admin_site
      [:admin, instance]
    else
      instance
    end
  end

  ##
  # Dropzone
  ##

  DROPZONE_IDENTIFIER = 'dropzone_'.freeze

  # NOTE: This is not completely secure, as you could technically now attach files and pictures
  # to anything that has an attachment point even when you shouldn't be able to.
  # In practice, this is never an issue.
  def check_for_dropzone
    return if params.nil?

    # Look for the params on the resource and see if there is a dropzone list.
    params.each do |key, data|
      next unless key.include?(DROPZONE_IDENTIFIER)

      # Assume dropzones are only used for has_many's.
      # If you want to support has_one's as well, have fun coding that :)

      destination = key.split(DROPZONE_IDENTIFIER)[1]

      upload_dropzone(destination, data)
    end
  end

  def upload_dropzone(destination, upload_data)
    # If you're ever extending this, you can figure out how to genericise it.
    # I am aware that I am probably writing this to myself.

    files = upload_data[:files]

    # Have to use this weird try 
    files.select! {|file| file.present? }
    if destination == 'pictures'
      # This check should happen after the destination check, otherwise
      # it won't throw an error if the files are nil.
      return if files.empty?

      attributes = upload_data.permit(:access_level, picture_tag_ids: [])

      attributes[:gallery] = get_resource

      files.each do |file_data|
        attributes[:image] = file_data

        Picture.create(attributes)
      end
    else
      raise ArgumentError.new, 'The destination specified for the dropzone is not valid.'
    end
  end
end
