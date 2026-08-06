require "test_helper"

# The :climate grid permission. app/models/ability.rb asks for a test per
# permission, and this one has two tiers (read the charts vs configure the
# sensors) whose relationship is worth pinning down.
class Climate::AbilityTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  test "a user with no climate permission can neither read nor manage" do
    ability = Ability.new(FactoryBot.create(:user))

    assert ability.cannot?(:read, :climate)
    assert ability.cannot?(:manage, :climate)
  end

  test "the read permission grants viewing the dashboard" do
    user = FactoryBot.create(:user)
    grant_climate_read_permission(user)

    assert Ability.new(user).can?(:read, :climate)
  end

  test "the read permission does NOT grant configuring sensors" do
    # Otherwise anyone who can look at the charts could flip a sensor's
    # temperature unit, which silently rewrites what every future reading means.
    user = FactoryBot.create(:user)
    grant_climate_read_permission(user)

    assert Ability.new(user).cannot?(:manage, :climate)
  end

  test "the manage permission also grants reading" do
    # CanCan's :manage matches any action, so the tiers nest without extra code.
    user = FactoryBot.create(:user)
    grant_climate_manage_permission(user)
    ability = Ability.new(user)

    assert ability.can?(:manage, :climate)
    assert ability.can?(:read, :climate)
  end

  test "a guest can do neither" do
    ability = Ability.new(nil)

    assert ability.cannot?(:read, :climate)
    assert ability.cannot?(:manage, :climate)
  end

  test "an admin can do both" do
    ability = Ability.new(users(:admin))

    assert ability.can?(:read, :climate)
    assert ability.can?(:manage, :climate)
  end

  test "the climate permission does not leak into other subjects" do
    user = FactoryBot.create(:user)
    grant_climate_manage_permission(user)
    ability = Ability.new(user)

    assert ability.cannot?(:manage, :reimbursements_finance)
    assert ability.cannot?(:access, :backend)
  end

  test "the sensor models are kept out of the permission grid" do
    # They are managed only through the climate pages, so a CRUD row for them in
    # the grid would be meaningless — the same rule as the reimbursements models.
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
