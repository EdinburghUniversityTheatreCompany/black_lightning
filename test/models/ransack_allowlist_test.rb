require "test_helper"

# Ransack 6's Search#respond_to? walks the model's association allowlist, and the default one
# raises. simple_form asks respond_to? of every search field and TableComponent of every sortable
# header, so a model with only an attributes list 500s its index page. Declare both lists.
class RansackAllowlistTest < ActiveSupport::TestCase
  test "every model with a ransack attributes list also lists its associations" do
    Rails.application.eager_load!
    models = ApplicationRecord.descendants.reject(&:abstract_class?).select do |model|
      model.method(:ransackable_attributes).owner.name.nil? # defined on the model, not Ransack's default
    end
    assert_operator models.size, :>, 30

    ability = Ability.new(nil) # some lists consult it, as GenericController passes current_ability
    broken = models.select do |model|
      model.ransack({}, auth_object: ability).respond_to?(:type_for_attribute)
      false
    rescue RuntimeError
      true
    end
    assert_empty broken.map(&:name), "these models need a ransackable_associations list"
  end
end
