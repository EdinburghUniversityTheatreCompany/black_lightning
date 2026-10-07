require "test_helper"

class Admin::ShowsControllerTest < ActionController::TestCase
  include AcademicYearHelper

  setup do
    @admin = users(:admin)
    sign_in @admin
  end

  test "should get index" do
    FactoryBot.create_list(:show, 3)

    get :index
    assert_response :success
    assert_not_nil assigns(:events)
  end

  test "index offers the members-only text search to every backend user, not only members" do
    backend_only = FactoryBot.create(:user)
    Role.create!(name: "Backend Only").tap do |role|
      role.permissions << admin_permissions(:access_backend)
      backend_only.add_role(role)
    end
    assert_not backend_only.member?
    sign_in backend_only

    get :index
    assert_response :success
    assert_select "input[name='q[members_only_text_cont]']", 1
  end

  test "should get random show" do
    FactoryBot.create_list(:show, 3)

    get :index, params: { commit: "Random" }

    # Due to the randomness, can't get it to be more specific than
    # checking for a redirect.
    assert_response :redirect
    assert_not_nil assigns(:events)
  end

  test "should get show" do
    @show = FactoryBot.create(:show)

    get :show, params: { id: @show }
    assert_response :success

    assert_no_match "DM Trained", response.body
  end

  # This mainly tests the show team members partial.
  test "should get show with a team member that is DM trained" do
    @show = FactoryBot.create(:show, team_member_count: 1)

    @show.users.first.add_role "DM Trained"

    get :show, params: { id: @show }

    assert_response :success
    assert_match "DM Trained", response.body
  end

  test "should get show with staffing debts and maintenance debts" do
    @show = FactoryBot.create(:show)

    FactoryBot.create(:maintenance_debt, show: @show)
    FactoryBot.create(:staffing_debt, show: @show)

    get :show, params: { id: @show }
    assert_response :success
  end

  test "should get show with debt settings section for current academic year show" do
    @show = FactoryBot.create(:show, is_public: true, end_date: start_of_year.advance(days: 1), start_date: start_of_year)

    get :show, params: { id: @show }
    assert_response :success
    assert_match "Debt Settings", response.body
  end

  test "should not show debt settings for old show" do
    @show = FactoryBot.create(:show, is_public: true, end_date: start_of_year.advance(years: -2), start_date: start_of_year.advance(years: -2))

    get :show, params: { id: @show }
    assert_response :success
    assert_no_match "Debt Settings", response.body
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create show" do
    attributes = FactoryBot.attributes_for(:show)

    assert_difference("Show.count") do
      post :create, params: { show: attributes }
    end

    assert_redirected_to admin_show_path(assigns(:show))
  end

  test "should not create invalid show" do
    attributes = FactoryBot.attributes_for(:show, author: nil)

    assert_no_difference("Show.count") do
      post :create, params: { show: attributes }
    end

    assert_response :unprocessable_entity
  end

  test "should get edit" do
    @show = FactoryBot.create(:show)

    get :edit, params: { id: @show }
    assert_response :success
  end

  test "should get edit with existing pictures" do
    @show = FactoryBot.create(:show, picture_count: 2)

    get :edit, params: { id: @show }
    assert_response :success
  end

  test "should render add picture nested-form template without image on edit" do
    @show = FactoryBot.create(:show)

    get :edit, params: { id: @show }
    assert_response :success

    # The new-record <template> holds an empty picture, so no image_tag.
    assert_match "data-nested-form-target=\"template\"", response.body
    assert_no_match "missing.png", response.body
  end

  test "should re-render edit when update fails with new picture attributes" do
    @show = FactoryBot.create(:show)

    picture_image = fixture_file_upload(Rails.root.join("test", "test.png"), "image/png")
    invalid_attributes = FactoryBot.attributes_for(:show, venue_id: nil)
    invalid_attributes[:pictures_attributes] = {
      "0" => {
        description: "test picture",
        image: picture_image,
        access_level: 2,
        _destroy: "false"
      }
    }

    put :update, params: { id: @show, show: invalid_attributes }
    assert_response :unprocessable_entity
  end

  test "should update show" do
    @show = FactoryBot.create(:show)
    attributes = FactoryBot.attributes_for(:show)

    put :update, params: { id: @show, show: attributes }

    assert_equal attributes[:name], assigns(:show)[:name]
    assert_equal [ "The Show \"#{attributes[:name]}\" was successfully updated." ], flash[:success]
    assert_redirected_to admin_show_path(assigns(:show))
  end

  test "should update the digital programme link, and offer it on the edit form" do
    @show = FactoryBot.create(:show)
    attributes = FactoryBot.attributes_for(:show, digital_programme_url: "https://example.com/programme.pdf")

    put :update, params: { id: @show, show: attributes }

    assert_empty assigns(:show).errors.full_messages, "There are errors on the show"
    assert_equal "https://example.com/programme.pdf", @show.reload.digital_programme_url

    get :edit, params: { id: @show }

    assert_response :success
    assert_match "show_digital_programme_url", response.body
    assert_match "https://example.com/programme.pdf", response.body
  end

  test "should update show without new debtors" do
    @show = FactoryBot.create(:show, team_member_count: 1)

    users = FactoryBot.create_list(:user, 3)
    attributes = FactoryBot.attributes_for(:show, team_members_attributes: team_members_attributes(users))

    # To check if an existing user who is in debt does not count.
    FactoryBot.create(:overdue_staffing_debt, user: @show.users.first)

    assert_no_difference "ActionMailer::Base.deliveries.count" do
      put :update, params: { id: @show, show: attributes }
    end

    assert_empty assigns(:show).errors.full_messages, "There are errors on the show"
    assert_equal [ "The Show \"#{attributes[:name]}\" was successfully updated." ], flash[:success]

    assert_redirected_to admin_show_path(assigns(:show))
  end

  test "should update show with new debtors" do
    @show = FactoryBot.create(:show)
    users = FactoryBot.create_list(:user, 5)
    attributes = FactoryBot.attributes_for(:show, team_members_attributes: team_members_attributes(users), start_date: start_of_year.advance(days: 1))

    FactoryBot.create(:overdue_staffing_debt, user: users.first)

    put :update, params: { id: @show, show: attributes }

    assert_enqueued_emails 1

    assert_equal "The show was successfully updated, but #{users.first.name} is in debt.", flash[:success].first
    assert_redirected_to admin_show_path(assigns(:show))
  end

  test "should not update invalid show" do
    @show = FactoryBot.create(:show)
    attributes = FactoryBot.attributes_for(:show, price: nil)

    put :update, params: { id: @show, show: attributes }

    assert_response :unprocessable_entity
  end

  test "a failed update keeps a custom author selected in the re-rendered form" do
    show = FactoryBot.create(:show, author: "Original Author")
    # Only an update clears the cached list; an empty one from an earlier test skips the custom-value branch.
    Rails.cache.delete(Event::AUTHOR_NAME_LIST_CACHE_KEY)

    put :update, params: { id: show, show: FactoryBot.attributes_for(:show, author: "  Brand New Custom Author  ", venue_id: nil) }

    assert_response :unprocessable_entity
    assert_select "select[name='show[author]'] option[selected][value='Brand New Custom Author']"
  end

  test "should destroy show" do
    @show = FactoryBot.create(:show, team_member_count: 0, picture_count: 0, review_count: 0, feedback_count: 0)

    assert_difference("Show.count", -1) do
      delete :destroy, params: { id: @show }

      assert_nil flash[:errors]
    end

    assert_redirected_to admin_shows_path
  end

  test "should update debt settings and create debts" do
    # All Directors, so none is capped.
    @show = FactoryBot.create(:show, start_date: start_of_year, end_date: start_of_year.advance(days: 7), team_member_count: 0)
    3.times do
      user = FactoryBot.create(:user)
      FactoryBot.create(:team_member, teamwork: @show, user: user, position: "Director")
    end

    debt_params = {
      maintenance_debt_amount: 1,
      maintenance_debt_start: Date.current.advance(days: 14),
      staffing_debt_amount: 2,
      staffing_debt_start: Date.current.advance(days: 14)
    }

    assert_difference "Admin::MaintenanceDebt.count", @show.team_members.count do
      assert_difference "Admin::StaffingDebt.count", @show.team_members.count * 2 do
        patch :update_debt_settings, params: { id: @show.slug, show: debt_params }
      end
    end

    assert_redirected_to admin_show_path(@show)
    assert_includes flash[:success].first, "Debt settings saved"
  end

  test "should update debt settings without creating duplicate debts" do
    @show = FactoryBot.create(:show, start_date: start_of_year, end_date: start_of_year.advance(days: 7))

    debt_params = {
      maintenance_debt_amount: 1,
      maintenance_debt_start: Date.current.advance(days: 14),
      staffing_debt_amount: 1,
      staffing_debt_start: Date.current.advance(days: 14)
    }

    patch :update_debt_settings, params: { id: @show.slug, show: debt_params }
    assert_redirected_to admin_show_path(@show)

    assert_no_difference "Admin::MaintenanceDebt.count" do
      assert_no_difference "Admin::StaffingDebt.count" do
        patch :update_debt_settings, params: { id: @show.slug, show: debt_params }
      end
    end

    assert_redirected_to admin_show_path(@show)
    assert_equal "Debt settings saved.", flash[:success].last
  end

  test "should not update debt settings for show outside academic year" do
    @show = FactoryBot.create(:show,
      start_date: start_of_year.advance(years: -2),
      end_date: start_of_year.advance(years: -2)
    )

    debt_params = {
      maintenance_debt_amount: 1,
      maintenance_debt_start: Date.current.advance(days: 14)
    }

    assert_no_difference "Admin::MaintenanceDebt.count" do
      patch :update_debt_settings, params: { id: @show.slug, show: debt_params }
    end

    assert_redirected_to admin_show_path(@show)
    assert_equal [ "Debt settings can only be configured for events in the current academic year or later." ], flash[:error]
  end

  test "convert to season" do
    show = FactoryBot.create(:show, review_count: 0, feedback_count: 0)

    assert_difference("Show.count", -1) do
      assert_difference("Season.count", 1) do
        post :convert_to_season, params: { id: show }
      end
    end

    season = Season.find(show.id)

    assert_equal season.name, show.name
    assert_equal season.picture_ids, show.picture_ids
    assert_equal season.team_member_ids, show.team_member_ids
  end

  test "convert to workshop" do
    show = FactoryBot.create(:show, review_count: 0, feedback_count: 0)

    assert_difference("Show.count", -1) do
      assert_difference("Workshop.count", 1) do
        post :convert_to_workshop, params: { id: show }
      end
    end

    assert_equal [ "Converted the Show \"#{show.name}\" into the Workshop \"#{show.name}\"." ], flash[:success]

    workshop = Workshop.find(show.id)

    assert_equal workshop.name, show.name
    assert_equal workshop.picture_ids, show.picture_ids
    assert_equal workshop.team_member_ids, show.team_member_ids
  end

  # Assuming it also will not convert to a Workshop in this case.
  test "cannot convert to season when there is stuff attached" do
    show = FactoryBot.create(:show, feedback_count: 1)

    assert_no_difference("Show.count") do
      assert_no_difference("Season.count") do
        post :convert_to_season, params: { id: show }
      end
    end

    assert_equal [ "There are still attached feedbacks left. You cannot convert a show with one of these attached to prevent data loss." ], flash[:error]
  end

  test "cannot convert without permission" do
    sign_out @admin
    sign_in FactoryBot.create(:committee)

    show = FactoryBot.create(:show, review_count: 0, feedback_count: 0)

    post :convert_to_workshop, params: { id: show }

    assert_response 403
  end

  test "upload pictures using dropzone" do
    attributes = FactoryBot.attributes_for(:show)

    file_data = [ fixture_file_upload(Rails.root.join("test", "test.png"), "image/png") ]
    dropzone_data = {
      files: file_data,
      access_level: 0
    }

    assert_difference("Show.count") do
      assert_difference("Picture.count", file_data.size) do
        post :create, params: { show: attributes, dropzone_pictures: dropzone_data }
      end
    end

    assert assigns(:show).pictures.count, file_data.size

    assert(assigns(:show).pictures.all { |picture| picture.access_level == 0 })
    assert_redirected_to admin_show_path(assigns(:show))
  end

  test "raises error when dropzoning something random" do
    assert_raises ArgumentError do
      @show = FactoryBot.create(:show)
      attributes = FactoryBot.attributes_for(:show)

      dropzone_data = {
        files: [ "the", "content", "should", "not", "matter" ]
      }

      put :update, params: { id: @show, show: attributes, dropzone_finbar: dropzone_data }
    end
  end

  test "updating a show stores its performances" do
    show = FactoryBot.create(:show, is_public: true)
    starts_at = show.start_date.in_time_zone.change(hour: 19, min: 30)

    patch :update, params: { id: show.to_param, show: { event_occurrences_attributes: {
      "0" => { starts_at: starts_at, note: "Press night", access_flags: [ "", "relaxed" ] }
    } } }

    occurrence = show.reload.event_occurrences.sole

    assert_equal starts_at.to_i, occurrence.starts_at.to_i
    assert_equal "Press night", occurrence.note
    assert_equal %w[relaxed], occurrence.access_flags
  end

  # SortableJS only reorders direct children, so deeper rows silently stop dragging.
  test "edit form nests the sortable team member rows directly inside the sortable controller" do
    show = FactoryBot.create(:show, team_member_count: 2)

    get :edit, params: { id: show.to_param }
    assert_response :success

    assert_select "[data-controller~=sortable]", 1
    assert_select "[data-controller~=sortable] > [data-sortable-item]", 2,
                  "team member rows must be direct children of the sortable controller"
  end

  # The submitted row order is saved (TeamMemberOrdering), so a form in id order would rewrite the credits.
  test "edit form lists team members in their saved display order, not id order" do
    show = FactoryBot.create(:show, team_member_count: 3)
    ids = show.team_members.order(:id).ids
    ids.each_with_index { |id, index| TeamMember.find(id).update_columns(display_order: ids.size - 1 - index) }

    get :edit, params: { id: show.to_param }
    assert_response :success

    rendered_ids = css_select("[data-controller~=sortable] > [data-sortable-item] input[name$='[id]']").map { |input| input["value"].to_i }
    assert_equal ids.reverse, rendered_ids
  end

  # After a failed save the form shows the rows as submitted; a scope would render the stale ones.
  test "a failed update re-renders the team members in the submitted order" do
    show = FactoryBot.create(:show, team_member_count: 2)
    first, second = show.team_members.order(:id).to_a
    # Rows appended to a persisted teamwork are numbered already; the reversed post must not rewrite them.
    before = show.team_members.order(:id).pluck(:id, :display_order)

    patch :update, params: { id: show.to_param, show: { price: nil, team_members_attributes: {
      "0" => team_member_row(second),
      "1" => team_member_row(first)
    } } }
    assert_response :unprocessable_entity

    rendered = css_select("[data-controller~=sortable] > [data-sortable-item] input[name$='[id]']").map { |input| input["value"].to_i }
    assert_equal [ second.id, first.id ], rendered
    assert_equal before, show.team_members.reload.order(:id).pluck(:id, :display_order),
                 "the failed save must not have written the order"
  end

  # Keys chosen to sort as written: a functional test cannot pin row order (CLAUDE.md, Testing).
  test "the saved order follows the submitted rows, skipping destroyed and blank ones and ignoring a posted display_order" do
    show = FactoryBot.create(:show, team_member_count: 3)
    a, b, c = show.team_members.order(:id).to_a

    patch :update, params: { id: show.to_param, show: { team_members_attributes: {
      "0" => team_member_row(c, display_order: 5),
      "1" => { id: "", position: "", user_id: "", _destroy: "false" },
      "2" => team_member_row(b, _destroy: "1"),
      "3" => team_member_row(a, display_order: 0)
    } } }
    assert_redirected_to admin_show_path(show)

    assert_equal [ [ c.id, 0 ], [ a.id, 1 ] ], show.team_members.ordered.pluck(:id, :display_order)
  end

  test "updating a show stores its ticket price bands and rewrites the price line" do
    show = FactoryBot.create(:show, is_public: true, price: "£10/8/7")

    patch :update, params: { id: show.to_param, show: { ticket_prices_attributes: {
      "0" => { category: "standard", amount: "9" },
      "1" => { category: "concession", amount: "7" },
      "2" => { category: "standard", amount: "" }
    } } }

    show.reload

    assert_equal [ [ 9.0, "standard" ], [ 7.0, "concession" ] ],
                 show.ticket_prices.map { |price| [ price.amount.to_f, price.category ] }
    assert_equal "£9 / £7 concessions", show.price
  end

  # Removing the last band posts no ticket_prices_attributes key, so the form's sentinel row is
  # what empties the collection.
  test "removing every price band through the form clears them" do
    show = FactoryBot.create(:show, is_public: true)
    show.update!(ticket_prices: [ { "category" => "standard", "amount" => "10" } ])

    patch :update, params: { id: show.to_param, show: {
      price: "Pay what you can",
      ticket_prices_attributes: { "sentinel" => { "amount" => "" } }
    } }

    assert_empty show.reload.ticket_prices
    assert_equal "Pay what you can", show.price
  end

  # ticket_prices is a JSON column, so _nested_fields needs template_object for its blank row.
  test "edit form renders the ticket price rows and their add-row template" do
    show = FactoryBot.create(:show, is_public: true)
    show.update!(ticket_prices: [ { "category" => "standard", "amount" => "10" } ])

    get :edit, params: { id: show.to_param }
    assert_response :success

    assert_match "Ticket prices", response.body
    assert_no_match "Translation missing", response.body
    assert_select "input[name='show[ticket_prices_attributes][0][amount]']"
    assert_select "select[name='show[ticket_prices_attributes][0][category]']"
    assert_match "show[ticket_prices_attributes][NEW_RECORD][amount]", response.body
    assert_select "input[type=hidden][name='show[ticket_prices_attributes][sentinel][amount]']"
  end

  test "edit form renders the performance rows under the show's own word for them" do
    show = FactoryBot.create(:show, is_public: true)
    FactoryBot.create(:event_occurrence, event: show)

    get :edit, params: { id: show.to_param }
    assert_response :success

    assert_match "Performances", response.body
    assert_no_match "Translation missing", response.body
    assert_select "[data-controller~=nested-form] input[name*='event_occurrences_attributes'][name*='[starts_at]']"

    EventOccurrence::ACCESS_FLAG_LABELS.each_value do |label|
      assert_match label, response.body
    end
  end

  private

  # A persisted row as the form posts it.
  def team_member_row(member, **extra)
    { id: member.id, user_id: member.user_id, position: member.position, _destroy: "false", **extra }
  end

  def team_members_attributes(users)
    team_members_attributes = {}

    users.each_with_index do |user, count|
      team_members_attributes[count] = { position: "Viking#{count}", user_name_field: user.name, user_id: user.id, "_destroy"=>"false" }
    end

    team_members_attributes
  end

  class FakeSync
    attr_reader :events

    def initialize(error: nil)
      @error = error
      @events = []
    end

    def call(event)
      @events << event
      raise @error if @error

      Pretix::PerformanceSync::Result.new(created: 2, updated: 1, adopted: 0, destroyed: 0,
                                          kept: 0, skipped: 0, emptied_series: false,
                                          missing_series: false)
    end
  end

  def with_fake_sync(sync)
    previous = Admin::GenericEventsController.performance_sync_builder
    Admin::GenericEventsController.performance_sync_builder = -> { sync }
    yield
  ensure
    # class_attribute makes a wrong replacement stick for the rest of the process.
    Admin::GenericEventsController.performance_sync_builder = previous
  end

  test "sync now pulls the performances in and says what changed" do
    show = FactoryBot.create(:show, pretix_sync_performances: true)
    sync = FakeSync.new

    with_fake_sync(sync) { post :sync_performances, params: { id: show } }

    assert_redirected_to admin_show_path(show)
    assert_equal [ show ], sync.events
    assert_match(/2/, flash.to_h.values.join(" "))
  end

  test "sync now reports a pretix failure rather than 500ing" do
    show = FactoryBot.create(:show, pretix_sync_performances: true)
    sync = FakeSync.new(error: Pretix::Client::NotFoundError.new("no such series"))

    with_fake_sync(sync) { post :sync_performances, params: { id: show } }

    assert_redirected_to admin_show_path(show)
    assert_match(/pretix/i, flash.to_h.values.join(" "))
  end

  test "sync now refuses an event that has not opted in" do
    show = FactoryBot.create(:show, pretix_sync_performances: false)
    sync = FakeSync.new

    with_fake_sync(sync) { post :sync_performances, params: { id: show } }

    assert_empty sync.events, "syncing an event with the box unticked would import dates nobody asked for"
  end

  test "editing a synced performance's flags leaves its pretix times alone" do
    show = FactoryBot.create(:show, pretix_sync_performances: true,
                                    start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))
    occurrence = show.event_occurrences.create!(starts_at: Time.zone.local(2026, 3, 4, 19, 30),
                                                admission_at: Time.zone.local(2026, 3, 4, 19, 0),
                                                pretix_subevent_id: 77)

    # What the form posts for a synced row: no starts_at, since its times render as text. The
    # leading "" is the check_boxes hidden field, which is why :all_blank was never usable.
    patch :update, params: { id: show, show: { event_occurrences_attributes: {
      "0" => { id: occurrence.id, note: "Q&A after", cancelled: "1",
               access_flags: [ "", "relaxed" ], _destroy: "0" }
    } } }

    occurrence.reload

    assert_equal Time.zone.local(2026, 3, 4, 19, 30), occurrence.starts_at
    assert_equal Time.zone.local(2026, 3, 4, 19, 0), occurrence.admission_at
    assert_equal 77, occurrence.pretix_subevent_id
    assert_equal "Q&A after", occurrence.note
    assert_predicate occurrence, :cancelled?
    assert_equal [ "relaxed" ], occurrence.access_flags
  end

  test "an event waiting for its ticket shop says so on its admin page" do
    show = FactoryBot.create(:show, pretix_sync_performances: true)
    show.update_columns(pretix_sync_error: "No pretix ticket shop found for \"#{show.slug}\" yet.")

    get :show, params: { id: show }

    assert_response :success
    assert_match(/No pretix ticket shop found/, response.body)
  end

  test "an event syncing happily shows no warning" do
    show = FactoryBot.create(:show, pretix_sync_performances: true)
    show.update_columns(pretix_synced_at: Time.current)

    get :show, params: { id: show }

    assert_response :success
    assert_no_match(/ticket shop found/, response.body)
  end

  test "sync now on an event with no ticket shop yet says so instead of failing" do
    show = FactoryBot.create(:show, pretix_sync_performances: true)
    show.update_columns(pretix_sync_error: "No pretix ticket shop found yet.")
    sync = Class.new do
      def call(_event) = Pretix::PerformanceSync::MISSING_SERIES
    end.new

    with_fake_sync(sync) { post :sync_performances, params: { id: show } }

    assert_redirected_to admin_show_path(show)
    assert_match(/No pretix ticket shop found yet/, flash.to_h.values.join(" "))
  end
end
