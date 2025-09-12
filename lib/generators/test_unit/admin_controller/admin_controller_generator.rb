require "rails/generators/test_unit"
require "rails/generators/test_unit/scaffold/scaffold_generator"
require "generators/chaos_rails/resource_helpers"

class TestUnit::Generators::AdminControllerGenerator < TestUnit::Generators::ScaffoldGenerator
  # Same as what the original does, but put them in admin folders.
  # Creating a new generator is also necessary so resource_name from ResourceHelpers is accessible.
  include ChaosRails::ResourceHelpers

  source_root File.expand_path("../templates", __FILE__)

  private

  def class_path
    result = super

    result.insert(0, "admin") unless result.first == "admin"

    result
  end

  def controller_class_path
    result = super

    result.insert(0, "admin") unless result.first == "admin"

    result
  end
end
