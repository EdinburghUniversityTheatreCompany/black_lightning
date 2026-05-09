require "test_helper"
require "generators/chaos_rails/admin_controller/admin_controller_generator"

class ChaosRails::AdminControllerGeneratorTest < Rails::Generators::TestCase
  tests ChaosRails::AdminControllerGenerator
  destination Rails.root.join("tmp/generators")

  setup do
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
  end

  test "generator runs without errors" do
    assert_nothing_raised do
      run_generator [ "Admin::StaffingJob", [ "name:string" ] ]
    end
  end
end
