require "rails/generators/rails/scaffold/scaffold_generator"
require "generators/chaos_rails/resource_helpers"
require "generators/chaos_rails/admin_controller/admin_controller_generator"

class ChaosRails::ScaffoldGenerator < Rails::Generators::ScaffoldGenerator
  include ChaosRails::ResourceHelpers

  remove_hook_for :resource_route
  remove_hook_for :scaffold_controller

  def invoke_admin_controller
    invoke "chaos_rails:admin_controller"
  end

  def invoke_fixtures_generator
    invoke "chaos_rails:fixtures"
  end
end
