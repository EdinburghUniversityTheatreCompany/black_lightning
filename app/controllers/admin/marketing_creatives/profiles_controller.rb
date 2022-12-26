class Admin::MarketingCreatives::ProfilesController < AdminController
  include GenericController

  load_and_authorize_resource class: MarketingCreatives::Profile, find_by: :url
  skip_load_resource only: %i[sign_up]

  ##
  # Overrides load_index_resources
  ##

  def sign_up
    return if check_if_the_current_user_has_a_profile

    @title = 'Sign-Up As Marketing Creative'
  
    # If you don't specify this, it will try to load a profile with ID nothing.
    @profile = MarketingCreatives::Profile.new

    respond_to do |format|
      format.html # sign_up.html.erb
      format.json { render json: @profile }
    end
  end

  def create
    if cannot?(:manage, MarketingCreatives::Profile)
      return if check_if_the_current_user_has_a_profile

      @profile.user = current_user
    end

    @profile.approved = false

    super
  end

  def approve
    @profile.update_attribute(:approved, true)

    helpers.append_to_flash(:success, "#{helpers.get_object_name(@profile, include_class_name: true, include_the: true)} has been approved and is now visible.")

    redirect_to admin_marketing_creatives_profile_path(@profile)
  end

  def reject
    @profile.update_attribute(:approved, false)

    helpers.append_to_flash(:success, "#{helpers.get_object_name(@profile, include_class_name: true, include_the: true)} has been rejected and is now no longer visible.")
    
    redirect_to admin_marketing_creatives_profile_path(@profile)
  end

  private

  def check_if_the_current_user_has_a_profile
    if current_user.marketing_creatives_profile.present?
      helpers.append_to_flash(:error, 'You have already signed up for a Marketing Creative profile, so you cannot sign up for another one.')
      redirect_to admin_marketing_creatives_profile_path(current_user.marketing_creatives_profile)

      return true
    end

    return false
  end

  # Generic Controller Overrides

  def resource_class
    MarketingCreatives::Profile
  end

  def permitted_params
    params = [ :name, :about, :contact,
      category_infos_attributes: [
        :id, :_destroy, :category_id, :image, :description,
        pictures_attributes: [:id, :_destroy, :description, :image]
      ]
    ]

    params += [:user_id] if can?(:manage, MarketingCreatives::Profile)

    return params
  end

  def includes_args
    [:user, :categories, :category_infos]
  end

  def order_args
    ['name']
  end
end
