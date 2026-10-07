require "test_helper"

module Reimbursements
  class AreaTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    test "an area is a spend cap unless somebody says otherwise" do
      # The safe default: a spend cap never reports more room than there is.
      assert_equal "expenses", create_reimbursements_area(name: "Cogito").budget_basis
    end

    test "the basis is one of the two the card can name" do
      area = create_reimbursements_area(name: "Cogito")
      area.budget_basis = "gross"

      assert_not area.valid?
      assert area.errors[:budget_basis].present?
    end

    # Stands in for the re-migrate case (the backfill creates areas before the
    # column exists), which a test cannot reach without DDL.
    test "an area whose basis attribute is not loaded still validates" do
      area = create_reimbursements_area(name: "Cogito")

      assert Area.select(:id, :name).find(area.id).valid?
    end

    test "the words on the form are the words on the card" do
      assert_equal "Agreed total (expenses)",
                   create_reimbursements_area(name: "Show", budget_basis: "expenses").basis_label
      assert_equal "Agreed total (net)",
                   create_reimbursements_area(name: "Committee", budget_basis: "net").basis_label
    end
  end
end
