require "test_helper"
require "bigdecimal"

module Reimbursements
  class ActualsAttributionTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

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
        ([ ACTUALS_HEADER ] + cost_centres.each_with_index.map { |cc, i| row_text(cc, narrative: "Row #{i}") })
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
      assert_equal [ "Row 0", "Row 1", "Row 2" ], result.attributed.map { |entry| entry.row.narrative }
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

    # A blank code is never inferred, even with one centre: "it must be the only one" files spend
    # under the wrong pot the day a second exists.
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

    # "Not ours" is a real answer to the mandatory question; without it the operator must park
    # another society's rows under the nearest centre.
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
  end
end
