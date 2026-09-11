require "test_helper"

module Reimbursements
  class AreaTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    test "requires a name" do
      area = Area.new(name: "")
      assert_not area.valid?
      assert area.errors[:name].present?
    end

    test "a budget belongs to an area, and an area-less budget is still valid" do
      area = create_reimbursements_area(name: "Cogito")
      in_area = create_reimbursements_budget(name: "Cogito: Marketing", area: area)
      loose = create_reimbursements_budget(name: "Contingency")

      assert_equal area, in_area.area
      assert_nil loose.area
      assert_equal [ in_area ], area.budgets.to_a
    end

    test "record_id is the id as a string, like a budget's" do
      area = create_reimbursements_area(name: "Cogito")
      assert_equal area.id.to_s, area.record_id
    end

    test "an area is a spend cap unless somebody says otherwise" do
      # Every area that exists came from the Phase 1 backfill of show-shaped
      # lines, and a spend cap never reports more room than there is. A
      # committee's net allowance is one deliberate choice by a human.
      assert_equal "expenses", create_reimbursements_area(name: "Cogito").budget_basis
    end

    test "the basis is one of the two the card can name" do
      area = create_reimbursements_area(name: "Cogito")
      area.budget_basis = "gross"

      assert_not area.valid?
      assert area.errors[:budget_basis].present?
    end

    # Standing in for the case a test cannot reach without DDL: the backfill
    # creates areas through this model, and on a re-migrate after a rollback it
    # runs BEFORE the migration that adds budget_basis — where a bare inclusion
    # raises on an attribute that is not there and stops the whole chain, so
    # the areas could be unwound but never put back.
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
