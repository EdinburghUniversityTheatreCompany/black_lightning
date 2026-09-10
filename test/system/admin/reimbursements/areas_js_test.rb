require "application_system_test_case"

module Admin
  module Reimbursements
    # The one browser-driven check on the areas admin screen: clicking the
    # real "Add budget line" / Save buttons. A request-level test POSTs
    # straight to the action and can't see a form_with opened INSIDE a
    # CardComponent (its submit renders outside the <form> and silently does
    # nothing) — only a system test clicking the real button catches that.
    class AreasJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        login_as users(:member)
      end

      test "adds a budget line to an area in the browser" do
        area = create_reimbursements_area(name: "Cogito")

        visit edit_admin_reimbursements_area_path(area.record_id)
        click_on "Add budget line"
        # stimulus-rails-nested-form's own wrapperSelector default — each row
        # (new or existing) is a ".nested-form-wrapper" div; the gem exposes
        # no "item" Stimulus target to select by.
        within all(".nested-form-wrapper").last do
          fill_in "Name", with: "Cogito: Marketing"
          fill_in "Nominal code", with: "432320"
        end
        click_on "Save"

        assert_text "Area saved"
        assert_equal "Cogito: Marketing", area.reload.budgets.last&.name
      end
    end
  end
end
