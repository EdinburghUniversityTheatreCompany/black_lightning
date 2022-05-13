require 'test_helper'
require 'generators/chaos_rails/admin_controller/admin_controller_generator'

class ChaosRails::AdminControllerGeneratorTest < Rails::Generators::TestCase
  tests ChaosRails::AdminControllerGenerator
  destination Rails.root.join('tmp/generators')
  setup :prepare_destination

  test "generator runs without errors" do
    assert_nothing_raised do
      run_generator ['Admin::StaffingJob', ['name:string']]
    end
  end
end
