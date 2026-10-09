require "test_helper"

module Admin
  module Reimbursements
    ##
    # Budget names are not unique (three live Fringe lines are called
    # "Marketing" on one nominal code), so every surface naming a budget on its
    # own must say which show it belongs to (Budget#display_name). The six
    # pickers are the money path: a wrong pick charges another show and moves
    # the claim to that show's owner gate.
    #
    # An integration test because the point is that ONE derivation reaches
    # every controller. Both seeded budgets share a name, so every assertion
    # reddens on the bare name.
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
        assert_includes labels, "Cogito: Marketing", where
        assert_includes labels, "Improverts: Marketing", where
        assert_not_includes labels, "Marketing", "#{where}: an unqualified option is ambiguous"
      end

      test "the producer's submission picker names the show on each line and keeps bare names" do
        sign_in @producer

        get new_admin_reimbursements_expense_path

        assert_response :success
        labels = option_texts("select#reimbursements_expense_form_budget_record_id") -
                 [ "Choose a budget…" ]
        assert_both_shows_named(labels, "the submission picker")
        assert_includes labels, "Contingency"
        groups = css_select("select#reimbursements_expense_form_budget_record_id optgroup")
        assert_equal ::Reimbursements::Budget::NO_AREA_GROUP, groups.last["label"]
      end

      test "the batch budget-update form names the show in each row and each field's label" do
        sign_in @finance

        get new_admin_reimbursements_budget_update_path

        assert_response :success
        rows = css_select("tbody tr td:first-child").map { |cell| cell.text.strip }
        assert_equal [ "Cogito: Marketing", "Contingency", "Improverts: Marketing" ], rows
        labels = css_select("input[type=text]").filter_map { |input| input["aria-label"] }
        assert_equal [ "New forecast for Cogito: Marketing", "New forecast for Contingency",
                       "New forecast for Improverts: Marketing" ], labels
      end

      test "Review's re-assign picker names the show on each line" do
        sign_in @finance

        get admin_reimbursements_review_path

        assert_response :success
        labels = option_texts("select#budget_record_id_#{@claim.record_id}")
        assert_both_shows_named(labels, "Review's budget picker")
        assert_equal labels.sort, labels, "sorting by the bare name puts Contingency first"
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
        # This picker appends " · <code>" to each option; compare the label
        # before it.
        labels = option_texts("select#reimbursements_expense_form_budget_record_id")
                 .map { |text| text.split(" · ").first }
        assert_both_shows_named(labels, "the actuals conversion picker")
      end

      # --- Read-only surfaces -------------------------------------------------

      test "the producer's own claim list and claim page name the show" do
        sign_in @producer

        get admin_reimbursements_expenses_path
        assert_response :success
        # The cell, not the body, which an area heading elsewhere would satisfy.
        assert_includes css_select("td").map { |cell| cell.text.strip }, "Cogito: Marketing"

        get admin_reimbursements_expense_path(@claim.record_id)
        assert_response :success
        assert_equal "Cogito: Marketing", definition_value("Budget")
      end

      # The value rendered beside the <dt> reading +term+ on the claim page.
      def definition_value(term)
        css_select("div").find { |node| node.at_css("dt")&.text&.strip == term }
                         &.at_css("dd")&.text&.strip
      end

      # The rowgroup heading above the row is not announced with the button, so
      # three buttons reading "Edit Marketing" is genuinely ambiguous.
      test "the grouped budgets index keeps bare row names but names the show on each Edit" do
        sign_in @finance

        get admin_reimbursements_budgets_path

        assert_response :success
        assert_equal [ "Edit Cogito: Marketing", "Edit Contingency", "Edit Improverts: Marketing" ],
                     css_select("a[aria-label^='Edit ']").map { |link| link["aria-label"] }.sort
        # The row's name stays bare (the area heads the group) and links to
        # the edit form.
        assert_includes css_select("td a.font-medium").map { |cell| cell.text.strip }, "Marketing"
        # And that link carries the QUALIFIED name for a screen reader, without
        # becoming a second control announcing "Edit …" on the same row.
        assert_includes css_select("td a.font-medium").map { |link| link["aria-label"] },
                        "Cogito: Marketing"
      end

      test "the overview's nominal-code card names the show, and its area card does not repeat it" do
        sign_in @finance

        get overview_admin_reimbursements_budgets_path

        assert_response :success
        # The two cards render the SAME partial, and only one of them has the
        # area written above the row.
        assert_equal [ "Cogito: Marketing", "Improverts: Marketing" ],
                     budget_links_under("Nominal code 432320")
        assert_equal [ "Marketing" ], budget_links_under("Cogito")
        assert_equal [ "Marketing" ], budget_links_under("Improverts")
      end

      # Every budget link in the row group whose heading reads EXACTLY +heading+:
      # a prefix match would also take the unattributed card's groups
      # ("Nominal code 432320 (net £20.00)").
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
