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

      # THE form's write is REPLACE, and this is the only thing enforcing it.
      # DatabaseStore carries two owner writes with the identical
      # (record_id, person_ids) signature — #sync_area_owners! replaces,
      # #add_area_owners! unions — so reaching for the wrong one here is silent:
      # removal just stops working, and removal is the only way to take a show's
      # sign-off authority off an area.
      test "removing an owner on the area form actually removes them" do
        alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
        bob = create_reimbursements_person(name: "Bob", email: "bob@example.com")
        area = create_reimbursements_area(name: "Cogito")
        area.sync_owner_ids!([ alice.id, bob.id ])

        patch :update, params: { id: area.record_id, name: "Cogito",
                                 owner_ids: [ alice.record_id ] }

        assert_equal [ alice.record_id ], area.reload.owner_ids
      end

      test "the form switches an area between a spend cap and a net allowance" do
        area = create_reimbursements_area(name: "Committee")
        assert_equal "expenses", area.budget_basis, "a backfilled area is a spend cap"

        patch :update, params: { id: area.record_id, name: "Committee", budget_basis: "net" }

        assert_equal "net", area.reload.budget_basis
      end

      test "a basis the radio pair cannot offer is ignored, not saved" do
        # save! would raise on Area's inclusion validation and 500 the form,
        # losing everything else typed on it.
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

      # An area with no owners switches its budgets' sign-off gate OFF entirely
      # (OwnerReview.gate_applies? is false with no owners), so say so where it
      # is set — the spirit of the budgets index's "No owner" badge.
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

      # --- Nested budget rows -------------------------------------------------
      # DatabaseStore#in_year and #in_cost_centre are deliberately lenient, so a
      # line stamped with neither shows up in EVERY year's and EVERY centre's
      # list — and, being active by default, in every producer's budget picker
      # in both cost centres. That is the exact state BudgetImport#adoptions
      # exists to prevent, and the area's own coordinates are knowable here.
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

      # This form posts EVERY child row, not just the one being edited, so a
      # rule requiring a nominal code of all of them locks an area holding one
      # code-less line out of its own form: its name, agreed total, owners and
      # notes, AND the "Detach from this area" control that would remove the
      # offending line. A blank code is supported state — the importer allows
      # it and the overview has a "(none)" bucket for it — so this is reachable
      # with ordinary data, the backfill's included.
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

      # An existing row's NAME is a different matter from its code: Budget
      # validates the name, so a blank one is never supported state and reaches
      # save!, which raises and 500s the form.
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

      # Budget validates its name, so a blank one reached save! and 500'd the
      # form rather than reporting anything the operator could act on.
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
                                         initial_budget: "£1,200", active: "0" } }
        }

        budget = area.reload.budgets.last
        # AR casts a raw String to a decimal column with to_d, so a permitted
        # "£1,200" would have stored as 0 — a figure nobody typed.
        assert_nil budget.initial_budget
        assert budget.active
      end
    end
  end
end
