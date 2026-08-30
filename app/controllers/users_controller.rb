##
# Public controller for User. More details can be found there.
##
class UsersController < ApplicationController
  include GenericController

  load_resource
  ##
  # GET /users/1
  #
  # GET /users/1.json
  ##
  def show
    authorize! :view_shows_and_bio, @user

    @title = @user.name(current_user)

    @team_memberships = @user.team_memberships(true)

    # Public profiles are indexed on purpose -- members opt out with public_profile, and a
    # profile the guest ability cannot see never reaches this line. What they must not all share
    # is the site-wide boilerplate description.
    @meta[:description] = profile_description

    super
  end

  def consent
    authorize! :edit, @user

    @user.update_column(:consented, Date.current)

    redirect_to(admin_path)
  end

  private

  def profile_description
    bio = helpers.render_plain(@user.bio).squish

    return bio if bio.present?

    "#{@title} at Bedlam Theatre \u2014 shows and roles with the Edinburgh University Theatre Company."
  end
end
