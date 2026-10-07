require "test_helper"

module Admin
  module Reimbursements
    class GlossaryControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      setup do
        @user = users(:member)
      end

      # The base portal permission, not finance: owners and producers read these words too.
      # Remaining and Left are different figures for one idea, and both are printed.
      test "a producer can read it, and it defines the audit's words" do
        grant_producer_permission(@user)
        sign_in @user

        get :show

        assert_response :success
        %w[Area Cost\ centre Nominal\ code Actuals Offsetting\ pair Endorse Committed
           Pipeline Expected\ outturn Variance].each do |term|
          assert_match(/#{Regexp.escape(term)}/, response.body, "#{term} is undefined")
        end
        assert_match(/IGNORES the pipeline/, response.body)
        assert_match(/can my show still afford this/i, response.body)
      end

      test "someone with no portal access at all cannot" do
        sign_in users(:committee)
        get :show
        assert_response :forbidden
      end

      test "the terms helper refuses a key it does not define" do
        assert_raises(ArgumentError) { ::Reimbursements::Glossary.terms(:not_a_term) }
      end

      test "no term is defined twice" do
        keys = ::Reimbursements::Glossary::ALL.map(&:key)
        assert_equal keys.uniq, keys, "a term defined twice can drift from itself"
      end
    end
  end
end
