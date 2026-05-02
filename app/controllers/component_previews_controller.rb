class ComponentPreviewsController < ViewComponentsController
  layout "admin"

  helper_method :current_user

  private

  def current_user
    @current_user ||= User.where.not(first_name: [ nil, "" ]).first || User.first
  end
end
