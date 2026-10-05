require "test_helper"

module Admin
  module Reimbursements
    class GlossaryControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      setup do
        @user = users(:member)
      end

      test "requires sign-in" do
        get :show
        assert_redirected_to new_user_session_path
      end

      # The base portal permission, not finance: owners and producers read these words too.
      test "a producer with no finance permission can read it" do
        grant_producer_permission(@user)
        sign_in @user

        get :show

        assert_response :success
      end

      test "someone with no portal access at all cannot" do
        sign_in users(:committee)
        get :show
        assert_response :forbidden
      end

      test "defines every word the audit named" do
        grant_producer_permission(@user)
        sign_in @user

        get :show

        assert_response :success
        %w[Area Cost\ centre Nominal\ code Actuals Offsetting\ pair Endorse Committed
           Pipeline Expected\ outturn Variance].each do |term|
          assert_match(/#{Regexp.escape(term)}/, response.body, "#{term} is undefined")
        end
      end

      # Remaining and Left are different figures for one idea, and both are printed.
      test "separates Remaining from Left" do
        grant_producer_permission(@user)
        sign_in @user

        get :show

        assert_match(/IGNORES the pipeline/, response.body)
        assert_match(/can my show still afford this/i, response.body)
      end

      test "the terms helper refuses a key it does not define" do
        assert_raises(ArgumentError) { ::Reimbursements::Glossary.terms(:not_a_term) }
      end

      test "every section's terms carry a definition" do
        ::Reimbursements::Glossary::ALL.each do |term|
          assert term.term.present?, "a glossary entry with no word"
          assert term.definition.present?, "#{term.key} has no definition"
        end
      end

      test "no term is defined twice" do
        keys = ::Reimbursements::Glossary::ALL.map(&:key)
        assert_equal keys.uniq, keys, "a term defined twice can drift from itself"
      end
    end
  end
end
