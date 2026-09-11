require "test_helper"

module Admin
  module Reimbursements
    ##
    # Stripping the "Area: " prefix made budget names legitimately non-unique —
    # on the live Fringe data three lines are called "Marketing" and three
    # "Other", all on nominal code 432320 — so every surface that names a
    # budget on its own has to say which show it belongs to
    # (Budget#display_name). The six surfaces where a human PICKS one are the
    # money path: a wrong pick charges another show AND moves the claim to that
    # show's owner gate.
    #
    # An integration test rather than six functional ones: the point is that
    # ONE derivation reaches every controller. Both seeded budgets are
    # identically named, so every assertion here reddens on the bare name.
    class BudgetDisplayNameTest < ActionDispatch::IntegrationTest
      include ReimbursementsTestHelpers
      include Devise::Test::IntegrationHelpers

      setup do
        @finance = users(:admin)
        @producer = users(:member)
        grant_producer_permission(@producer)

        @cogito = create_reimbursements_area(name: "Cogito")
        @improverts = create_reimbursements_area(name: "Improverts")
        # Same name, same nominal code, different show: the live shape.
        @cogito_marketing = create_reimbursements_budget(name: "Marketing", nominal_code: "432320",
                                                         area: @cogito, initial_budget: BigDecimal("400"))
        @improverts_marketing = create_reimbursements_budget(name: "Marketing", nominal_code: "432320",
                                                             area: @improverts,
                                                             initial_budget: BigDecimal("250"))
        @contingency = create_reimbursements_budget(name: "Contingency", nominal_code: "439999")

        @person = create_reimbursements_person(email: @producer.email)
        @claim = create_reimbursements_expense(person: @person, budget: @cogito_marketing)
      end

      # The whole option list of one select, never a body match: the page also
      # carries area headings and card titles.
      def option_texts(selector)
        css_select("#{selector} option").map { |option| option.text.strip }
      end

      def assert_both_shows_named(labels, where)
        assert_includes labels, "Cogito — Marketing", where
        assert_includes labels, "Improverts — Marketing", where
        assert_not_includes labels, "Marketing", "#{where}: an unqualified option is ambiguous"
      end

      test "the producer's submission picker names the show on each line" do
        sign_in @producer

        get new_admin_reimbursements_expense_path

        assert_response :success
        assert_both_shows_named(option_texts("select#reimbursements_expense_form_budget_record_id"),
                                "the submission picker")
      end

      test "an area-less line keeps its bare name in the picker" do
        sign_in @producer

        get new_admin_reimbursements_expense_path

        assert_includes option_texts("select#reimbursements_expense_form_budget_record_id"),
                        "Contingency"
      end

      test "the picker is ordered by the label it prints" do
        sign_in @producer

        get new_admin_reimbursements_expense_path

        offered = option_texts("select#reimbursements_expense_form_budget_record_id") -
                  [ "Choose a budget…" ]
        assert_equal offered.sort, offered,
                     "the options read out of order, which is what sorting by the bare name does"
      end

      test "the batch budget-update form names the show in each row and each field's label" do
        sign_in @finance

        get new_admin_reimbursements_budget_update_path

        assert_response :success
        rows = css_select("tbody tr td:first-child").map { |cell| cell.text.strip }
        assert_equal [ "Cogito — Marketing", "Contingency", "Improverts — Marketing" ], rows
        labels = css_select("input[type=text]").filter_map { |input| input["aria-label"] }
        assert_equal [ "New forecast for Cogito — Marketing", "New forecast for Contingency",
                       "New forecast for Improverts — Marketing" ], labels
      end

      test "Review's re-assign picker names the show on each line" do
        sign_in @finance

        get admin_reimbursements_review_path

        assert_response :success
        assert_both_shows_named(option_texts("select#budget_record_id_#{@claim.record_id}"),
                                "Review's budget picker")
      end

      test "the finance expense-edit picker names the show on each line" do
        sign_in @finance

        get edit_admin_reimbursements_expense_edit_path(@claim.record_id)

        assert_response :success
        assert_both_shows_named(option_texts("select#budget_record_id"),
                                "the expense-edit picker")
      end

      test "the expense-edit index's budget filter names the show on each line" do
        sign_in @finance

        get admin_reimbursements_expense_edits_path

        assert_response :success
        assert_both_shows_named(option_texts("select#budget"), "the budget filter")
      end

      test "the actuals conversion picker names the show on each line" do
        actual = create_reimbursements_actual(nominal_code: "432320", debit: BigDecimal("20"))
        sign_in @finance

        get new_expense_admin_reimbursements_actual_path(actual.record_id)

        assert_response :success
        assert_both_shows_named(option_texts("select#reimbursements_expense_form_budget_record_id"),
                                "the actuals conversion picker")
      end

      # --- Read-only surfaces -------------------------------------------------

      test "the producer's own claim list and claim page name the show" do
        sign_in @producer

        get admin_reimbursements_expenses_path
        assert_response :success
        # The CELL, not the body: a page that grew an area heading elsewhere
        # would satisfy a body match with the budget column still bare.
        assert_includes css_select("td").map { |cell| cell.text.strip }, "Cogito — Marketing"

        get admin_reimbursements_expense_path(@claim.record_id)
        assert_response :success
        assert_equal "Cogito — Marketing", definition_value("Budget")
      end

      # The value rendered beside the <dt> reading +term+ on the claim page.
      def definition_value(term)
        css_select("div").find { |node| node.at_css("dt")&.text&.strip == term }
                         &.at_css("dd")&.text&.strip
      end

      test "My Budgets names the show on each budget card" do
        @cogito.owners << @person
        @improverts.owners << @person
        sign_in @producer

        get admin_reimbursements_my_budgets_path

        assert_response :success
        titles = css_select("span.card-title").map { |heading| heading.text.strip }
        assert_includes titles, "Cogito — Marketing"
        assert_includes titles, "Improverts — Marketing"
        assert_not_includes titles, "Marketing"
      end

      # The rowgroup heading above the row is not announced with the button, so
      # three buttons reading "Edit Marketing" is genuinely ambiguous.
      test "the grouped budgets index keeps bare row names but names the show on each Edit" do
        sign_in @finance

        get admin_reimbursements_budgets_path

        assert_response :success
        assert_equal [ "Edit Cogito — Marketing", "Edit Contingency", "Edit Improverts — Marketing" ],
                     css_select("a[aria-label^='Edit ']").map { |link| link["aria-label"] }.sort
        # The row itself stays bare: the area is the heading right above it.
        assert_includes css_select("td span.font-medium").map { |cell| cell.text.strip }, "Marketing"
      end

      test "the overview's nominal-code card names the show, and its area card does not repeat it" do
        sign_in @finance

        get overview_admin_reimbursements_budgets_path

        assert_response :success
        # The two cards render the SAME partial, and only one of them has the
        # area written above the row.
        assert_equal [ "Cogito — Marketing", "Improverts — Marketing" ],
                     budget_links_under("Nominal code 432320")
        assert_equal [ "Marketing" ], budget_links_under("Cogito")
        assert_equal [ "Marketing" ], budget_links_under("Improverts")
      end

      # Every budget link in the row group whose heading reads EXACTLY +heading+
      # — a prefix match would also take the unattributed-actuals card's own
      # groups further down the page ("Nominal code 432320 (net £20.00)").
      def budget_links_under(heading)
        css_select("tbody").flat_map do |body|
          cell = body.at_css("th[scope=rowgroup]")
          next [] if cell.nil?

          # The area card writes the area's name in its own span beside the
          # area's figures; the nominal card's heading is the whole cell.
          label = (cell.at_css("span.font-semibold") || cell).text.squish
          next [] unless label == heading

          body.css("td:first-child a").map { |link| link.text.strip }
        end
      end
    end
  end
end
