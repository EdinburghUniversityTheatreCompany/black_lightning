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

  test "the nine finance-gated links all appear with the finance permission" do
    grant_finance_permission(@current_user)
    @current_user.instance_variable_set(:@ability, nil) # ability is memoized; force a rebuild

    gated_titles = %w[Review Expenses People Budgets Build\ Batch History Reconcile
                       EUSA\ Actuals Settings]

    titles = finance_category[:children].map { |child| child[:title] }

    gated_titles.each { |title| assert_includes titles, title }
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
