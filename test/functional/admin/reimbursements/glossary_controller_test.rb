require "test_helper"

module Admin
  module Reimbursements
    ##
    # The portal had no glossary anywhere, and its best explanations were
    # `title=` tooltips — invisible on a touch screen and to the keyboard.
    class GlossaryControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      setup do
        @user = users(:member)
      end

      test "requires sign-in" do
        get :show
        assert_redirected_to new_user_session_path
      end

      # Gated on the BASE portal permission, not the finance one: an owner
      # reads "committed", "left" and "endorse" on their own area page, and a
      # producer reads "Submitted" on a claim they sent weeks ago.
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

      # Remaining and Left are two different figures for one English word, and
      # the portal prints both. A glossary that did not separate them would
      # leave the reader worse off than one that never mentioned either.
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
