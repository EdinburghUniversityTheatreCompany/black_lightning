require "application_system_test_case"

# Each controller file registers under the identifier its path gives
# (admin/permissions_grid_controller.js is admin--permissions-grid), and nested-form
# comes from its package. A registration that drops or renames one leaves every
# data-controller using it dead without an error.
class StimulusRegistrationTest < ApplicationSystemTestCase
  CONTROLLERS = Rails.root.join("app/javascript/controllers")

  test "every controller file registers under its path's identifier" do
    from_files = Dir.glob("**/*_controller.js", base: CONTROLLERS).map do |path|
      path.delete_suffix("_controller.js").gsub("/", "--").tr("_", "-")
    end

    visit root_path

    registered = evaluate_script("Stimulus.router.modules.map((module) => module.identifier)")
    assert_equal (from_files + [ "nested-form" ]).sort, registered.sort
  end
end
