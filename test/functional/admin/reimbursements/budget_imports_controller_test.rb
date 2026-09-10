require "test_helper"

module Admin
  module Reimbursements
    class BudgetImportsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      FY = ::Reimbursements::FinancialYear
      HEADERS = "Budget\tNominal code\tType\tAmount\tOwner emails\tNotes".freeze

      setup do
        finance = Role.create!(name: "Business Manager")
        finance.permissions << Permission.create(action: "manage", subject_class: "reimbursements_finance")
        users(:member).add_role("Business Manager")
        @user = users(:member)
        @year = FY.create!(label: "Fringe 2027")
        @cost_centre = ::Reimbursements::CostCentre.default
      end

      def tsv(*rows)
        ([ HEADERS ] + rows).join("\n")
      end

      def preview_params(text, **extra)
        { year: @year.key, pasted_text: text,
          cost_centre_id: @cost_centre.id }.merge(extra)
      end

      # --- Auth gating -------------------------------------------------------

      test "requires sign-in" do
        get :show, params: { year: @year.key }
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        sign_in users(:committee)
        get :show, params: { year: @year.key }
        assert_response :forbidden
      end

      # No longer a 404: the year is a selector param, not a path segment, so it
      # follows FinanceController's rule — never show a DIFFERENT year's money as
      # though it were the one asked for, so say so and fall back to the active
      # year. Which year is being imported into is then on screen in the select,
      # and travels explicitly through preview into apply.
      test "an unknown year falls back to the active year and says so" do
        active = FY.create!(label: "Fringe 2026", active: true)
        sign_in @user

        get :show, params: { year: "no-such-year" }

        assert_response :success
        assert_equal active, assigns(:selected_financial_year)
        assert_match(/no-such-year/, response.body)
      end

      # --- Step 1: the form --------------------------------------------------

      # --- Entering from either side ----------------------------------------
      # Financial years are orthogonal to cost centres, so the wizard needs both
      # and neither is a path segment. Each entry point prefills the side it
      # knows and the operator picks the other.

      test "show defaults to the active year when the link named none" do
        active = FY.create!(label: "Fringe 2026", active: true)
        sign_in @user

        get :show

        assert_response :success
        assert_equal active, assigns(:selected_financial_year)
      end

      test "show preselects the cost centre a settings-page link named" do
        centre = create_reimbursements_cost_centre(key: "termtime", name: "Termtime",
                                                   eusa_code: "BED")
        sign_in @user

        get :show, params: { cost_centre_id: centre.id }

        assert_response :success
        assert_equal centre, assigns(:selected_cost_centre)
      end

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

      # The destination travels through the preview, so apply cannot land in a
      # different (year, cost centre) pair than the one that was shown.
      test "apply imports into the year the preview carried, not the active one" do
        FY.create!(label: "Fringe 2026", active: true)
        sign_in @user

        post :apply, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"))

        assert_response :success
        assert_equal @year, ::Reimbursements::Budget.find_by(name: "Props").financial_year
      end

      test "show renders the paste/upload form for the year" do
        sign_in @user

        get :show, params: { year: @year.key }

        assert_response :success
        assert_equal @year, assigns(:selected_financial_year)
      end

      # Turbo Drive REJECTS a non-redirect response to a form POST and discards
      # it, so preview/apply would render a perfectly good page server-side that
      # never reaches the screen. The wizard is stateless (a redirect can't
      # carry the paste), so every step lives in one Turbo Frame instead — the
      # same fix Reconcile uses. Only a browser catches this, hence the guard.
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

      test "preview reports a line already in the year as a revision" do
        existing = create_reimbursements_budget(name: "Props", initial_budget: 1000)
        existing.update!(financial_year: @year)
        sign_in @user

        post :preview, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"))

        assert_equal 1, assigns(:import).entries_in(:revise).size
      end

      test "preview refuses an empty paste" do
        sign_in @user

        post :preview, params: preview_params("  ")

        assert_response :success
        assert_match(/paste|upload/i, response.body)
        assert_nil assigns(:import)
      end

      # Keyword matching can only ever be nearly right, so the preview states
      # what it actually read — the thing that makes a mis-mapping visible.
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

      test "preview states a new area will be created" do
        sign_in @user

        post :preview, params: preview_params(
          "Area\tBudget\tNominal code\tType\tAmount\n" \
          "Cogito\tCogito: Marketing\t432320\tExpense\t400"
        )

        assert_response :success
        assert_equal [ "Cogito" ], assigns(:import).area_creates.map { |a| a[:name] }
        assert_match(/Cogito/, response.body)
      end

      test "apply creates the area named on the sheet and attaches the budget to it" do
        sign_in @user

        assert_difference -> { ::Reimbursements::Area.count }, 1 do
          post :apply, params: preview_params(
            "Area\tBudget\tNominal code\tType\tAmount\n" \
            "Cogito\tCogito: Marketing\t432320\tExpense\t400"
          )
        end

        assert_response :success
        area = ::Reimbursements::Area.find_by(name: "Cogito")
        assert_equal @year, area.financial_year
        assert_equal @cost_centre, area.cost_centre
        assert_equal area.id, ::Reimbursements::Budget.find_by(name: "Cogito: Marketing").area_id
      end

      test "apply attaches to an existing area rather than creating a second" do
        area = create_reimbursements_area(name: "Cogito", cost_centre: @cost_centre, financial_year: @year)
        sign_in @user

        assert_no_difference -> { ::Reimbursements::Area.count } do
          post :apply, params: preview_params(
            "Area\tBudget\tNominal code\tType\tAmount\n" \
            "Cogito\tCogito: Marketing\t432320\tExpense\t400"
          )
        end

        assert_equal area.id, ::Reimbursements::Budget.find_by(name: "Cogito: Marketing").area_id
      end

      # --- Step 3: apply -----------------------------------------------------

      test "apply creates the year's budgets" do
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

      test "apply refuses without a cost centre" do
        sign_in @user

        assert_no_difference -> { ::Reimbursements::Budget.count } do
          post :apply, params: preview_params(tsv("Props\t4000\tExpense\t1200\t\t"), cost_centre_id: "")
        end

        assert_response :unprocessable_entity
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
        file = fixture_file_upload_xlsx([ HEADERS.split("\t"),
                                          [ "Props", "4000", "Expense", "1200", "", "" ] ])

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

      # The preview marks the text it carries as this class's own escaped output.
      # Without the marker apply unescapes the operator's own paste, and a name
      # typed "Costume\next week" is stored with a real newline in it.
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
        assert_match "Budget", response.body
        assert_match "Nominal code", response.body
      end

      private

      def fixture_file_upload_xlsx(rows)
        require "caxlsx"
        package = Axlsx::Package.new
        package.workbook.add_worksheet(name: "Budget") { |sheet| rows.each { |row| sheet.add_row row } }
        file = Tempfile.new([ "budget", ".xlsx" ])
        file.binmode
        file.write(package.to_stream.read)
        file.rewind
        Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
      end
    end
  end
end
