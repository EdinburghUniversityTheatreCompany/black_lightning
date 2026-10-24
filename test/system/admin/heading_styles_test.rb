require "application_system_test_case"

module Admin
  # admin.css styles a bare h3 in the base layer, so an h3's own utilities win, and keeps
  # markdown h3s off the typography plugin's scale. Only computed styles show which rule won.
  class HeadingStylesTest < ApplicationSystemTestCase
    include ReimbursementsTestHelpers

    test "an h3 with its own size shows it" do
      grant_finance_permission(users(:member))
      login_as users(:member)
      area = create_reimbursements_area(name: "Cogito")
      visit edit_admin_reimbursements_area_path(area.record_id)

      # text-sm
      assert_equal "14px", style_of(find("main h3", text: "Budgets"), "fontSize")
    end

    test "entry year headings show their own colours" do
      Techie.create!(name: "Yearless", entry_year: nil)
      login_as users(:admin)
      visit by_entry_year_admin_techies_path

      assert_equal theme_colour("--color-primary"), colour_of(find("main h3", text: "2010"))
      assert_equal theme_colour("--color-gray-500"), colour_of(find("main h3", text: "No Entry Year"))
    end

    test "a plain h3 and a markdown h3 keep the admin heading style" do
      venue = venues(:roxy)
      venue.update!(description: "### Getting in\n\nUse the stage door.\n\n### Parking {.mb-4}\n\nNone.")
      login_as users(:admin)
      visit admin_venue_path(venue)

      # Injected, so no class on a real heading can make this pass for the wrong reason.
      execute_script(%(document.querySelector("main").insertAdjacentHTML("afterbegin", '<h3 id="plain-heading">Plain</h3>')))

      # text-xl font-semibold text-gray-700 mb-2
      expected = { "fontSize" => "20px", "lineHeight" => "28px", "fontWeight" => "600",
                   "color" => theme_colour("--color-gray-700"), "marginBottom" => "8px" }
      [ find("main h3#plain-heading"), find("main .prose h3", text: "Getting in") ].each do |heading|
        assert_equal expected, expected.keys.index_with { |property| style_of(heading, property) }, heading.text
      end

      # bootstrap_compat's unlayered mb-4, typed in the markdown, still beats the heading rule.
      assert_equal "24px", style_of(find("main .prose h3", text: "Parking"), "marginBottom")
    end
  end
end
