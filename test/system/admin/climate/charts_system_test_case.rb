require "application_system_test_case"

module Admin
  module Climate
    # Logs in a user who can read the climate dashboard, for the chart browser tests.
    class ChartsSystemTestCase < ApplicationSystemTestCase
      include ClimateTestHelpers

      setup do
        role = ::Role.create!(name: "Climate Viewer")
        role.permissions << ::Admin::Permission.create(action: "read", subject_class: "climate")
        role.permissions << ::Admin::Permission.create(action: "access", subject_class: "backend")
        users(:member).add_role("Climate Viewer")
        login_as users(:member)
      end
    end
  end
end
