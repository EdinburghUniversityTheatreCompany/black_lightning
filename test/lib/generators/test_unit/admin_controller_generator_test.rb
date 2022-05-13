require "test_helper"
require "generators/test_unit/admin_controller/admin_controller_generator"
require "rails/generators/test_unit"

class TestUnit::AdminControllerGeneratorTest < Rails::Generators::TestCase
  tests TestUnit::Generators::AdminControllerGenerator
  destination Rails.root.join('tmp/generators')
  setup :prepare_destination

  test "generator runs without errors" do
    assert_nothing_raised do
      run_generator ['TestUnit::AdminController', 'name:string']
    end
  end
end
