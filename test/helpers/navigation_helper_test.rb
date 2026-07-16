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

    titles = finance_category[:children].map { |child| child[:title] }

    assert_not_includes titles, "Review"
    assert_not_includes titles, "Settings"
    # Reimbursements/Payment Details are gated on the separate :access permission instead.
    assert_includes titles, "Reimbursements"
    assert_includes titles, "Payment Details"
  end
end
