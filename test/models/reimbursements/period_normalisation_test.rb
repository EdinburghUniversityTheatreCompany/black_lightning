require "test_helper"

module Reimbursements
  ##
  # The EUSA accounting period has ONE canonical spelling, zero-padded to two
  # digits, so the ledger's filter cannot offer "05", "06", "5" and "6" as four
  # different months (it did: ?period=6 returned 12 rows and ?period=06 five).
  #
  # Covered here: the pure rule, the model write path, the backfill of rows
  # already stored, and — the one that actually costs money if it breaks — that
  # dedup still recognises a re-pasted row across the two spellings.
  class PeriodNormalisationTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # --- The rule ----------------------------------------------------------

    test "pads a bare month to two digits" do
      assert_equal "06", Reconciliation.normalise_period("6")
      assert_equal "01", Reconciliation.normalise_period(" 1 ")
    end

    test "leaves an already-canonical period alone, and is idempotent" do
      assert_equal "06", Reconciliation.normalise_period("06")
      assert_equal "06", Reconciliation.normalise_period(Reconciliation.normalise_period("6"))
      assert_equal "12", Reconciliation.normalise_period("12")
    end

    test "covers Sage's year-end period 13" do
      assert_equal "13", Reconciliation.normalise_period("13")
    end

    test "leaves a spelling it does not understand exactly as the sheet wrote it" do
      # Padding something we cannot read would be guessing at a figure finance
      # reads back off the filter.
      assert_equal "P6", Reconciliation.normalise_period("P6")
      assert_equal "2026/06", Reconciliation.normalise_period("2026/06")
      assert_equal "", Reconciliation.normalise_period(nil)
      assert_equal "100", Reconciliation.normalise_period("100")
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

    test "the reconcile parser normalises the period it reads off the sheet" do
      header = "Nominal\tCost Centre\tRef\tDate\tPeriod\tNarrative\tNarrative 1\tDebit\tCredit\tNet"
      row = "439999\tF40\tBACS001\t01/09/2026\t6\tBACS PAYMENT\t\t10.00\t\t10.00"
      rows = Reconciliation.parse_actuals_rows("#{header}\n#{row}")

      assert_equal "06", rows.sole.period
    end

    # --- The backfill ------------------------------------------------------

    test "the backfill rewrites stored rows and reports how many" do
      unpadded = create_reimbursements_eusa_actual(period: "6", debit: BigDecimal("10"))
      # update_column, not the model: the before_validation callback is exactly
      # what this backfill exists to have been missing.
      unpadded.update_column(:period, "6")
      already = create_reimbursements_eusa_actual(period: "07", debit: BigDecimal("11"))

      rewritten = PeriodNormalisation.run!

      assert_equal 1, rewritten
      assert_equal "06", unpadded.reload.period
      assert_equal "07", already.reload.period
    end

    test "the backfill is idempotent" do
      create_reimbursements_eusa_actual(period: "6", debit: BigDecimal("10"))
        .update_column(:period, "6")
      PeriodNormalisation.run!

      assert_equal 0, PeriodNormalisation.run!
    end

    test "the backfill leaves a period it cannot read alone" do
      row = create_reimbursements_eusa_actual(period: "06", debit: BigDecimal("10"))
      row.update_column(:period, "P6")

      PeriodNormalisation.run!

      assert_equal "P6", row.reload.period
    end

    # --- Dedup across the two spellings ------------------------------------
    #
    # The reconcile wizard buckets a paste by (period, cost centre) and asks
    # the store for what is already imported for that period. If the two
    # spellings did not meet, re-pasting a month would import every row a
    # second time and double-count real spend in the ledger and every rollup.

    test "an unpadded paste finds a stored padded row for the same month" do
      create_reimbursements_eusa_actual(period: "06", narrative: "BACS RUN",
                                        debit: BigDecimal("10"))

      assert_equal 1, Reimbursements.build_store.actuals_for_period("6").size
    end

    test "a padded paste finds a stored unpadded row for the same month" do
      row = create_reimbursements_eusa_actual(period: "06", narrative: "BACS RUN",
                                              debit: BigDecimal("10"))
      row.update_column(:period, "6")

      assert_equal 1, Reimbursements.build_store.actuals_for_period("06").size
    end

    test "a different month is still a different bucket" do
      create_reimbursements_eusa_actual(period: "06", debit: BigDecimal("10"))

      assert_empty Reimbursements.build_store.actuals_for_period("7")
    end
  end
end
