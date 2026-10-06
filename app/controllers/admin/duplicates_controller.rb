# Lists potential duplicate users and records pairs marked as not duplicates.
class Admin::DuplicatesController < AdminController
  authorize_resource class: false

  def index
    @duplicates = User.find_potential_duplicates

    # The fuzzy-both buckets come from the cache the background job fills.
    @duplicates[:fuzzy_both_overlapping] = load_cached_duplicates("overlapping")
    @duplicates[:fuzzy_both_no_overlap] = load_cached_duplicates("no_overlap")

    @title = "Potential Duplicate Users"
  end

  def mark_not_duplicate
    @user1 = User.find(params[:user_id])
    @user2 = User.find(params[:other_user_id])

    @user1.mark_not_duplicate(@user2)

    respond_to do |format|
      format.turbo_stream
      format.html do
        helpers.append_to_flash(:success, "#{@user1.name_or_email} and #{@user2.name_or_email} marked as not duplicates")
        redirect_to admin_duplicates_path
      end
    end
  end

  private

  def load_cached_duplicates(bucket_type)
    CachedDuplicate.includes(:user1, :user2).where(bucket_type: bucket_type).map do |cached|
      {
        users: [ cached.user1, cached.user2 ],
        years_overlap: (bucket_type == "overlapping"),
        years_active_cache: {}
      }
    end
  end
end
