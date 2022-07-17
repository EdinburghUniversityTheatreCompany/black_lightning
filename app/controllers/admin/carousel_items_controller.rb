

class Admin::CarouselItemsController < AdminController
  include GenericController
  load_and_authorize_resource

  # INDEX:  /carousel_items
  # SHOW:   /carousel_items/1
  # EDIT:   /carousel_items/1/edit
  # UPDATE: /carousel_items/1
  # NEW:    /carousel_items/new
  # CREATE: /carousel_items

  private

  def permitted_params
    # Make sure that references have _id appended to the end of them.
    # Check existing controllers for inspiration.
    [:title, :tagline, :carousel_name, :ordering, :is_active, :image, :url]
  end

  def order_args
    ['carousel_name', 'ordering']
  end
end
