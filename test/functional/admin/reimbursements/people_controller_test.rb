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

      @valid_person = airtable_person_record(id: "recValid", name: "Valid Vic",
                                             email: "vic@example.com", sort_code: "08-99-99",
                                             account_number: "66374958")
      @invalid_person = airtable_person_record(id: "recInvalid", name: "Invalid Ivy",
                                               email: "ivy@example.com", sort_code: "08-99-99",
                                               account_number: "66374959")
      @outside_person = airtable_person_record(id: "recOutside", name: "Outside Ophelia",
                                               email: "ophelia@example.com", sort_code: "99-99-99",
                                               account_number: "12345678")
      @missing_person = airtable_person_record(id: "recMissing", name: "Missing Mo",
                                               email: "mo@example.com")

      @checker = FakeChecker.new(
        "66374958" => MC::VALID,
        "66374959" => MC::INVALID,
        "12345678" => MC::OUTSIDE_SPEC
      )

      rebuild_store(people: [ @valid_person, @invalid_person, @outside_person, @missing_person ])
      PeopleController.checker_builder = -> { @checker }
    end

    teardown do
      BaseController.store_builder = -> { ::Reimbursements::Store.new }
      PeopleController.checker_builder = -> { MC.default_checker }
    end

    def rebuild_store(people:)
      @store, @client = build_fake_store(people: people)
      BaseController.store_builder = -> { @store }
    end

    def person_record_with_notes(id:, notes:, **attrs)
      record = airtable_person_record(id: id, **attrs)
      record["fields"][FIELD_IDS[:people][:notes]] = notes
      record
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
      dup_a = airtable_person_record(id: "recDupA", name: "Sam Same", email: "sam@example.com")
      dup_b = airtable_person_record(id: "recDupB", name: "Sam Same", email: "different@example.com")
      rebuild_store(people: [ dup_a, dup_b, @missing_person ])
      sign_in @user

      get :index

      assert_response :success
      assert_equal %w[recDupA recDupB], assigns(:duplicates).map(&:record_id)
      assert_includes response.body, "Duplicate name or email detected"
    end

    test "renders a live modulus badge per bank-detail state" do
      sign_in @user
      get :index

      assert_response :success
      assert_includes response.body, "Valid"
      assert_includes response.body, "Invalid"
      assert_includes response.body, "Outside spec"
      assert_includes response.body, "Missing"
    end

    # --- Update: bank details ---------------------------------------------

    test "saving bank details writes formatted values and an audit note" do
      rebuild_store(people: [ @missing_person ])
      sign_in @user

      patch :update, params: { id: "recMissing", sort_code: "089999", account_number: "66374958" }

      assert_redirected_to admin_reimbursements_people_path
      table, record_id, fields = @client.updated.sole
      assert_equal :people, table
      assert_equal "recMissing", record_id
      assert_equal "08-99-99", fields[FIELD_IDS[:people][:sort_code]]
      assert_equal "66374958", fields[FIELD_IDS[:people][:account_number]]
      assert_includes fields[FIELD_IDS[:people][:notes]],
                      "Bank details updated: sort code 08-99-99, account 66374958"
    end

    test "the audit line is appended to existing notes, preserving them" do
      person = person_record_with_notes(id: "recNotes", notes: "Earlier note.",
                                        name: "Nora Notes", email: "nora@example.com")
      rebuild_store(people: [ person ])
      sign_in @user

      patch :update, params: { id: "recNotes", sort_code: "089999", account_number: "66374958" }

      notes = @client.updated.sole.last[FIELD_IDS[:people][:notes]]
      assert notes.start_with?("Earlier note.\n[")
      assert_includes notes, "sort code 08-99-99, account 66374958"
    end

    test "unchanged bank details are not rewritten" do
      sign_in @user

      patch :update, params: { id: "recValid", sort_code: "08-99-99", account_number: "66374958" }

      assert_redirected_to admin_reimbursements_people_path
      assert_equal "No changes to save.", flash[:notice]
      assert_empty @client.updated
    end

    test "invalid bank details are rejected without a write" do
      sign_in @user

      patch :update, params: { id: "recMissing", sort_code: "08", account_number: "1" }

      assert_redirected_to admin_reimbursements_people_path
      assert_match(/Sort code/, flash[:alert])
      assert_empty @client.updated
    end

    # --- Update: mark verified --------------------------------------------

    test "marking verified writes the verified flag" do
      sign_in @user

      patch :update, params: { id: "recValid", verify: "1" }

      assert_redirected_to admin_reimbursements_people_path
      table, record_id, fields = @client.updated.sole
      assert_equal :people, table
      assert_equal "recValid", record_id
      assert fields[FIELD_IDS[:people][:verified]]
    end

    test "cannot verify a person without bank details" do
      sign_in @user

      patch :update, params: { id: "recMissing", verify: "1" }

      assert_redirected_to admin_reimbursements_people_path
      assert_match(/no bank details/, flash[:alert])
      assert_empty @client.updated
    end

    test "updating an unknown person 404s" do
      sign_in @user

      patch :update, params: { id: "recNope", verify: "1" }

      assert_response :not_found
      assert_empty @client.updated
    end
  end
  end
end
