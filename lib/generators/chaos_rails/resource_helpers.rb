module ChaosRails::ResourceHelpers
  def self.included(base) # :nodoc:
    base.include(Rails::Generators::ResourceHelpers)
    base.class_option :model_name, type: :string, desc: "ModelName to be used"
  end

  def resource_name
    @resource_name ||= controller_name.demodulize.underscore.singularize
  end
end
