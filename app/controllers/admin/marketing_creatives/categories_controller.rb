class Admin::MarketingCreatives::CategoriesController < AdminController
  include GenericController
  load_and_authorize_resource class: MarketingCreatives::Category, find_by: :url

  def index
    @title = 'Marketing Creative Categories'

    super
  end

  def show
    # We shuffle the category_infos with a different seed every day.
    # This way, every Creative has a fair chance of ending up near the top.
    days_since_bedlam = Date.today - Date.new(1980, 1, 30)

    @category_infos = @category.category_infos
                               .accessible_by(current_ability)
                               .includes(image_attachment: :blob)
                               .order(:id)
                               .shuffle(random: Random.new(days_since_bedlam))

    super
  end

  private
  
  def resource_class
    MarketingCreatives::Category
  end

  def permitted_params
    [:name, :name_on_profile, :image]
  end

  def order_args
    :name
  end

  def includes_args
    [image_attachment: :blob]
  end
end
