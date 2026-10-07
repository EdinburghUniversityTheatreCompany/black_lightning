require "test_helper"

module Reimbursements
  ##
  # The EUSA period has ONE canonical spelling, zero-padded to two digits. Covers the pure rule, the
  # model write path, the backfill, and the one that costs money if it breaks: dedup still recognising
  # a re-pasted row across the two spellings.
  class PeriodNormalisationTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # --- The rule ----------------------------------------------------------

    # Padding what we cannot read would be guessing at a figure finance reads back off the filter.
    test "pads a bare month and leaves any other spelling as the sheet wrote it" do
      { "6" => "06", " 1 " => "01", "06" => "06", "12" => "12", "13" => "13",
        "P6" => "P6", "2026/06" => "2026/06", "100" => "100", nil => "" }.each do |stored, canonical|
        assert_equal canonical, Reconciliation.normalise_period(stored), stored.inspect
      end
    end

    # --- The write paths ---------------------------------------------------

    test "the model normalises on save, whatever wrote the row" do
      actual = create_reimbursements_eusa_actual(period: "6", debit: BigDecimal("10"))
      assert_equal "06", actual.reload.period
    end

    test "a nil period stays nil rather than becoming a blank string" do
      actual = create_reimbursements_eusa_actual(period: nil, debit: BigDecimal("10"))
      assert_nil actual.reload.period
    end

    # --- The backfill ------------------------------------------------------

    test "the backfill rewrites stored rows and reports how many" do
      unpadded = create_reimbursements_eusa_actual(period: "6", debit: BigDecimal("10"))
      # update_column, not the model: the before_validation is what this backfill exists to have been missing.
      unpadded.update_column(:period, "6")
      already = create_reimbursements_eusa_actual(period: "07", debit: BigDecimal("11"))

      rewritten = PeriodNormalisation.run!

      assert_equal 1, rewritten
      assert_equal "06", unpadded.reload.period
      assert_equal "07", already.reload.period
      assert_equal 0, PeriodNormalisation.run!, "a second run finds nothing to do"
    end

    test "the backfill leaves a period it cannot read alone" do
      row = create_reimbursements_eusa_actual(period: "06", debit: BigDecimal("10"))
      row.update_column(:period, "P6")

      PeriodNormalisation.run!

      assert_equal "P6", row.reload.period
    end

    # --- Dedup across the two spellings ------------------------------------
    #
    # If the spellings did not meet, re-pasting a month would import every row twice and double-count
    # real spend.

    test "a period lookup finds the month under either spelling, and no other month" do
      create_reimbursements_eusa_actual(period: "06", debit: BigDecimal("10"))
      create_reimbursements_eusa_actual(period: "06", debit: BigDecimal("11")).update_column(:period, "6")
      store = Reimbursements.build_store

      assert_equal 2, store.actuals_for_period("6").size
      assert_equal 2, store.actuals_for_period("06").size
      assert_empty store.actuals_for_period("7")
    end
  end
end
