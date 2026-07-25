require "test_helper"

module Admin
  module Reimbursements
  class PeopleControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    MC = ::Reimbursements::ModulusCheck

    # A checker whose verdict is keyed by account number, so badge-state tests
    # don't depend on the gitignored Pay.UK rule files being present.
    class FakeChecker
      def initialize(by_account = {})
        @by_account = by_account
      end

      def check(_sort_code, account_number)
        @by_account.fetch(account_number, MC::OUTSIDE_SPEC)
      end
    end

    setup do
      finance = Role.create!(name: "Business Manager")
      finance.permissions << Permission.create(action: "manage", subject_class: "reimbursements_finance")
      users(:member).add_role("Business Manager")
      @user = users(:member)

      @valid_person = create_reimbursements_person(name: "Valid Vic", email: "vic@example.com",
                                                   sort_code: "08-99-99", account_number: "66374958")
      @invalid_person = create_reimbursements_person(name: "Invalid Ivy", email: "ivy@example.com",
                                                     sort_code: "08-99-99", account_number: "66374959")
      @outside_person = create_reimbursements_person(name: "Outside Ophelia", email: "ophelia@example.com",
                                                     sort_code: "99-99-99", account_number: "12345678")
      @missing_person = create_reimbursements_person(name: "Missing Mo", email: "mo@example.com")

      @checker = FakeChecker.new(
        "66374958" => MC::VALID,
        "66374959" => MC::INVALID,
        "12345678" => MC::OUTSIDE_SPEC
      )
      PeopleController.checker_builder = -> { @checker }
    end

    teardown do
      PeopleController.checker_builder = -> { MC.default_checker }
    end

    # --- Auth gating -------------------------------------------------------

    test "requires sign-in" do
      get :index
      assert_redirected_to new_user_session_path
    end

    test "denies members without the finance permission" do
      sign_in users(:committee)
      get :index
      assert_response :forbidden
    end

    test "the producer portal permission alone does not grant finance access" do
      producer = Role.create!(name: "Producer")
      producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
      other = users(:member_with_phone_number)
      other.add_role("Producer")
      sign_in other

      get :index

      assert_response :forbidden
    end

    # --- Index -------------------------------------------------------------

    test "lists everyone in the registry" do
      sign_in @user
      get :index

      assert_response :success
      assert_equal 4, assigns(:people).size
      assert_includes response.body, "Valid Vic"
      assert_includes response.body, "Missing Mo"
    end

    test "shows a duplicate banner when a name or email clashes" do
      dup_a = create_reimbursements_person(name: "Sam Same", email: "sam@example.com")
      dup_b = create_reimbursements_person(name: "Sam Same", email: "different@example.com")
      sign_in @user

      get :index

      assert_response :success
      assert_equal [ dup_a, dup_b ].map(&:record_id).sort, assigns(:duplicates).map(&:record_id).sort
      assert_includes response.body, "Duplicate name or email detected"
    end

    test "renders a live modulus badge per bank-detail state" do
      sign_in @user
      get :index

      assert_response :success
      # Assert on the BadgeComponent colour classes, not the labels: the labels
      # (Valid/Invalid/Missing) collide with the fixture person names, so a broken
      # mapping would still leave the words in the body. The colour classes can
      # only come from the badge, so they genuinely pin the state mapping:
      # VALID -> success (green), INVALID -> danger (red), OUTSIDE_SPEC -> warning
      # (amber). None of the four fixture people are verified, so each colour
      # comes from exactly one modulus badge.
      assert_includes response.body, "bg-success/15", "VALID should map to a green badge"
      assert_includes response.body, "bg-danger/15", "INVALID should map to a red badge"
      assert_includes response.body, "bg-warning/15", "OUTSIDE_SPEC should map to an amber badge"
      assert_includes response.body, "Outside spec"
      assert_includes response.body, "Missing"
    end

    # --- Update: bank details ---------------------------------------------

    test "saving bank details writes formatted values and an audit note" do
      sign_in @user

      patch :update, params: { id: @missing_person.record_id,
                               sort_code: "089999", account_number: "66374958" }

      assert_redirected_to admin_reimbursements_people_path
      details = @missing_person.reload.payment_details
      assert_equal "08-99-99", details.sort_code
      assert_equal "66374958", details.account_number
      # The audit line masks BOTH bank details to last-4 and records the actor; it
      # must never carry either value in the clear.
      assert_includes details.notes,
                      "Bank details updated: sort code ****9999, account ****4958"
      assert_not_includes details.notes, "66374958",
                          "the audit line must not embed the full account number"
      assert_not_includes details.notes, "08-99-99",
                          "the audit line must not embed the full sort code"
      assert_not_includes details.notes, "089999",
                          "the audit line must not embed the full sort code undashed either"
    end

    test "the audit line is appended to existing notes, preserving them" do
      person = create_reimbursements_person(name: "Nora Notes", email: "nora@example.com",
                                            notes: "Earlier note.")
      sign_in @user

      patch :update, params: { id: person.record_id, sort_code: "089999", account_number: "66374958" }

      notes = person.reload.payment_details.notes
      assert notes.start_with?("Earlier note.\n[")
      assert_includes notes, "sort code ****9999, account ****4958"
    end

    # S6: the line masked the account number but wrote the full sort code, while
    # Exports::People masks both. The stricter rule wins in both places — a sort
    # code is not a secret on its own, but the audit trail sits next to the masked
    # account number on the People page, and the pair is what identifies an
    # account.
    test "the audit line masks both bank details and names the acting user" do
      sign_in @user

      patch :update, params: { id: @missing_person.record_id,
                               sort_code: "089999", account_number: "66374958" }

      notes = @missing_person.reload.payment_details.notes
      # Masked account number and sort code, never the full digits.
      assert_includes notes, "account ****4958"
      assert_includes notes, "sort code ****9999"
      assert_not_includes notes, "66374958",
                          "the full account number must not appear in the audit trail"
      assert_not_includes notes, "08-99-99",
                          "the full sort code must not appear in the audit trail"
      # Actor attribution: the signed-in operator's name + id.
      assert_includes notes, @user.name_or_email
      assert_includes notes, "(##{@user.id})"
    end

    test "unchanged bank details are not rewritten" do
      sign_in @user
      before = @valid_person.payment_details.updated_at

      patch :update, params: { id: @valid_person.record_id,
                               sort_code: "08-99-99", account_number: "66374958" }

      assert_redirected_to admin_reimbursements_people_path
      assert_equal "No changes to save.", flash[:notice]
      assert_equal before, @valid_person.reload.payment_details.updated_at
    end

    test "a differently-formatted but identical sort code isn't treated as a change" do
      # A record edited directly could store the sort code without dashes
      # ("089999") — the same digits as the canonical "08-99-99" this form
      # always submits. bank_details_changed? must normalise both sides the
      # same way the account-number check right beside it already does.
      @valid_person.payment_details.update!(sort_code: "089999")
      sign_in @user

      patch :update, params: { id: @valid_person.record_id,
                               sort_code: "08-99-99", account_number: "66374958" }

      assert_redirected_to admin_reimbursements_people_path
      assert_equal "No changes to save.", flash[:notice]
      assert_equal "089999", @valid_person.reload.payment_details.sort_code,
                   "the identical-digits submission must not rewrite the record"
    end

    test "invalid bank details re-render the form without a write, preserving the typed values" do
      sign_in @user
      missing_id = @missing_person.record_id
      valid_id = @valid_person.record_id

      patch :update, params: { id: missing_id, sort_code: "08", account_number: "1" }

      # Re-render (not redirect) so the operator's typed values and the open
      # edit section survive the validation failure.
      assert_response :unprocessable_entity
      assert_nil @missing_person.reload.payment_details
      assert_match(/Sort code/, response.body)
      # This person's edit section stays expanded with the typed values intact.
      assert_select "details[open] input#sort_code_#{missing_id}[value=?]", "08"
      assert_select "details[open] input#account_number_#{missing_id}[value=?]", "1"
      # Other people's sections stay collapsed.
      assert_select "details[open] input#sort_code_#{valid_id}", false
      # The error is a role="alert" region, wired to both fields via
      # aria-describedby, and both fields are flagged aria-invalid.
      assert_select "p[role=alert]#bank_details_error_#{missing_id}"
      assert_select "input#sort_code_#{missing_id}[aria-describedby=bank_details_error_#{missing_id}][aria-invalid=true]"
      assert_select "input#account_number_#{missing_id}[aria-describedby=bank_details_error_#{missing_id}][aria-invalid=true]"
    end

    # --- Update: mark verified --------------------------------------------

    test "marking verified writes the verified flag" do
      sign_in @user

      patch :update, params: { id: @valid_person.record_id, verify: "1" }

      assert_redirected_to admin_reimbursements_people_path
      assert @valid_person.reload.verified?
    end

    test "cannot verify a person without bank details" do
      sign_in @user

      patch :update, params: { id: @missing_person.record_id, verify: "1" }

      assert_redirected_to admin_reimbursements_people_path
      assert_match(/no bank details/, flash[:alert])
      assert_not @missing_person.reload.verified?
    end

    test "cannot verify a person whose bank details fail the modulus check" do
      sign_in @user

      patch :update, params: { id: @invalid_person.record_id, verify: "1" }

      assert_redirected_to admin_reimbursements_people_path
      assert_match(/fail the modulus check/, flash[:alert])
      assert_not @invalid_person.reload.verified?
    end

    test "can verify a person whose bank details are outside spec (advisory, not a hard block)" do
      sign_in @user

      patch :update, params: { id: @outside_person.record_id, verify: "1" }

      assert_redirected_to admin_reimbursements_people_path
      assert @outside_person.reload.verified?
    end

    test "editing bank details resets verified to false" do
      verified_person = create_reimbursements_person(name: "Vera Verified", email: "vera@example.com",
                                                     sort_code: "08-99-99", account_number: "66374958",
                                                     verified: true)
      sign_in @user

      patch :update, params: { id: verified_person.record_id,
                               sort_code: "20-20-20", account_number: "50502366" }

      assert_redirected_to admin_reimbursements_people_path
      assert_not verified_person.reload.verified?,
                 "a bank-detail correction must not leave a stale Verified badge standing"
    end

    test "updating an unknown person 404s" do
      sign_in @user

      patch :update, params: { id: "999999", verify: "1" }

      assert_response :not_found
    end

    # --- CSV export ----------------------------------------------------------

    test "index CSV export answers a text/csv download named for today" do
      sign_in @user

      get :index, format: :csv

      assert_csv_download("people")
    end

    test "index CSV export has a header row and one row per person" do
      sign_in @user

      get :index, format: :csv

      rows = CSV.parse(response.body)
      assert_equal [ "Name", "Email", "Sort code", "Account number",
                     "Modulus check", "Verified" ], rows.first
      assert_equal 5, rows.size, "header + four people"

      vic = rows.find { |r| r[0] == "Valid Vic" }
      assert_equal "vic@example.com", vic[1]
      assert_equal "Valid", vic[4]
      assert_equal "No", vic[5]
    end

    test "index CSV export MASKS both bank details to their last four digits" do
      sign_in @user

      get :index, format: :csv

      vic = CSV.parse(response.body).find { |r| r[0] == "Valid Vic" }
      assert_equal "****9999", vic[2], "the sort code must be masked"
      assert_equal "****4958", vic[3], "the account number must be masked"
      # The export leaves the portal, so no complete bank detail may travel in it.
      assert_not_includes response.body, "66374958"
      assert_not_includes response.body, "08-99-99"
      assert_not_includes response.body, "089999"
    end

    test "index CSV export leaves a person with no bank details blank, not masked" do
      sign_in @user

      get :index, format: :csv

      mo = CSV.parse(response.body).find { |r| r[0] == "Missing Mo" }
      assert_nil mo[2]
      assert_nil mo[3]
      assert_equal "Missing", mo[4]
    end

    test "index CSV export reports each modulus verdict" do
      sign_in @user

      get :index, format: :csv

      rows = CSV.parse(response.body)
      assert_equal "Invalid", rows.find { |r| r[0] == "Invalid Ivy" }[4]
      assert_equal "Outside spec", rows.find { |r| r[0] == "Outside Ophelia" }[4]
    end

    test "index CSV export reports a verified payee as verified" do
      sign_in @user
      @valid_person.payment_details.update!(verified: true)

      get :index, format: :csv

      assert_equal "Yes", CSV.parse(response.body).find { |r| r[0] == "Valid Vic" }[5]
    end

    test "index offers a Download CSV link" do
      sign_in @user

      get :index

      assert_includes response.body, "Download CSV"
      assert_includes response.body, "/admin/reimbursements/people?format=csv"
    end
  end
  end
end
