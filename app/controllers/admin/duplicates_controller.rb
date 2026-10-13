# Lists potential duplicate users and records pairs marked as not duplicates.
class Admin::DuplicatesController < AdminController
  authorize_resource class: false

  def index
    @duplicates = User.find_potential_duplicates

    # The fuzzy-both buckets come from the cache the background job fills.
    @duplicates[:fuzzy_both_overlapping] = load_cached_duplicates(CachedDuplicate.overlapping)
    @duplicates[:fuzzy_both_no_overlap] = load_cached_duplicates(CachedDuplicate.no_overlap)

    @title = "Potential Duplicate Users"
  end

  def mark_not_duplicate
    @user1 = User.find(params[:user_id])
    @user2 = User.find(params[:other_user_id])

    @user1.mark_not_duplicate(@user2)
    low, high = [ @user1.id, @user2.id ].minmax
    CachedDuplicate.where(user1_id: low, user2_id: high).delete_all

    respond_to do |format|
      format.turbo_stream
      format.html do
        helpers.append_to_flash(:success, "#{@user1.name_or_email} and #{@user2.name_or_email} marked as not duplicates")
        redirect_to admin_duplicates_path
      end
    end
  end

  private

  def load_cached_duplicates(scope)
    pairs = scope.includes(:user1, :user2).to_a
    years = User.bulk_years_active_for(pairs.flat_map { |pair| [ pair.user1_id, pair.user2_id ] })
    pairs.map { |pair| { users: [ pair.user1, pair.user2 ], years_active_cache: years } }
  end
end
