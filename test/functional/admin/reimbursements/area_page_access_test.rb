require "test_helper"

module Admin
  module Reimbursements
    ##
    # Who may open an area's page: finance, or a person the area's owners name. A
    # refusal is a 404, not a 403, which would confirm the area exists.
    class AreaPageAccessTest < ActionController::TestCase
      tests Admin::Reimbursements::AreasController
      include ReimbursementsTestHelpers

      setup do
        grant_producer_permission(users(:member))

        @owner = create_reimbursements_person(email: users(:member).email, name: "Olive Owner")
        @area = create_reimbursements_area(name: "Cogito", initial_budget: 4_600)
        @area.owners << @owner
        @someone_elses = create_reimbursements_area(name: "Macbeth", initial_budget: 3_000)
      end

      # Owning a different area makes you a stranger to this one.
      test "an owner of another area gets a 404, not a 403" do
        sign_in users(:member)

        get :show, params: { id: @someone_elses.record_id }

        assert_response :not_found
      end

      # The claims table renders Kaminari's pager and a ViewComponent gets no
      # helpers, so an area WITH claims 500ed while every empty-area test passed.
      test "finance opens an area it does not own: claims table, pager and tabs" do
        grant_finance_permission(users(:admin))
        sign_in users(:admin)
        line = create_reimbursements_budget(name: "Marketing", initial_budget: 1_100, area: @area)
        payee = create_reimbursements_person(email: "payee@example.com", name: "Nadia Ferreira")
        30.times do |n|
          create_reimbursements_expense(person: payee, budget: line, amount: 10 + n,
                                        description: "Claim number #{n}",
                                        status: ::Reimbursements::Status::PAID)
        end
        # Newest, so unfiltered it would head page 1: its absence proves the tab filters.
        create_reimbursements_expense(person: payee, budget: line, description: "A waiting one",
                                      status: ::Reimbursements::Status::PENDING)

        get :show, params: { id: @area.record_id, status: "paid" }

        assert_response :success
        assert_equal 25, css_select("table").last.css("tbody tr").size,
                     "the claims table should page at 25"
        assert_select "nav[aria-label=?]", "Page Navigation", minimum: 1
        assert_not_includes response.body, "A waiting one"
      end

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
