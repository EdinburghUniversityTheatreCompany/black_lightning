require "test_helper"
require "bigdecimal"

module Reimbursements
  class ActualsAttributionTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    HEADER = "Nominal\tCost Centre\tRef\tDate\tPeriod\tNarrative\tNarrative 1\tDebit\tCredit\tNet".freeze

    setup do
      @fringe = reimbursements_cost_centres(:fringe)
      @termtime = create_reimbursements_cost_centre(key: "termtime", name: "Bedlam Termtime",
                                                    eusa_code: "BED",
                                                    receive_mailbox: "bed@example.com",
                                                    send_mailbox: "bed@example.com")
    end

    def row_text(cost_centre, narrative: "Alice", amount: "10.00")
      "439999\t#{cost_centre}\tBACS001\t15/03/2025\t03\t#{narrative}\tShow\t#{amount}\t\t#{amount}"
    end

    def parse(*cost_centres)
      Reconciliation.parse_actuals_rows(
        ([ HEADER ] + cost_centres.each_with_index.map { |cc, i| row_text(cc, narrative: "Row #{i}") })
          .join("\n")
      )
    end

    def attribute(rows, blank_choice: nil)
      ActualsAttribution.new(cost_centres: [ @fringe, @termtime ])
                        .call(rows, blank_choice: blank_choice)
    end

    test "each row lands in the cost centre its own code names" do
      result = attribute(parse("F40", "BED", "F40"))

      assert_equal [ @fringe, @termtime, @fringe ], result.attributed.map(&:cost_centre)
      assert_equal [ "Row 0", "Row 1", "Row 2" ], result.rows.map(&:narrative)
      assert_empty result.dropped_rows
    end

    test "matching a code is case- and whitespace-insensitive" do
      result = attribute(parse("  f40  "))

      assert_equal [ @fringe ], result.attributed.map(&:cost_centre)
    end

    test "a row naming an unconfigured cost centre is skipped, and named" do
      result = attribute(parse("F40", "G12", "H03", "G12"))

      assert_equal [ @fringe ], result.attributed.map(&:cost_centre)
      assert_equal 3, result.unrecognised_rows.size
      assert_equal %w[G12 H03], result.unrecognised_codes,
                   "the preview has to say WHICH codes were dropped, not just how many rows"
    end

    # Even with a single cost centre configured, a blank code is never inferred.
    # "It must be the only one" is exactly the guess that files real spend under
    # the wrong pot the day a second pot exists.
    test "blank-code rows are held back until the operator chooses, even with one centre" do
      single = ActualsAttribution.new(cost_centres: [ @fringe ])
      result = single.call(parse("F40", ""), blank_choice: nil)

      assert_equal [ @fringe ], result.attributed.map(&:cost_centre)
      assert_equal 1, result.unassigned_blank_rows.size
      assert result.blank_choice_required?
    end

    test "a chosen cost centre attributes the blank rows to it" do
      result = attribute(parse("F40", ""), blank_choice: @termtime.id.to_s)

      assert_equal [ @fringe, @termtime ], result.attributed.map(&:cost_centre)
      assert_empty result.unassigned_blank_rows
      refute_predicate result, :blank_choice_required?
    end

    # "Not ours" is a real answer to a mandatory question — without it an
    # operator facing another society's blank rows has no honest way past the
    # gate except to park them under whichever centre is nearest to hand.
    test "the skip choice drops the blank rows without blocking the rest" do
      result = attribute(parse("F40", ""), blank_choice: ActualsAttribution::SKIP)

      assert_equal [ @fringe ], result.attributed.map(&:cost_centre)
      assert_equal 1, result.skipped_blank_rows.size
      refute_predicate result, :blank_choice_required?
    end

    test "an id that matches no configured centre reads as no choice at all" do
      result = attribute(parse(""), blank_choice: "999999")

      assert_empty result.attributed
      assert result.blank_choice_required?, "a bogus id must not silently import the rows anywhere"
    end

    test "cost_centre_keys identify the attributed centre, not the exported code" do
      result = attribute(parse("F40", ""), blank_choice: @fringe.id.to_s)

      assert_equal [ @fringe.id.to_s, @fringe.id.to_s ], result.cost_centre_keys,
                   "an assigned blank row is in the pot the operator chose, not in 'blank'"
    end

    test "dropped_rows collects every row the paste will not import" do
      result = attribute(parse("F40", "G12", ""), blank_choice: nil)

      assert_equal 2, result.dropped_rows.size
    end
  end
end
