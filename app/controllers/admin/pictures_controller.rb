##
# Admin controller for Pictures.
##
class Admin::PicturesController < AdminController
  include GenericController

  load_and_authorize_resource
end
