require 'rails/generators/rails/scaffold/scaffold_generator'
require 'generators/chaos_rails/resource_helpers'
require 'generators/chaos_rails/admin_controller/admin_controller_generator'

class ChaosRails::ScaffoldGenerator < Rails::Generators::ScaffoldGenerator
  include ChaosRails::ResourceHelpers

  Rails::Generators.invoke 'chaos_rails:admin_controller'
  Rails::Generators.invoke 'chaos_rails:fixtures'

  remove_hook_for :resource_route
  remove_hook_for :scaffold_controller
end
