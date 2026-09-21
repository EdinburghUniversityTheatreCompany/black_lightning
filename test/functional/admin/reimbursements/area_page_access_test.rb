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

      # The claims table renders Kaminari's pager, and a ViewComponent gets no
      # helpers of its own — so an area WITH claims 500ed while every test that
      # only ever built an empty one passed. Renders the real page with claims.
      test "an area with claims renders its claims table and its pager" do
        grant_finance_permission(users(:admin))
        sign_in users(:admin)
        line = create_reimbursements_budget(name: "Marketing", initial_budget: 1_100, area: @area)
        payee = create_reimbursements_person(email: "payee@example.com", name: "Nadia Ferreira")
        30.times do |n|
          create_reimbursements_expense(person: payee, budget: line, amount: 10 + n,
                                        description: "Claim number #{n}",
                                        status: ::Reimbursements::Status::PAID)
        end

        get :show, params: { id: @area.record_id }

        assert_response :success
        assert_equal 25, css_select("table").last.css("tbody tr").size,
                     "the claims table should page at 25"
        assert_select "nav[aria-label=?]", "Page Navigation", minimum: 1
      end

      # The tabs are URL state, so a status the portal knows filters the list.
      test "the claims tab filters by where each claim has got to" do
        grant_finance_permission(users(:admin))
        sign_in users(:admin)
        line = create_reimbursements_budget(name: "Marketing", initial_budget: 1_100, area: @area)
        payee = create_reimbursements_person(email: "payee@example.com", name: "Nadia Ferreira")
        create_reimbursements_expense(person: payee, budget: line, description: "A paid one",
                                      status: ::Reimbursements::Status::PAID)
        create_reimbursements_expense(person: payee, budget: line, description: "A waiting one",
                                      status: ::Reimbursements::Status::PENDING)

        get :show, params: { id: @area.record_id, status: "paid" }

        assert_response :success
        assert_includes response.body, "A paid one"
        assert_not_includes response.body, "A waiting one"
      end

      # An owner reads a show's claims; nothing here may turn that into a
      # directory of its members' bank details.
      test "an owner sees the claims but no bank details" do
        line = create_reimbursements_budget(name: "Marketing", initial_budget: 1_100, area: @area)
        payee = create_reimbursements_person(email: "payee@example.com", name: "Nadia Ferreira",
                                             sort_code: "08-99-99", account_number: "66374958")
        create_reimbursements_expense(person: payee, budget: line, description: "Poster reprint",
                                      status: ::Reimbursements::Status::PAID)
        sign_in users(:member)

        get :show, params: { id: @area.record_id }

        assert_response :success
        assert_includes response.body, "Poster reprint"
        assert_not_includes response.body, "66374958"
        assert_not_includes response.body, "08-99-99"
      end

      test "a signed-out visitor is sent to sign in rather than shown the page" do
        sign_out users(:member)

        get :show, params: { id: @area.record_id }

        assert_redirected_to new_user_session_path
      end
    end
  end
end
