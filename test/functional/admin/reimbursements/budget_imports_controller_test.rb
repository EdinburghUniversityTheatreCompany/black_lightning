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
        { financial_year_key: @year.key, pasted_text: text,
          cost_centre_id: @cost_centre.id }.merge(extra)
      end

      # --- Auth gating -------------------------------------------------------

      test "requires sign-in" do
        get :show, params: { financial_year_key: @year.key }
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        sign_in users(:committee)
        get :show, params: { financial_year_key: @year.key }
        assert_response :forbidden
      end

      test "404s on an unknown year" do
        sign_in @user
        get :show, params: { financial_year_key: "no-such-year" }
        assert_response :not_found
      end

      # --- Step 1: the form --------------------------------------------------

      test "show renders the paste/upload form for the year" do
        sign_in @user

        get :show, params: { financial_year_key: @year.key }

        assert_response :success
        assert_equal @year, assigns(:financial_year)
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

        post :preview, params: { financial_year_key: @year.key, cost_centre_id: @cost_centre.id,
                                 file: file }

        assert_response :success
        # The preview carries the upload on as TSV, so apply needs no file.
        carried = assigns(:import).to_tsv
        assert_difference -> { ::Reimbursements::Budget.count }, 1 do
          post :apply, params: preview_params(carried)
        end
        assert_equal BigDecimal("1200"), ::Reimbursements::Budget.find_by(name: "Props").initial_budget
      end

      test "the template download names the columns the importer reads" do
        sign_in @user

        get :template, params: { financial_year_key: @year.key, format: :csv }

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
