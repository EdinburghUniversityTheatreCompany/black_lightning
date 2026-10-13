require "application_system_test_case"

module Admin
  module Climate
    # Logs in a user who can read the climate dashboard, for the chart browser tests.
    class ChartsSystemTestCase < ApplicationSystemTestCase
      include ClimateTestHelpers

      setup do
        grant_backend(users(:member))
        grant_climate_read_permission(users(:member))
        login_as users(:member)
      end
    end
  end
end
