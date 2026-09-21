require "test_helper"

module Admin
  module Reimbursements
    ##
    # The "Your shows and budgets" half of My Budgets: one row per thing the
    # signed-in person is responsible for, with the four figures an owner reads.
    #
    # Owning a SHOW is owning its area, and its lines inherit that — so the row
    # is the area, not one row per line, which is what the page used to print.
    class MyBudgetsRowsTest < ActionController::TestCase
      tests Admin::Reimbursements::MyBudgetsController
      include ReimbursementsTestHelpers

      setup do
        producer = Role.create!(name: "Producer")
        producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
        users(:member).add_role("Producer")
        @user = users(:member)
        @owner = create_reimbursements_person(email: @user.email, name: "Olive Owner")
        @submitter = create_reimbursements_person(email: "sam@example.com", name: "Sam Submitter")
        sign_in @user
      end

      test "a show the person owns is one row, not one row per line" do
        area = create_reimbursements_area(name: "Cogito", initial_budget: 4_600)
        area.owners << @owner
        create_reimbursements_budget(name: "Marketing", initial_budget: 1_100, area: area)
        create_reimbursements_budget(name: "Set", initial_budget: 1_500, area: area)

        get :index

        assert_response :success
        rows = css_select("tbody tr").map { |row| row.text.squish }
        assert_equal 1, rows.size, "expected one row for the area: #{rows.inspect}"
        assert_includes rows.first, "Cogito"
        assert_includes rows.first, "2 lines"
      end

      # Budget − Spent − Waiting, which is NOT Budget#remaining: a claim still
      # waiting for approval is money an owner cannot spend twice.
      test "Left counts the claims still waiting for approval" do
        area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
        area.owners << @owner
        line = create_reimbursements_budget(name: "Marketing", initial_budget: 1_000, area: area)
        create_reimbursements_expense(person: @submitter, budget: line, amount: 200,
                                      amount_excl_vat: 200,
                                      status: ::Reimbursements::Status::APPROVED)
        create_reimbursements_expense(person: @submitter, budget: line, amount: 300,
                                      amount_excl_vat: 300,
                                      status: ::Reimbursements::Status::PENDING)

        get :index

        row = css_select("tbody tr").first.text.squish
        assert_includes row, "£200.00", "spent is missing: #{row}"
        assert_includes row, "£300.00", "waiting is missing: #{row}"
        assert_includes row, "£500.00", "Left should be 1000 - 200 - 300: #{row}"
      end

      # A £0 agreed total with nothing allocated is a figure nobody filled in,
      # not a cap of nothing that all spend is over (Mick's call).
      test "a zero budget reads as unset rather than as an overspend" do
        area = create_reimbursements_area(name: "Last years business", initial_budget: 0)
        area.owners << @owner
        line = create_reimbursements_budget(name: "Last years business", area: area)
        create_reimbursements_expense(person: @submitter, budget: line, amount: 3_273.20,
                                      amount_excl_vat: 3_273.20,
                                      status: ::Reimbursements::Status::PAID)

        get :index

        row = css_select("tbody tr").first.text.squish
        assert_includes row, "no budget set"
        assert_not_includes row, "over"
      end

      test "an area with no agreed total falls back to what its lines add up to" do
        area = create_reimbursements_area(name: "Improverts")
        area.owners << @owner
        create_reimbursements_budget(name: "Marketing", initial_budget: 1_100, area: area)
        create_reimbursements_budget(name: "Retreat", initial_budget: 1_500, area: area)

        get :index

        row = css_select("tbody tr").first.text.squish
        assert_includes row, "£2,600.00"
        assert_includes row, "no total agreed"
      end

      # Two production areas are both called "Tech", in different centres and
      # years, so a bare name would be two identical rows.
      test "each row says which pot and year it belongs to" do
        centre = create_reimbursements_cost_centre(key: "termtime", name: "Bedlam Termtime",
                                                   eusa_code: "BED")
        area = create_reimbursements_area(name: "Tech", initial_budget: 100, cost_centre: centre)
        area.owners << @owner
        create_reimbursements_budget(name: "Tech", initial_budget: 100, area: area)

        get :index

        row = css_select("tbody tr").first.text.squish
        assert_includes row, "Bedlam Termtime"
      end

      test "a loose line the person owns gets its own row" do
        create_reimbursements_budget(name: "Contingency", initial_budget: 500, owners: [ @owner ])

        get :index

        row = css_select("tbody tr").first.text.squish
        assert_includes row, "Contingency"
        assert_includes row, "a single budget, in no area"
      end

      test "income lines are left out of a show's figures" do
        area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
        area.owners << @owner
        create_reimbursements_budget(name: "Set", initial_budget: 1_000, area: area)
        create_reimbursements_budget(name: "Ticket income", initial_budget: 800, area: area,
                                     budget_type: "Income")

        get :index

        row = css_select("tbody tr").first.text.squish
        assert_includes row, "£1,000.00", "the budget should be the expense line only: #{row}"
        assert_not_includes row, "£1,800.00"
      end

      # The inbox gathers the work across every show, so a many-show owner has
      # one place to do it rather than hunting card by card.
      test "claims waiting for sign-off are listed with how long they have waited" do
        area = create_reimbursements_area(name: "Cogito", initial_budget: 1_000)
        area.owners << @owner
        line = create_reimbursements_budget(name: "Marketing", initial_budget: 1_000, area: area)
        create_reimbursements_expense(person: @submitter, budget: line, amount: 64.20,
                                      status: ::Reimbursements::Status::PENDING,
                                      description: "Poster reprint",
                                      submitted_at: 3.days.ago)

        get :index

        assert_includes response.body, "Poster reprint"
        assert_includes response.body, "waiting 3 days"
        assert_includes css_select("tbody tr").first.text.squish, "1 waiting"
      end
    end
  end
end
