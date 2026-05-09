require "test_helper"
require "generators/chaos_rails/scaffold/scaffold_generator"

class ChaosRails::ScaffoldGeneratorTest < Rails::Generators::TestCase
  tests ChaosRails::ScaffoldGenerator
  destination Rails.root.join("tmp/generators")

  setup do
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
  end

  test "generator runs without errors" do
    assert_nothing_raised do
      run_generator [ "Test::Scaffold", [ "name:string" ] ]
    end
  end
end
