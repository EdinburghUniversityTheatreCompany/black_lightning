require "generators/chaos_rails/resource_helpers"

class ChaosRails::AdminControllerGenerator < Rails::Generators::NamedBase
  include Rails::Generators::ResourceHelpers
  include ChaosRails::ResourceHelpers

  source_root File.expand_path("../templates", __FILE__)

  argument :attributes, type: :array, default: [], banner: "field:type field:type"

  def create_controller_files
    template_file = "admin_controller.rb"
    template template_file, File.join("app/controllers/admin", controller_class_path, "#{controller_file_name}_controller.rb")
  end

  def add_resource_route
    namespace = regular_class_path

    unless namespace.first == "admin"
      namespace.insert(0, "admin")
    end

    route "resources :#{file_name.pluralize}", namespace: namespace
  end

  hook_for :template_engine, as: :admin_controller do |template_engine|
    invoke template_engine
  end

  hook_for :test_framework, as: :admin_controller

  private

  def permitted_params
    attachments, others = attributes_names.partition { |name| attachments?(name) }
    params = others.map { |name| ":#{name}" }
    params += attachments.map { |name| "#{name}: []" }
    params.join(", ")
  end

  def attachments?(name)
    attribute = attributes.find { |attr| attr.name == name }
    attribute&.attachments?
  end
end
