require "test_helper"

# The :climate grid permission, in two tiers: read the charts, configure the sensors.
class Climate::AbilityTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  test "read lets you view, manage also configures" do
    # CanCan's :manage matches any action, so the tiers nest without extra code.
    reader = FactoryBot.create(:user).tap { |user| grant_climate_read_permission(user) }
    manager = FactoryBot.create(:user).tap { |user| grant_climate_manage_permission(user) }
    outcomes = { nil => [ false, false ], FactoryBot.create(:user) => [ false, false ],
                 reader => [ true, false ], manager => [ true, true ], users(:admin) => [ true, true ] }

    outcomes.each do |user, expected|
      ability = Ability.new(user)

      assert_equal expected, [ ability.can?(:read, :climate), ability.can?(:manage, :climate) ], user&.email.inspect
    end
  end

  test "the sensor models are kept out of the permission grid" do
    # Managed only through the climate pages, so a grid CRUD row would be meaningless.
    controller = Admin::PermissionsController.new
    controller.send(:set_models_and_roles)
    models = controller.instance_variable_get(:@models)

    assert_not_includes models, Climate::Sensor
    assert_not_includes models, Climate::Reading
  end

  test "the climate subject is offered in the permission grid" do
    controller = Admin::PermissionsController.new
    controller.send(:set_models_and_roles)
    miscellaneous = controller.instance_variable_get(:@miscellaneous_permission_subject_classes)

    assert_equal %w[read manage], miscellaneous["climate"].keys
  end
end
