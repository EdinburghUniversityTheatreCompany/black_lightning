require "test_helper"

module Admin
  module Reimbursements
    ##
    # Who may open an area's page. It is the one reimbursements screen two
    # different audiences share, so the gate is a union — finance, or a person
    # this area's owner set names — and a refusal is a 404 rather than a 403,
    # following ReceiptFilesController: a 403 confirms the area exists to
    # someone who has no business knowing which shows the society is running.
    class AreaPageAccessTest < ActionController::TestCase
      tests Admin::Reimbursements::AreasController
      include ReimbursementsTestHelpers

      setup do
        producer = Role.create!(name: "Producer")
        producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
        users(:member).add_role("Producer")

        @owner = create_reimbursements_person(email: users(:member).email, name: "Olive Owner")
        @area = create_reimbursements_area(name: "Cogito", initial_budget: 4_600)
        @area.owners << @owner
        @someone_elses = create_reimbursements_area(name: "Macbeth", initial_budget: 3_000)
      end

      test "finance can open any area, owned or not" do
        grant_finance_permission(users(:admin))
        sign_in users(:admin)

        get :show, params: { id: @someone_elses.record_id }

        assert_response :success
      end

      test "an owner can open the area they own" do
        sign_in users(:member)

        get :show, params: { id: @area.record_id }

        assert_response :success
      end

      # The gate reads the area's owner set, so a producer who owns a DIFFERENT
      # show is as much a stranger to this one as somebody who owns nothing.
      test "an owner of another area gets a 404, not a 403" do
        sign_in users(:member)

        get :show, params: { id: @someone_elses.record_id }

        assert_response :not_found
      end

      test "a producer who owns nothing gets a 404" do
        create_reimbursements_person(email: "nobody@example.com", name: "No Body")
        sign_in users(:member)
        @area.owners.destroy_all

        get :show, params: { id: @area.record_id }

        assert_response :not_found
      end

      # A line inherits its area's owners, so owning a line INSIDE an area is
      # the same claim as owning the area — the sign-off gate already reads it
      # that way (Budget#owners resolves through the area).
      test "owning a loose budget opens that budget's own page, not an area's" do
        loose = create_reimbursements_budget(name: "Contingency", owners: [ @owner ], initial_budget: 500)
        sign_in users(:member)

        get :show, params: { id: @area.record_id }
        assert_response :success

        assert_includes loose.own_owners, @owner, "the loose line's owner row was not written"
      end

      test "a signed-out visitor is sent to sign in rather than shown the page" do
        sign_out users(:member)

        get :show, params: { id: @area.record_id }

        assert_redirected_to new_user_session_path
      end
    end
  end
end
