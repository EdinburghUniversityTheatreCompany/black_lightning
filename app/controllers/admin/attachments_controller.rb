##
# Admin controller for User management.
##
class Admin::AttachmentsController < AdminController
  include GenericController

  load_and_authorize_resource
end
