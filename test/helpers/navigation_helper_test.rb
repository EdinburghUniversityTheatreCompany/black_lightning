require "test_helper"

class NavigationHelperTest < ActionView::TestCase
  include ReimbursementsTestHelpers

  def current_ability
    @current_user.ability
  end

  # CanCanCan wires can?/cannot? into controllers (and so views) via its
  # Railtie; a bare ActionView::TestCase doesn't go through that, so delegate
  # them here the same way User itself does.
  def can?(...)
    current_ability.can?(...)
  end

  def cannot?(...)
    current_ability.cannot?(...)
  end

  setup do
    @current_user = users(:committee)
  end

  def finance_category
    admin_navbar_items.find { |category| category[:title] == "Finance" }
  end

  def my_reimbursements_category
    admin_navbar_items.find { |category| category[:title] == "My Reimbursements" }
  end

  test "the nine finance-gated links are hidden without the finance permission" do
    # A category with zero visible children is dropped entirely
    # (navbar_categories.reject! { |c| c[:children].empty? }) — with no
    # reimbursements permission at all, "Finance" doesn't appear at all.
    assert_nil finance_category
  end

  test "every finance-gated link appears with the finance permission" do
    grant_finance_permission(@current_user)
    @current_user.instance_variable_set(:@ability, nil) # ability is memoized; force a rebuild

    gated_titles = [ "Review claims", "All claims", "Build batch", "Batches", "Budgets",
                     "Overview", "Areas", "Forecast revisions", "Reconcile", "Ledger",
                     "Export workbook", "People", "Financial years", "Cost centres",
                     "Email & integrations" ]

    titles = finance_category[:children].map { |child| child[:title] }

    gated_titles.each { |title| assert_includes titles, title }
  end

  # Fifteen flat links put the weekly work at positions 1, 2, 9 and 10, so the
  # category is broken into the four jobs — in the order they are done.
  test "the finance links are grouped by the job they belong to, weekly work first" do
    grant_finance_permission(@current_user)
    @current_user.instance_variable_set(:@ability, nil)

    groups = finance_category[:children].map { |child| child[:group] }

    assert_equal [ "Pay claims", "Budgets", "EUSA ledger", "Setup" ], groups.uniq
    assert_empty groups.compact_blank.tally.select { |_, count| count.zero? },
                 "every finance link needs a group, or it renders under the previous one"
    assert_nil groups.find(&:blank?), "a finance link with no group: #{finance_category[:children].inspect}"
  end

  test "the producer portal permission alone does not reveal the finance-gated links" do
    grant_producer_permission(@current_user)
    @current_user.instance_variable_set(:@ability, nil)

    # The finance-only category is dropped entirely for a producer.
    assert_nil finance_category

    # Their own claim/payment/budget links live in a separate My Reimbursements
    # category, gated on the base :access permission.
    titles = my_reimbursements_category[:children].map { |child| child[:title] }
    assert_includes titles, "My Claims"
    assert_includes titles, "Payment Details"
    assert_includes titles, "My Budgets"
  end
end
