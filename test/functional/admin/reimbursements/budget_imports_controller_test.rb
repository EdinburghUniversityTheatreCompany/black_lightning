require "test_helper"

module Admin
  module Reimbursements
    class BudgetImportsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      FY = ::Reimbursements::FinancialYear
      # Derived, never retyped: see ReimbursementsTestHelpers#budget_import_sheet.
      HEADERS = ::Reimbursements::BudgetImport::TSV_HEADERS.join("\t").freeze

      setup do
        @user = users(:member)
        grant_finance_permission(@user)
        @year = FY.create!(label: "Fringe 2027")
        @cost_centre = ::Reimbursements::CostCentre.default
      end

      alias tsv budget_import_sheet

      def preview_params(text, **extra)
        { year: @year.key, pasted_text: text,
          cost_centre_id: @cost_centre.id }.merge(extra)
      end

      # --- Step 1: the form --------------------------------------------------

      test "show says so when no financial year is set up at all" do
        FY.delete_all
        sign_in @user

        get :show

        assert_response :success
        assert_nil assigns(:selected_financial_year)
        assert_match(/No financial year is set up yet/, response.body)
      end

      test "preview writes nothing and refuses when no financial year exists" do
        FY.delete_all
        sign_in @user

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          post :preview, params: { pasted_text: tsv("Props\t4000\tExpense\t1200\t\t"),
                                   cost_centre_id: @cost_centre.id }
        end

        assert_response :unprocessable_entity
        assert_nil assigns(:import)
      end

      # Turbo Drive drops a non-redirect response to a form POST, so every step
      # must render inside the frame. Only a browser would see it otherwise.
      test "every wizard step renders inside the turbo frame" do
        sign_in @user

        get :show, params: { year: @year.key }
        assert_match(/turbo-frame id="budget_import"/, response.body)

        post :preview, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"))
        assert_match(/turbo-frame id="budget_import"/, response.body)

        post :apply, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"))
        assert_match(/turbo-frame id="budget_import"/, response.body)
      end

      # --- Step 2: preview ---------------------------------------------------

      test "preview buckets the pasted sheet without writing anything" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          post :preview, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t",
                                                    "Venue\t4100\tExpense\t800\t\t"))
        end

        assert_response :success
        assert_equal 2, assigns(:import).entries_in(:create).size
      end

      test "preview refuses an empty paste" do
        sign_in @user

        post :preview, params: preview_params("  ")

        assert_response :success
        assert_match(/paste|upload/i, response.body)
        assert_nil assigns(:import)
      end

      test "preview states which column each field was read from" do
        sign_in @user

        post :preview, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"))

        assert_match(/Columns read from your sheet/, response.body)
        assert_select "td", text: "Nominal code"
      end

      test "preview links an unknown owner email to the register-a-person form" do
        sign_in @user

        post :preview, params: preview_params(tsv("Props\t4000\tExpense\t1200\tnobody@example.com\t"))

        assert_equal [ "nobody@example.com" ], assigns(:import).unknown_owner_emails
        assert_includes response.body, new_admin_reimbursements_person_path
      end

      test "preview scopes matching to the year being imported into, not the active year" do
        active_year = FY.create!(label: "Fringe 2026", active: true)
        other = create_reimbursements_budget(name: "Props", initial_budget: 1000)
        other.update!(financial_year: active_year)
        sign_in @user

        post :preview, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"))

        # Last year has a "Props" too; this year hasn't, so it's a create.
        assert_equal 1, assigns(:import).entries_in(:create).size
        assert_empty assigns(:import).entries_in(:revise)
      end

      # --- Areas ---------------------------------------------------------------

      # "Marketing" shares nothing with "Cogito", so only the Area cell can match.
      test "preview shows the area named on the sheet, marked as new" do
        sign_in @user

        post :preview, params: preview_params(
          "Area\tBudget\tNominal code\tType\tAmount\n" \
          "Cogito\tMarketing\t432320\tExpense\t400"
        )

        assert_response :success
        assert_equal [ "Cogito" ], assigns(:import).area_creates.map { |a| a[:name] }
        # :not(.mt-2) skips the "Columns read from your sheet" table.
        assert_select "div.overflow-x-auto:not(.mt-2) table tbody tr", 1 do
          assert_select "td:first-child", text: /\ACogito\b/
          assert_select "td:first-child span.text-amber-700", text: "(new)"
        end
      end

      test "preview marks every row landing in a new area as new, however its cell is cased" do
        sign_in @user

        post :preview, params: preview_params(
          "Area\tBudget\tNominal code\tType\tAmount\n" \
          "Cogito\tSet\t432320\tExpense\t500\n" \
          "cogito\tProps\t432330\tExpense\t600"
        )

        assert_select "div.overflow-x-auto:not(.mt-2) td:first-child span.text-amber-700",
                      text: "(new)", count: 2
      end

      # Two lines of one name would render alike without these labels.
      test "preview states the line each row matched, and what the loose reading passed over" do
        cogito = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                            financial_year: @year)
        create_reimbursements_budget(name: "Marketing", area: cogito, initial_budget: 400,
                                     financial_year: @year, cost_centre: @cost_centre)
        create_reimbursements_budget(name: "Marketing", initial_budget: 400,
                                     financial_year: @year, cost_centre: @cost_centre)
        sign_in @user

        post :preview, params: preview_params(tsv("Cogito: Marketing\t432320\tExpense\t500\t\t",
                                                  "Marketing\t432320\tExpense\t900\t\t"))

        assert_equal 2, assigns(:import).entries_in(:revise).size
        assert_select "div.overflow-x-auto:not(.mt-2) table tbody tr", 2
        # The row with a blank Area cell that landed on Cogito's line says so.
        assert_select "td span.text-gray-600", text: "matched: Cogito"
        # And the row the loose reading decided names the line it passed over.
        assert_select "td div.text-amber-700",
                      text: /Matched "Marketing" in no area\. "Marketing" in Cogito is named the same/
      end

      test "apply creates the area named on the sheet and attaches the budget to it" do
        sign_in @user

        assert_difference -> { ::Reimbursements::Area.count }, 1 do
          post :apply, params: preview_params(
            "Area\tArea total\tBudget name\tNominal code\tType\tBudget amount\n" \
            "Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400"
          )
        end

        assert_response :success
        area = ::Reimbursements::Area.find_by(name: "Cogito")
        assert_equal @year, area.financial_year
        assert_equal @cost_centre, area.cost_centre
        assert_equal BigDecimal("1200"), area.initial_budget
        # Stored bare: Budget#display_name puts the prefix back.
        assert_equal area.id, ::Reimbursements::Budget.find_by(name: "Marketing").area_id
      end

      # The first import of a year is all creates, so a "matched:" label there
      # would be on every row.
      test "the first import of a year states where each line lands and claims no match" do
        sign_in @user

        post :preview, params: preview_params(
          "Area\tBudget\tNominal code\tType\tAmount\n" \
          "Cogito\tSet\t432320\tExpense\t500\n" \
          "\tCogito: Marketing\t432330\tExpense\t600"
        )

        assert_equal 2, assigns(:import).entries_in(:create).size
        assert_select "div.overflow-x-auto:not(.mt-2) table tbody tr", 2 do
          assert_select "td:first-child", text: /Cogito/
        end
        assert_select "td:first-child span.text-gray-600", text: "(from its name)"
        assert_no_match(/matched:/, response.body)
      end

      # The create and the absence sit in two panels; this links them.
      test "the absent panel names a line this sheet re-creates under its own prefix" do
        area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                          financial_year: @year)
        create_reimbursements_budget(name: "Cogito: Marketing", initial_budget: 400,
                                     financial_year: @year, cost_centre: @cost_centre)
        sign_in @user

        post :preview, params: preview_params(
          "Area\tBudget\tNominal code\tType\tAmount\n" \
          "Cogito\tMarketing\t432320\tExpense\t400"
        )

        assert_equal [ area.id ], assigns(:import).creates.map { |create| create[:area_id].to_i }
        assert_match(/this sheet creates the same line inside that area/, response.body)
      end

      # A half-filled Area column, then the same lines fully converted, must
      # not end as two lines.
      test "a half-filled Area column converges with the sheet that fills it in" do
        sign_in @user

        post :apply, params: preview_params(
          "Area\tBudget\tNominal code\tType\tAmount\n" \
          "Cogito\tSet\t432320\tExpense\t500\n" \
          "\tCogito: Marketing\t432330\tExpense\t600"
        )

        area = ::Reimbursements::Area.find_by(name: "Cogito")
        assert_equal area.id, ::Reimbursements::Budget.find_by(name: "Marketing")&.area_id
        assert_nil ::Reimbursements::Budget.find_by(name: "Cogito: Marketing")

        post :preview, params: preview_params(
          "Area\tBudget\tNominal code\tType\tAmount\n" \
          "Cogito\tSet\t432320\tExpense\t500\n" \
          "Cogito\tMarketing\t432330\tExpense\t700"
        )

        assert_empty assigns(:import).entries_in(:create), "both lines already exist"
        assert_empty assigns(:import).absent_budgets
        assert_equal 1, assigns(:import).entries_in(:revise).size
      end

      test "the preview states the agreed total each new area is about to be given" do
        sign_in @user

        post :preview, params: preview_params(
          "Area\tArea total\tBudget name\tNominal code\tType\tBudget amount\n" \
          "Cogito\t1200\tCogito: Marketing\t432320\tExpense\t400"
        )

        assert_response :success
        assert_includes response.body, "Agreed totals to be set"
        assert_includes response.body, "£1,200.00"
      end

      # --- Re-homing a line the sheet disagrees with ---------------------------

      AREA_HEADERS = "Area\tBudget name\tNominal code\tType\tBudget amount".freeze

      # One matched line, currently in +area+ (nil for none), on a sheet that
      # names "Cogito".
      def marketing_in(area)
        create_reimbursements_budget(name: "Cogito: Marketing", area: area, initial_budget: 400,
                                     cost_centre: @cost_centre, financial_year: @year)
      end

      def cogito_sheet = "#{AREA_HEADERS}\nCogito\tCogito: Marketing\t432320\tExpense\t400"

      test "preview reports a re-home as a ticked checkbox keyed by budget id" do
        improverts = create_reimbursements_area(name: "Improverts", cost_centre: @cost_centre,
                                                financial_year: @year)
        create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre, financial_year: @year)
        budget = marketing_in(improverts)
        sign_in @user

        post :preview, params: preview_params(cogito_sheet)

        assert_response :success
        assert_select "input[type=checkbox][name='re_home_budget_ids[]']" \
                      "[value=?][checked=checked]", budget.record_id
        assert_select "label[for=?]", "re-home-#{budget.record_id}", text: /Improverts.+Cogito/m
      end

      test "apply ignores a re-home key that matches no line in this sheet" do
        improverts = create_reimbursements_area(name: "Improverts", cost_centre: @cost_centre,
                                                financial_year: @year)
        create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre, financial_year: @year)
        budget = marketing_in(improverts)
        sign_in @user

        post :apply, params: preview_params(cogito_sheet, re_home_budget_ids: [ "999999" ])

        assert_equal improverts.id, budget.reload.area_id
      end

      # Every line already exists, so only the re-home attaches them to the area.
      test "a re-import that gains an Area column attaches the existing lines to the new area" do
        budget = marketing_in(nil)
        sign_in @user

        assert_difference -> { ::Reimbursements::Area.count }, 1 do
          post :apply, params: preview_params(cogito_sheet,
                                              re_home_budget_ids: [ "", budget.record_id ])
        end

        assert_response :success
        area = ::Reimbursements::Area.find_by(name: "Cogito")
        assert_equal area.id, budget.reload.area_id
        assert_equal 1, assigns(:result).re_homed
      end

      # Without the moved lines in the count the button would read "Nothing to
      # import", disabled.
      test "preview offers to import a sheet whose only change is the area" do
        marketing_in(nil)
        sign_in @user

        post :preview, params: preview_params(cogito_sheet)

        assert_empty assigns(:import).entries_in(:create)
        assert_empty assigns(:import).revisions
        assert_select "input[type=submit][value=?]", "Import 1 new area and 1 moved line" do
          assert_select "[disabled]", false
        end
      end

      # The claim the budget-id keying exists to make; the unticked line is left
      # exactly where it was.
      test "a tick follows its budget when the sheet's rows are reordered" do
        improverts = create_reimbursements_area(name: "Improverts", cost_centre: @cost_centre,
                                                financial_year: @year)
        cogito = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                            financial_year: @year)
        marketing = marketing_in(improverts)
        set = create_reimbursements_budget(name: "Cogito: Set", area: improverts,
                                           initial_budget: 500, cost_centre: @cost_centre,
                                           financial_year: @year)
        sign_in @user

        # The opposite order to the sheet the preview rendered its ticks from.
        post :apply, params: preview_params(
          "#{AREA_HEADERS}\n" \
          "Cogito\tCogito: Set\t432320\tExpense\t500\n" \
          "Cogito\tCogito: Marketing\t432320\tExpense\t400",
          re_home_budget_ids: [ "", marketing.record_id ]
        )

        assert_equal cogito.id, marketing.reload.area_id
        assert_equal improverts.id, set.reload.area_id
      end

      test "unticking every re-home creates no area at all" do
        budget = marketing_in(nil)
        sign_in @user

        assert_no_difference -> { ::Reimbursements::Area.count } do
          post :apply, params: preview_params(cogito_sheet, re_home_budget_ids: [ "" ])
        end

        assert_equal 0, assigns(:result).areas_created
        assert_equal 0, assigns(:result).re_homed
        assert_nil budget.reload.area_id
      end

      test "preview warns that a re-home into an ownerless area drops the sign-off gate" do
        marketing_in(nil)
        sign_in @user

        post :preview, params: preview_params(cogito_sheet)

        assert_select "p.text-warning",
                      text: /Cogito names nobody, so claims on this line skip budget-owner sign-off entirely/
      end

      test "preview does not warn when the area the sheet names has owners" do
        area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                          financial_year: @year)
        area.sync_owner_ids!([ create_reimbursements_person(name: "Alice",
                                                            email: "alice@example.com").id ])
        marketing_in(nil)
        sign_in @user

        post :preview, params: preview_params(cogito_sheet)

        assert_select "p.text-warning", false
      end

      # --- The owner column names the AREA -------------------------------------

      OWNER_HEADERS = "#{AREA_HEADERS}\tOwner emails".freeze

      def cogito_owner_sheet(email) = "#{OWNER_HEADERS}\nCogito\tCogito: Marketing\t432320\tExpense\t400\t#{email}"

      # Three qualifications in one sheet: in scope (bare), new, and another
      # year's area reached through a blank Area cell.
      test "preview names who will sign off for each area, qualified and marking the additions" do
        area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                          financial_year: @year)
        area.sync_owner_ids!([ create_reimbursements_person(name: "Bob", email: "bob@example.com").id ])
        create_reimbursements_person(name: "Alice", email: "alice@example.com")
        marketing_in(area)
        stale = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                           financial_year: FY.create!(label: "Fringe 2026"))
        create_reimbursements_budget(name: "Cogito: Set", area: stale, initial_budget: 500,
                                     cost_centre: @cost_centre, financial_year: @year)
        sign_in @user

        post :preview, params: preview_params(
          "#{cogito_owner_sheet('alice@example.com')}\n" \
          "\tCogito: Set\t432320\tExpense\t500\tbob@example.com\n" \
          "Improverts\tImproverts: Props\t432320\tExpense\t150\talice@example.com"
        )

        assert_select "li" do |items|
          lines = items.map { |item| item.text.squish }
          assert_includes lines, "Cogito: Bob, Alice (added)"
          assert_includes lines, "Cogito (Fringe 2026): Bob (added)"
          assert_includes lines, "Improverts (new): Alice (added)"
        end
      end

      test "the owner panel says unticking a move does not hold the owner back" do
        create_reimbursements_person(name: "Alice", email: "alice@example.com")
        marketing_in(nil)
        create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre, financial_year: @year)
        sign_in @user

        post :preview, params: preview_params(cogito_owner_sheet("alice@example.com"))

        assert_select "p" do |paragraphs|
          assert paragraphs.any? { |p|
            p.text.squish.include?("Unticking a move above does not withhold the owner, " \
                                   "and the area the sheet named still gains them")
          }, "the panel must say the owner grant and the re-home tick are decoupled"
        end
      end

      test "apply gives the area the sheet's owner and leaves the line's own rows empty" do
        area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                          financial_year: @year)
        alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
        budget = marketing_in(area)
        sign_in @user

        post :apply, params: preview_params(cogito_owner_sheet("alice@example.com"))

        assert_equal [ alice.record_id ], area.reload.owner_ids
        assert_empty budget.reload.own_owners
        assert_equal 1, assigns(:result).area_owners_synced
      end

      # --- The "not in this sheet" panel --------------------------------------

      test "the absent-budget panel names the show each missing line belongs to" do
        cogito = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                            financial_year: @year)
        improverts = create_reimbursements_area(name: "Improverts", cost_centre: @cost_centre,
                                                financial_year: @year)
        [ cogito, improverts ].each do |area|
          %w[Marketing Other].each do |line|
            create_reimbursements_budget(name: line, nominal_code: "432320", area: area,
                                         initial_budget: 400, cost_centre: @cost_centre,
                                         financial_year: @year)
          end
        end
        sign_in @user

        # The sheet covers Cogito only, so both of Improverts' lines are absent.
        post :preview, params: preview_params(
          "#{AREA_HEADERS}\nCogito\tMarketing\t432320\tExpense\t400\n" \
          "Cogito\tOther\t432320\tExpense\t400"
        )

        assert_response :success
        panel = css_select("p.text-gray-600").map { |node| node.text.squish }
                                             .find { |text| text.include?("never deletes a budget") }
        assert_equal "Nothing will happen to them. Importing never deletes a budget, because its " \
                     "claims and history hang off it. Improverts: Marketing and Improverts: Other.",
                     panel
      end

      # --- A revised area total ---------------------------------------------

      TOTAL_HEADERS = "Area\tArea total\tBudget name\tNominal code\tType\tBudget amount".freeze

      # The line's figure moves too (stored 400), so the label carries both.
      def cogito_total_sheet(total)
        "#{TOTAL_HEADERS}\nCogito\t#{total}\tCogito: Marketing\t432320\tExpense\t450"
      end

      test "preview reports a revised area total with the figure it replaces" do
        area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                          financial_year: @year, initial_budget: 1000)
        marketing_in(area)
        sign_in @user

        post :preview, params: preview_params(cogito_total_sheet(1200))

        assert_response :success
        assert_select "h3", text: "Changed area totals (1)"
        assert_select "input[type=submit][value=?]",
                      "Import 1 changed figure and 1 revised area total"
      end

      test "apply logs the revised area total as a forecast and keeps the agreed figure" do
        area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                          financial_year: @year, initial_budget: 1000)
        marketing_in(area)
        sign_in @user

        post :apply, params: preview_params(cogito_total_sheet(1200))

        area.reload
        assert_equal BigDecimal("1000"), area.initial_budget
        assert_equal BigDecimal("1200"), area.projected_amount
        assert_equal 1, assigns(:result).area_revised
        assert_select "li", text: /1 area total.*revised/m
      end

      # Otherwise it would read "Cogito → Cogito".
      test "preview qualifies a re-home whose from and to areas share a name" do
        stale = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre,
                                           financial_year: FY.create!(label: "Fringe 2026"))
        budget = marketing_in(stale)
        sign_in @user

        post :preview, params: preview_params(cogito_sheet)

        assert_select "label[for=?]", "re-home-#{budget.record_id}" do |labels|
          assert_equal "Cogito: Marketing · Cogito (Fringe 2026) → Cogito (new)",
                       labels.sole.text.squish
        end
      end

      # --- Step 3: apply -----------------------------------------------------

      # The destination travels through the preview, so apply cannot land in a
      # different (year, cost centre) pair than the one that was shown.
      test "apply creates the year's budgets" do
        FY.create!(label: "Fringe 2026", active: true)
        sign_in @user

        assert_difference -> { ::Reimbursements::Budget.count }, 2 do
          post :apply, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t",
                                                  "Ticket income\t1000\tIncome\t8000\t\t"))
        end

        assert_response :success
        props = ::Reimbursements::Budget.find_by(name: "Props")
        assert_equal @year, props.financial_year
        assert_equal @cost_centre, props.cost_centre
        assert_equal BigDecimal("1200"), props.initial_budget
        assert_equal "Income", ::Reimbursements::Budget.find_by(name: "Ticket income").budget_type
      end

      test "apply logs a revision as a forecast under one budget update" do
        existing = create_reimbursements_budget(name: "Props", initial_budget: 1000)
        existing.update!(financial_year: @year)
        sign_in @user

        assert_difference -> { ::Reimbursements::BudgetUpdate.count }, 1 do
          post :apply, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"))
        end

        existing.reload
        assert_equal BigDecimal("1000"), existing.initial_budget
        assert_equal BigDecimal("1200"), existing.current_forecast
      end

      test "apply writes nothing when a row is unreadable, and shows the preview again" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          post :apply, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t",
                                                  "Venue\t4100\tExpense\tabout a grand\t\t"))
        end

        assert_response :unprocessable_entity
        assert_match(/about a grand/, response.body)
      end

      test "apply accepts a blank cost centre while only one is configured" do
        sign_in @user

        assert_difference -> { ::Reimbursements::Budget.count }, 1 do
          post :apply, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"), cost_centre_id: "")
        end
      end

      test "apply refuses without a cost centre once there are two to choose from" do
        create_second_reimbursements_cost_centre
        sign_in @user

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          post :apply, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"), cost_centre_id: "")
        end

        assert_response :unprocessable_entity
        assert_includes response.body, "Choose which cost centre"
      end

      test "preview refuses without a cost centre and keeps the paste" do
        create_second_reimbursements_cost_centre
        sign_in @user

        post :preview, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"),
                                              cost_centre_id: "")

        assert_response :unprocessable_entity
        assert_includes response.body, "Choose which cost centre"
        # Step 1 again, with what was pasted still in the box.
        assert_includes response.body, "Props"
      end

      test "the cost-centre select offers a prompt rather than preselecting the first" do
        create_second_reimbursements_cost_centre
        sign_in @user

        get :show

        assert_response :success
        assert_includes response.body, "Choose a cost centre…"
        assert_select "select#cost_centre_id option[selected]", 0
      end

      test "a centre named by the entry point still arrives selected" do
        second = create_second_reimbursements_cost_centre
        sign_in @user

        get :show, params: { cost_centre_id: second.id }

        assert_response :success
        assert_select "select#cost_centre_id option[selected][value=?]", second.id.to_s
      end

      test "the preview names the cost centre it is about to import into" do
        second = create_second_reimbursements_cost_centre
        sign_in @user

        post :preview, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"),
                                              cost_centre_id: second.id)

        assert_response :success
        assert_includes response.body, second.name
      end

      test "applying the same sheet twice creates nothing the second time" do
        sign_in @user
        post :apply, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"))

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          post :apply, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"))
        end
      end

      test "an uploaded xlsx survives preview into apply" do
        sign_in @user
        file = xlsx_upload([ HEADERS.split("\t"), [ "", "", "Props", "4000", "Expense", "1200", "", "" ] ],
                           sheet: "Budget")

        post :preview, params: { year: @year.key, cost_centre_id: @cost_centre.id,
                                 file: file }

        assert_response :success
        # The preview carries the upload on as TSV, so apply needs no file.
        carried = assigns(:import).to_tsv
        assert_difference -> { ::Reimbursements::Budget.count }, 1 do
          post :apply, params: preview_params(carried)
        end
        assert_equal BigDecimal("1200"), ::Reimbursements::Budget.find_by(name: "Props").initial_budget
      end

      # Without the marker, apply would unescape a typed "Costume\next week".
      test "the preview marks the sheet it carries as canonical" do
        sign_in @user

        post :preview, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"))

        assert_select "input[name=?][value=?]", "canonical", "1"
      end

      test "apply leaves a backslash the operator typed alone" do
        sign_in @user

        post :apply, params: preview_params(tsv("Costume\\next week\t4000\tExpense\t1200\t\t"))

        assert_response :success
        assert_equal "Costume\\next week", ::Reimbursements::Budget.sole.name
      end

      test "apply unescapes the sheet the preview carried" do
        sign_in @user

        post :apply, params: preview_params(tsv("Costume\\nrepairs\t4000\tExpense\t1200\t\t"),
                                            canonical: "1")

        assert_response :success
        assert_equal "Costume\nrepairs", ::Reimbursements::Budget.sole.name
      end

      test "the template download names the columns the importer reads" do
        sign_in @user

        get :template, params: { format: :csv }

        assert_response :success
        assert_match(/filename="budget-import-template\.csv"/, response.headers["Content-Disposition"])
        header, hints = CSV.parse(response.body)
        assert_equal ::Reimbursements::BudgetImport::TSV_HEADERS, header
        assert_equal "The show's agreed total, the same on every row of that area",
                     hints[header.index("Area total")]
      end

      test "the import page explains the two amount columns" do
        sign_in @user

        get :show

        assert_response :success
        assert_match(/Area total.*agreed total.*every row/m, response.body)
        assert_match(/Budget amount.*that line/m, response.body)
      end

      test "show preselects the operator's home cost centre when no link named one" do
        termtime = create_second_reimbursements_cost_centre
        users(:member).update!(reimbursements_cost_centre: termtime)
        sign_in users(:member)

        get :show

        assert_select "select#cost_centre_id option[selected][value=?]", termtime.id.to_s
      end
    end
  end
end
