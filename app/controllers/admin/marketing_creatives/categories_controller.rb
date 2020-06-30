class Admin::MarketingCreatives::CategoriesController < AdminController
  include GenericController
  load_and_authorize_resource class: MarketingCreatives::Category, find_by: :url

  def index
    @title = 'Marketing Creative Categories'

    super
  end

  def show
    # Todo
  end

  private
  
  def resource_class
    MarketingCreatives::Category
  end

  def permitted_params
    [:name, :name_on_profile, :image]
  end
end
