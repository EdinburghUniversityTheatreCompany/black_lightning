##
# Controller for viewing and managing potential duplicate users.
##
class Admin::DuplicatesController < AdminController
  authorize_resource class: false

  def index
    @duplicates = User.find_potential_duplicates
    @title = "Potential Duplicate Users"
  end

  def mark_not_duplicate
    user1 = User.find(params[:user_id])
    user2 = User.find(params[:other_user_id])

    user1.mark_not_duplicate(user2)

    helpers.append_to_flash(:success, "#{user1.name_or_email} and #{user2.name_or_email} marked as not duplicates")
    redirect_to admin_duplicates_path
  end
end
