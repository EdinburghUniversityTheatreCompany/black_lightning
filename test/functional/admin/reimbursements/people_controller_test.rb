require "test_helper"

module Admin
  module Reimbursements
  class PeopleControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    setup do
      @user = users(:member)
      grant_finance_permission(@user)

      @valid_person = create_reimbursements_person(name: "Valid Vic", email: "vic@example.com",
                                                   sort_code: "08-99-99", account_number: "66374958")
      @invalid_person = create_reimbursements_person(name: "Invalid Ivy", email: "ivy@example.com",
                                                     sort_code: "08-99-99", account_number: "66374959")
      @outside_person = create_reimbursements_person(name: "Outside Ophelia", email: "ophelia@example.com",
                                                     sort_code: "99-99-99", account_number: "12345678")
      @missing_person = create_reimbursements_person(name: "Missing Mo", email: "mo@example.com")

      PeopleController.checker_builder = lambda {
        FakeModulusChecker.new("66374958" => ::Reimbursements::ModulusCheck::VALID,
                               "66374959" => ::Reimbursements::ModulusCheck::INVALID)
      }
    end

    teardown do
      PeopleController.checker_builder = -> { ::Reimbursements::ModulusCheck.default_checker }
    end

    test "requires sign-in" do
      get :index
      assert_redirected_to new_user_session_path
    end

    test "denies members without the finance permission" do
      sign_in users(:committee)
      get :index
      assert_response :forbidden
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

    # Every write comes back with that person's row open and scrolled to.
    def assert_redirected_to_person(person)
      assert_redirected_to admin_reimbursements_people_path(person: person.record_id,
                                                            anchor: "person-#{person.record_id}")
    end

    test "index filters by name or email" do
      sign_in @user

      { "ivy" => [ "Invalid Ivy" ], "ophelia@example" => [ "Outside Ophelia" ] }.each do |q, expected|
        get :index, params: { q: q }

        assert_equal expected, assigns(:people).map(&:name)
      end
    end

    test "index lists people alphabetically" do
      # Accented: the column collates utf8mb4_unicode_ci (folds accents) but Ruby sorts
      # bytewise, so an in-memory sort would put Ábel after Valid Vic.
      create_reimbursements_person(name: "Ábel Aardvark", email: "abel@example.com")
      sign_in @user

      get :index

      names = assigns(:people).map(&:name)
      assert_equal 5, names.size
      assert_equal "Ábel Aardvark", names.first
      assert_equal names, names.sort_by { |n| n.unicode_normalize(:nfd) }
    end

    test "index links each person to their own claims" do
      create_reimbursements_expense(person: @valid_person,
                                    budget: create_reimbursements_budget(name: "Props"))
      sign_in @user

      get :index

      assert_response :success
      assert_select "a[href=?]", admin_reimbursements_expense_edits_path(person: @valid_person.record_id),
                    text: "1 claim"
      assert_match(/No claims/, response.body)
    end

    test "index opens and anchors the row named by ?person=" do
      sign_in @user

      get :index, params: { person: @valid_person.record_id }

      assert_select "details[open]##{"person-#{@valid_person.record_id}"}"
      assert_select "details[open]##{"person-#{@missing_person.record_id}"}", false,
                    "only the named row opens"
    end

    test "the People CSV carries the on-screen filter" do
      sign_in @user

      get :index, params: { q: "ivy" }, format: :csv

      assert_response :success
      assert_includes response.body, "Invalid Ivy"
      assert_not_includes response.body, "Valid Vic"
    end

    test "saving bank details writes formatted values and an audit note" do
      sign_in @user

      patch :update, params: { id: @missing_person.record_id,
                               sort_code: "089999", account_number: "66374958" }

      assert_redirected_to_person @missing_person
      details = @missing_person.reload.payment_details
      assert_equal "08-99-99", details.sort_code
      assert_equal "66374958", details.account_number
      # Both details masked to last four, never in the clear.
      assert_includes details.notes,
                      "Bank details updated: sort code ****9999, account ****4958"
      assert_not_includes details.notes, "66374958",
                          "the audit line must not embed the full account number"
      assert_not_includes details.notes, "08-99-99",
                          "the audit line must not embed the full sort code"
      assert_not_includes details.notes, "089999",
                          "the audit line must not embed the full sort code undashed either"
      assert_includes details.notes, "by #{@user.name_or_email} (##{@user.id})"
    end

    test "the audit line is appended to existing notes, preserving them" do
      person = create_reimbursements_person(name: "Nora Notes", email: "nora@example.com",
                                            notes: "Earlier note.")
      sign_in @user

      patch :update, params: { id: person.record_id, sort_code: "089999", account_number: "66374958" }

      notes = person.reload.payment_details.notes
      assert notes.start_with?("Earlier note.\n[")
    end

    test "a differently-formatted but identical sort code isn't treated as a change" do
      # A directly edited record may store the sort code undashed; bank_details_changed?
      # must normalise both sides.
      @valid_person.payment_details.update!(sort_code: "089999")
      sign_in @user

      patch :update, params: { id: @valid_person.record_id,
                               sort_code: "08-99-99", account_number: "66374958" }

      assert_redirected_to_person @valid_person
      assert_equal "No changes to save.", flash[:notice]
      assert_equal "089999", @valid_person.reload.payment_details.sort_code,
                   "the identical-digits submission must not rewrite the record"
    end

    test "invalid bank details re-render the form without a write, preserving the typed values" do
      sign_in @user
      missing_id = @missing_person.record_id
      valid_id = @valid_person.record_id

      patch :update, params: { id: missing_id, sort_code: "08", account_number: "1" }

      assert_response :unprocessable_entity
      assert_nil @missing_person.reload.payment_details
      assert_select "details[open] input#sort_code_#{missing_id}[value=?]", "08"
      assert_select "details[open] input#account_number_#{missing_id}[value=?]", "1"
      assert_select "details[open] input#sort_code_#{valid_id}", false
      # The error is a role="alert" region wired to both fields via aria-describedby.
      assert_select "p[role=alert]#bank_details_error_#{missing_id}"
      assert_select "input#sort_code_#{missing_id}[aria-describedby=bank_details_error_#{missing_id}][aria-invalid=true]"
      assert_select "input#account_number_#{missing_id}[aria-describedby=bank_details_error_#{missing_id}][aria-invalid=true]"
    end

    test "marks Valid and Outside-spec details verified (advisory, not a hard block)" do
      sign_in @user

      [ @valid_person, @outside_person ].each do |person|
        patch :update, params: { id: person.record_id, verify: "1" }

        assert_redirected_to_person person
        assert person.reload.verified, person.name
      end
    end

    test "refuses to verify missing or modulus-invalid details" do
      sign_in @user

      { @missing_person => /no bank details/, @invalid_person => /fail the modulus check/ }.each do |person, alert|
        patch :update, params: { id: person.record_id, verify: "1" }

        assert_redirected_to_person person
        assert_match alert, flash[:alert]
        assert_not person.reload.verified, person.name
      end
    end

    test "editing bank details resets verified to false" do
      verified_person = create_reimbursements_person(name: "Vera Verified", email: "vera@example.com",
                                                     sort_code: "08-99-99", account_number: "66374958",
                                                     verified: true)
      sign_in @user

      patch :update, params: { id: verified_person.record_id,
                               sort_code: "20-20-20", account_number: "50502366" }

      assert_redirected_to_person verified_person
      assert_not verified_person.reload.verified?,
                 "a bank-detail correction must not leave a stale Verified badge standing"
    end

    test "updating an unknown person 404s" do
      sign_in @user

      patch :update, params: { id: "999999", verify: "1" }

      assert_response :not_found
    end

    test "index CSV lists every person with bank details masked" do
      @valid_person.payment_details.update!(verified: true)
      sign_in @user

      get :index, format: :csv

      assert_csv_download("people")
      assert_equal [
        [ "Name", "Email", "Sort code", "Account number", "Modulus check", "Verified" ],
        [ "Invalid Ivy", "ivy@example.com", "****9999", "****4959", "Invalid", "No" ],
        [ "Missing Mo", "mo@example.com", nil, nil, "Missing", "No" ],
        [ "Outside Ophelia", "ophelia@example.com", "****9999", "****5678", "Outside spec", "No" ],
        [ "Valid Vic", "vic@example.com", "****9999", "****4958", "Valid", "Yes" ]
      ], CSV.parse(response.body)
    end

    test "index links to the register-a-person form and the CSV download" do
      sign_in @user

      get :index

      assert_select "a[href=?]", new_admin_reimbursements_person_path
      assert_select "a[href=?]", "/admin/reimbursements/people?format=csv", text: "Download CSV"
    end

    test "new renders the user picker" do
      sign_in @user

      get :new

      assert_response :success
      assert_select "select#user_id"
    end

    test "create registers the chosen user as a person" do
      sign_in @user
      chosen = users(:user)

      assert_difference -> { ::Reimbursements::Person.count }, 1 do
        post :create, params: { user_id: chosen.id }
      end

      assert_redirected_to admin_reimbursements_people_path
      person = ::Reimbursements::Person.order(:id).last
      assert_equal chosen.full_name, person.name
      assert_equal chosen.email, person.email
      assert_equal person.id, chosen.reload.reimbursements_person_id,
                   "the PersonLink must be remembered for next time"
      assert_nil person.payment_details
    end

    test "create matches an unlinked person on email instead of duplicating them" do
      sign_in @user
      chosen = users(:user)
      existing = create_reimbursements_person(name: "Cyclops Cat", email: chosen.email)

      assert_no_difference -> { ::Reimbursements::Person.count } do
        post :create, params: { user_id: chosen.id }
      end

      assert_redirected_to admin_reimbursements_people_path
      assert_match(/already in the registry/, flash[:alert])
      assert_equal existing.id, chosen.reload.reimbursements_person_id
    end

    test "create with no or an unknown user re-renders the form and writes nothing" do
      sign_in @user

      [ "", "999999" ].each do |user_id|
        assert_no_difference -> { ::Reimbursements::Person.count } do
          post :create, params: { user_id: user_id }
        end

        assert_response :unprocessable_entity
        assert_select "select#user_id"
      end
    end
  end
  end
end
