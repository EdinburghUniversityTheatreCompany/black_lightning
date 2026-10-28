require "test_helper"

module Admin
  module Reimbursements
    ##
    # "Pair offsetting rows": an estimate and its reversal pasted in different months. Proposed
    # through the hand-pairing gate, ticked by the detector's score, confirmed by a person.
    class ActualsPairOffsetsTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      tests ActualsController

      setup do
        grant_finance_permission(users(:member))
        sign_in users(:member)
        @estimate = estimate_leg(credit: BigDecimal("12381.81"), period: "05", date: Date.new(2026, 9, 7))
        @reversal = estimate_leg(debit: BigDecimal("12381.81"), period: "06", date: Date.new(2026, 10, 4))
      end

      # Production's Bedlam Fringe pair, one journal reference on both legs.
      def estimate_leg(**attrs)
        create_reimbursements_eusa_actual(nominal_code: "331130", ref: "JNL0442",
                                          narrative: "P5 F40 accrued ticket income",
                                          cost_centre_id: ::Reimbursements::CostCentre.order(:id).first.id, **attrs)
      end

      def pair_key = "#{@reversal.id}:#{@estimate.id}"

      test "the ledger proposes the pair, ticked, and marking it takes both legs out of every total" do
        get :index

        assert_response :success
        assert_select "input[type=checkbox][name='pairs[]'][value=?][checked]", pair_key
        assert_select "input[type=submit][value=?]", "Mark the ticked pairs as offsetting"

        post :pair_offsets, params: { pairs: [ pair_key ] }

        assert_redirected_to admin_reimbursements_actuals_path
        assert_equal "Marked 1 pair as offsetting, so neither row counts as spend or income. " \
                     "\"Not offsetting\" on the full ledger undoes a pair.", flash[:notice]
        assert [ @estimate, @reversal ].map(&:reload).all?(&:offset?)
        assert_equal @estimate.id, @reversal.offset_of_id
      end

      test "an unticked pair is left alone" do
        post :pair_offsets, params: { pairs: [] }

        assert_not [ @estimate, @reversal ].map(&:reload).any?(&:offset?)
      end

      # Listed, so a credit Link credits or Reconcile held back is never stranded, but not ticked.
      test "weak evidence is proposed unticked: no shared reference, period or narrative, months apart" do
        @reversal.update!(ref: "SI0099", period: "09", narrative: "Box office takings", date: Date.new(2027, 1, 20))

        get :index

        assert_select "input[name='pairs[]'][value=?]", pair_key
        assert_select "input[name='pairs[]'][checked]", count: 0
      end

      test "a period filter shows only the pairs with a leg in that period" do
        get :index, params: { period: "06" }

        assert_select "input[name='pairs[]'][value=?]", pair_key

        get :index, params: { period: "03" }

        assert_select "input[name='pairs[]']", count: 0
      end

      test "rows on different codes or in different cost centres are never proposed" do
        @reversal.update!(nominal_code: "331300")

        get :index

        assert_select "input[name='pairs[]']", count: 0

        @reversal.update!(nominal_code: "331130", cost_centre_id: create_second_reimbursements_cost_centre.id)

        get :index

        assert_select "input[name='pairs[]']", count: 0
      end

      # The checkbox is a stale read: a leg linked since must not be hidden as noise.
      test "a pair one of whose legs was placed since the page loaded is refused" do
        @estimate.update!(budget: create_reimbursements_budget(name: "Tickets", budget_type: "Income",
                                                               nominal_code: "331130"))

        post :pair_offsets, params: { pairs: [ pair_key, "not-a-pair", { "x" => "1" } ] }

        assert_not @reversal.reload.offset?
        assert_equal "No pairs marked. 1 pair left alone: a row in it was already in another marked " \
                     "pair, or changed since the page loaded.",
                     flash[:notice]
      end

      test "the full ledger and its CSV skip the proposals" do
        get :index, params: { state: ActualsController::STATE_ALL }

        assert_response :success
        assert_nil assigns(:offset_pairs)
      end
    end
  end
end
