require "test_helper"

module Admin
  module Reimbursements
    class AreasControllerTest < ActionController::TestCase
      tests Admin::Reimbursements::AreasController
      include ReimbursementsTestHelpers

      setup do
        @user = users(:admin)
        grant_finance_permission(@user)
        sign_in @user
      end

      test "index requires the finance permission" do
        sign_in users(:committee)
        get :index
        assert_response :forbidden
      end

      # Two rows both reading £5,000.00 under a bare "Agreed total" header mean
      # different things unless the row says which.
      test "the areas index states what each agreed total is a total of" do
        create_reimbursements_area(name: "Cogito show", initial_budget: 5_000)
        create_reimbursements_area(name: "Committee", initial_budget: 5_000,
                                   budget_basis: "net")
        create_reimbursements_area(name: "Unbudgeted")

        get :index

        assert_response :success
        rows = css_select("tbody tr").map { |row| row.text.squish }
        assert(rows.any? { |row| row.include?("Cogito show") && row.include?("£5,000.00 (expenses)") },
               "the spend cap's row does not say so: #{rows.inspect}")
        assert(rows.any? { |row| row.include?("Committee") && row.include?("£5,000.00 (net)") },
               "the net allowance's row does not say so: #{rows.inspect}")
        # "- (expenses)" would read as a claim about expenses, not an unset plan.
        assert(rows.any? { |row| row.include?("Unbudgeted") && !row.include?("(expenses)") },
               "an area with no agreed total was qualified anyway: #{rows.inspect}")
      end

      # The empty hidden field beside a multiple select is what clears the list:
      # without it, removing the last owner posts no owner_ids key at all.
      test "the area form offers its owners as one searchable multi-select" do
        alice = create_reimbursements_person(name: "Alice Owner", email: "alice@example.com")
        bob = create_reimbursements_person(name: "Bob Owner", email: "bob@example.com")
        area = create_reimbursements_area(name: "Cogito")
        area.sync_owner_ids!([ alice.id ])

        get :edit, params: { id: area.record_id }

        assert_response :success
        assert_select "select[name='reimbursements_area[owner_ids][]'][multiple].simple-select2"
        assert_select "input[type=hidden][name='reimbursements_area[owner_ids][]'][value='']"
        assert_select "select[name='reimbursements_area[owner_ids][]'] " \
                      "option[value=#{alice.record_id}][selected]"
        assert_select "select[name='reimbursements_area[owner_ids][]'] " \
                      "option[value=#{bob.record_id}][selected]", false
      end

      test "creates an area with its owners" do
        person = create_reimbursements_person(name: "Alice", email: "alice@example.com")

        assert_difference -> { ::Reimbursements::Area.count }, 1 do
          post :create, params: { name: "Cogito", initial_budget: "£1,200",
                                  owner_ids: [ person.record_id ] }
        end

        area = ::Reimbursements::Area.order(:id).last
        assert_equal "Cogito", area.name
        assert_equal 1200, area.initial_budget, "a typed £1,200 must not store as 0"
        assert_equal [ person.record_id ], area.owner_ids
      end

      # The form's write is REPLACE, and only this test enforces it: DatabaseStore's
      # #sync_area_owners! replaces and #add_area_owners! unions, with identical
      # signatures, so the wrong one fails silently and removal stops working.
      test "removing an owner on the area form actually removes them" do
        alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
        bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")
        area = create_reimbursements_area(name: "Cogito")
        area.sync_owner_ids!([ alice.id, bob.id ])

        patch :update, params: { id: area.record_id, name: "Cogito",
                                 owner_ids: [ alice.record_id ] }

        assert_equal [ alice.record_id ], area.reload.owner_ids
      end

      # DatabaseStore::AREA_FIELDS drops an unlisted column silently, so a net
      # area would come back a spend cap with nothing on screen saying so.
      test "an area created as a net allowance is not silently a spend cap" do
        post :create, params: { name: "Committee", initial_budget: "1000",
                                budget_basis: "net" }

        assert_equal "net", ::Reimbursements::Area.order(:id).last.budget_basis
      end

      test "the form switches an area between a spend cap and a net allowance" do
        area = create_reimbursements_area(name: "Committee")
        assert_equal "expenses", area.budget_basis, "a backfilled area is a spend cap"

        patch :update, params: { id: area.record_id, name: "Committee", budget_basis: "net" }

        assert_equal "net", area.reload.budget_basis
      end

      test "a basis the radio pair cannot offer is ignored, not saved" do
        # save! would raise on the inclusion validation and 500 the form.
        area = create_reimbursements_area(name: "Committee", budget_basis: "net")

        patch :update, params: { id: area.record_id, name: "Committee", budget_basis: "gross" }

        assert_response :redirect
        assert_equal "net", area.reload.budget_basis
      end

      test "rejects a blank name" do
        assert_no_difference -> { ::Reimbursements::Area.count } do
          post :create, params: { name: "" }
        end

        assert_response :unprocessable_entity
      end

      test "adds a budget line to an area through nested attributes" do
        area = create_reimbursements_area(name: "Cogito")

        assert_difference -> { ::Reimbursements::Budget.count }, 1 do
          patch :update, params: {
            id: area.record_id, name: "Cogito",
            budgets_attributes: { "0" => { name: "Cogito: Marketing", nominal_code: "432320" } }
          }
        end

        assert_equal "Cogito: Marketing", area.reload.budgets.last.name
      end

      test "detaching a budget nils its area rather than deleting it" do
        area = create_reimbursements_area(name: "Cogito")
        budget = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          patch :update, params: {
            id: area.record_id, name: "Cogito",
            budgets_attributes: { "0" => { id: budget.id, area_id: "" } }
          }
        end

        assert_nil budget.reload.area
      end

      # An area with no owners switches its budgets' sign-off gate off
      # (OwnerReview.gate_applies? is false), so the form says so.
      test "the area form warns when the area has no owners" do
        area = create_reimbursements_area(name: "Cogito")

        get :edit, params: { id: area.record_id }

        assert_response :success
        assert_match(/skip budget-owner sign-off/, response.body)
      end

      test "the area form does not warn when the area has an owner" do
        person = create_reimbursements_person(name: "Alice", email: "alice@example.com")
        area = create_reimbursements_area(name: "Cogito")
        area.sync_owner_ids!([ person.id ])

        get :edit, params: { id: area.record_id }

        assert_response :success
        assert_no_match(/skip budget-owner sign-off/, response.body)
      end

      # A line with neither year nor centre is lenient-scoped into every year's and
      # centre's list and every producer's picker (the state BudgetImport#adoptions
      # prevents), so it takes the area's own.
      test "a budget line added through the area inherits its year and cost centre" do
        year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2027", active: true)
        centre = ::Reimbursements::CostCentre.default
        area = create_reimbursements_area(name: "Cogito", financial_year: year, cost_centre: centre)

        patch :update, params: {
          id: area.record_id, name: "Cogito",
          budgets_attributes: { "0" => { name: "Cogito: Marketing", nominal_code: "432320" } }
        }

        budget = area.reload.budgets.last
        assert_equal year.id, budget.financial_year_id
        assert_equal centre.id, budget.cost_centre_id
      end

      # The form posts EVERY child row, so requiring a nominal code of all of them
      # would lock an area holding one code-less line (supported state) out of its
      # own form, Detach included.
      test "an area holding a code-less line can still be saved" do
        area = create_reimbursements_area(name: "Cogito")
        line = create_reimbursements_budget(name: "Cogito: Marketing", nominal_code: "",
                                            area: area)

        patch :update, params: {
          id: area.record_id, name: "Cogito Autumn",
          budgets_attributes: { "0" => { id: line.id, name: line.name, nominal_code: "" } }
        }

        assert_redirected_to edit_admin_reimbursements_area_path(area.record_id)
        assert_equal "Cogito Autumn", area.reload.name
      end

      # The Add row's Type select has no blank option, so an untouched row still
      # posts budget_type; :all_blank would build it with no name and 500 in
      # save!. Untouched has to mean the fields the operator fills.
      test "an untouched Add budget line row is dropped rather than 500ing the form" do
        area = create_reimbursements_area(name: "Cogito")

        patch :update, params: {
          id: area.record_id, name: "Cogito",
          budgets_attributes: { "0" => { name: "", nominal_code: "",
                                         budget_type: "Expense", initial_budget: "" } }
        }

        assert_redirected_to edit_admin_reimbursements_area_path(area.record_id)
        assert_empty area.reload.budgets
      end

      # A truncated POST with neither name nor code key: the key guard must read
      # the lambda's fields, or the row is absent there, touched in the lambda
      # and raises in save!.
      test "a row posting only a figure, with no name or code key at all, is reported" do
        area = create_reimbursements_area(name: "Cogito")

        patch :update, params: {
          id: area.record_id, name: "Cogito",
          budgets_attributes: { "0" => { budget_type: "Expense", initial_budget: "500" } }
        }

        assert_response :unprocessable_entity
        assert_empty area.reload.budgets
      end

      # A figure with no name is half-filled, not untouched: report it rather than
      # drop a line the operator thinks they added.
      test "a new budget row carrying only a figure is reported, not dropped" do
        area = create_reimbursements_area(name: "Cogito")

        patch :update, params: {
          id: area.record_id, name: "Cogito",
          budgets_attributes: { "0" => { name: "", nominal_code: "",
                                         budget_type: "Expense", initial_budget: "500" } }
        }

        assert_response :unprocessable_entity
        assert_match(/needs a name and a nominal code/, flash[:alert].to_s + response.body)
        assert_empty area.reload.budgets
      end

      test "a code-less line can still be detached from its area" do
        area = create_reimbursements_area(name: "Cogito")
        line = create_reimbursements_budget(name: "Cogito: Marketing", nominal_code: "",
                                            area: area)

        patch :update, params: {
          id: area.record_id, name: "Cogito",
          budgets_attributes: { "0" => { id: line.id, name: line.name, nominal_code: "",
                                         area_id: "" } }
        }

        assert_nil line.reload.area_id
      end

      # Unlike its code, an existing row's name is required: blank would raise in save!.
      test "blanking an existing line's name is rejected rather than raising" do
        area = create_reimbursements_area(name: "Cogito")
        line = create_reimbursements_budget(name: "Cogito: Marketing", area: area)

        patch :update, params: {
          id: area.record_id, name: "Cogito",
          budgets_attributes: { "0" => { id: line.id, name: " ", nominal_code: "432320" } }
        }

        assert_response :unprocessable_entity
        assert_equal "Cogito: Marketing", line.reload.name
      end

      test "a budget line with no nominal code is rejected, not filed under (none)" do
        area = create_reimbursements_area(name: "Cogito")

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          patch :update, params: {
            id: area.record_id, name: "Cogito",
            budgets_attributes: { "0" => { name: "Cogito: Marketing", nominal_code: " " } }
          }
        end

        assert_response :unprocessable_entity
      end

      test "a budget line with a blank name is rejected rather than raising" do
        area = create_reimbursements_area(name: "Cogito")

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          patch :update, params: {
            id: area.record_id, name: "Cogito",
            budgets_attributes: { "0" => { name: " ", nominal_code: "432320" } }
          }
        end

        assert_response :unprocessable_entity
      end

      test "a nested budget row cannot carry fields the form does not render" do
        area = create_reimbursements_area(name: "Cogito")

        patch :update, params: {
          id: area.record_id, name: "Cogito",
          budgets_attributes: { "0" => { name: "Cogito: Marketing", nominal_code: "432320",
                                         active: "0", cost_centre_id: "999" } }
        }

        budget = area.reload.budgets.last
        assert budget.active, "a field the form never renders must not be writable through it"
        refute_equal 999, budget.cost_centre_id
      end

      test "a new nested row takes its type and initial budget" do
        area = create_reimbursements_area(name: "Cogito")

        patch :update, params: {
          id: area.record_id, name: "Cogito",
          budgets_attributes: { "0" => { name: "Ticket income", nominal_code: "301000",
                                         budget_type: "Income", initial_budget: "5000" } }
        }

        budget = area.reload.budgets.last
        assert_equal "Income", budget.budget_type
        assert_equal BigDecimal("5000"), budget.initial_budget
      end

      # A raw "£1,200" would store as 0 through AR's to_d.
      test "a typed amount goes through the parser" do
        area = create_reimbursements_area(name: "Cogito")

        patch :update, params: {
          id: area.record_id, name: "Cogito",
          budgets_attributes: { "0" => { name: "Marketing", nominal_code: "432320",
                                         initial_budget: "£1,200" } }
        }

        assert_equal BigDecimal("1200"), area.reload.budgets.last.initial_budget
      end

      test "an unreadable amount blocks the save and names itself" do
        area = create_reimbursements_area(name: "Cogito")

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          patch :update, params: {
            id: area.record_id, name: "Cogito",
            budgets_attributes: { "0" => { name: "Marketing", nominal_code: "432320",
                                           initial_budget: "about a grand" } }
          }
        end

        assert_response :unprocessable_entity
        assert_match(/isn't an amount/, response.body)
      end

      # A blank must not become a £0 plan (PlannedAmount), and on an existing row
      # must leave the figure alone.
      test "a blank amount leaves an existing line's figure where it is" do
        area = create_reimbursements_area(name: "Cogito")
        budget = create_reimbursements_budget(name: "Marketing", area: area,
                                              initial_budget: BigDecimal("800"))

        patch :update, params: {
          id: area.record_id, name: "Cogito",
          budgets_attributes: { "0" => { id: budget.id, name: "Marketing",
                                         nominal_code: "432320", initial_budget: "" } }
        }

        assert_equal BigDecimal("800"), budget.reload.initial_budget
      end

      test "a blank amount on a new line leaves it with no plan rather than a £0 one" do
        area = create_reimbursements_area(name: "Cogito")

        patch :update, params: {
          id: area.record_id, name: "Cogito",
          budgets_attributes: { "0" => { name: "Marketing", nominal_code: "432320",
                                         initial_budget: "" } }
        }

        assert_nil area.reload.budgets.last.initial_budget
      end

      test "an unknown budget type is refused" do
        area = create_reimbursements_area(name: "Cogito")

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          patch :update, params: {
            id: area.record_id, name: "Cogito",
            budgets_attributes: { "0" => { name: "Marketing", nominal_code: "432320",
                                           budget_type: "Nonsense" } }
          }
        end

        assert_response :unprocessable_entity
        assert_match(/valid budget type/, response.body)
      end

      test "the form renders a type and an amount for each row" do
        area = create_reimbursements_area(name: "Cogito")
        create_reimbursements_budget(name: "Marketing", area: area)

        get :edit, params: { id: area.record_id }

        assert_response :success
        assert_select "select[name*='[budget_type]']"
        assert_select "input[name*='[initial_budget]']"
      end
    end
  end
end
