require "application_system_test_case"

module Admin
  # admin.css makes a link in <main> brand red unless it names a colour of its own. The markup
  # carries the right classes either way, so only the computed colour shows which rule won.
  class LinkColoursTest < ApplicationSystemTestCase
    include ReimbursementsTestHelpers

    test "a link that names its own colour shows it, and a plain link stays brand red" do
      grant_finance_permission(users(:member))
      login_as users(:member)
      visit admin_reimbursements_budgets_path

      current_tab = find("nav[aria-label='Budget views'] a[aria-current=page]", text: "Budgets")
      assert_equal theme_colour("--color-blue-800"), colour_of(current_tab)

      # Injected, so no later class on a real link can make this pass for the wrong reason.
      execute_script(%(document.querySelector("main").insertAdjacentHTML("afterbegin", '<a href="#" id="plain-link">Plain</a>')))
      assert_equal theme_colour("--color-primary"), colour_of(find("main a#plain-link"))
    end

    test "a markdown link stays brand red" do
      venue = venues(:roxy)
      venue.update!(description: "Get in by [the stage door](https://example.org/stage-door).")
      login_as users(:admin)
      visit admin_venue_path(venue)

      assert_equal theme_colour("--color-primary"), colour_of(find("main .prose a", text: "the stage door"))
    end
  end
end
