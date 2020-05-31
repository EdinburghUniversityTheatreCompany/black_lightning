require 'test_helper'

class NameHelperTest < ActionView::TestCase
  test 'get_formatted_class_name' do
    assert_equal 'Maintenance Debt', get_formatted_class_name(Admin::MaintenanceDebt)
    assert_equal 'Questionnaire', get_formatted_class_name(Admin::Questionnaires::Questionnaire)
    assert_equal 'User', get_formatted_class_name(FactoryBot.create(:user))
  end

  test 'format_class_name' do
    assert_equal 'Questionnaires', format_class_name('questionnaires')
    assert_equal 'Questionnaire', format_class_name('questionnaires', true)
    assert_equal 'Admin Team Member', format_class_name('admin_team_members', true)
    assert_equal 'Team Members', format_class_name('Admin::Teams::TeamMembers')
  end

  test 'get_object_name for class' do
    assert_equal 'Maintenance Debt', get_object_name(Admin::MaintenanceDebt)
  end

  test 'get_object_name for objects with title properties' do
    user = FactoryBot.create(:user)
    assert_equal user.name, get_object_name(user)

    news = FactoryBot.create(:news)
    assert_equal news.title, get_object_name(news)

    mass_mail = FactoryBot.create(:draft_mass_mail)
    assert_equal mass_mail.subject, get_object_name(mass_mail)

    staffing = FactoryBot.create(:staffing)
    assert_equal staffing.show_title, get_object_name(staffing)
  end

  test 'get_object_name with reached default' do
    maintenance_debt = FactoryBot.create(:maintenance_debt)
    assert_equal 'Finbar the Viking', get_object_name(maintenance_debt, 'Finbar the Viking')

    assert_equal '', get_object_name(maintenance_debt, '')
  end

  test 'get_object_name with unreached default' do
    user = FactoryBot.create(:user)
    assert_equal user.name, get_object_name(user, 'Finbar the Viking')
  end

  test 'get_object_name with no title properties and no default' do
    maintenance_debt = FactoryBot.create(:maintenance_debt)
    assert_equal 'Maintenance Debt', get_object_name(maintenance_debt)
  end

  test 'get_object_name with class name' do
    venue = venues(:one)
    assert_equal "Venue '#{venue.name}'", get_object_name(venue, include_class_name: true)
  end

  test 'get_object_name with class name with "the"' do
    venue = venues(:one)
    assert_equal "the Venue '#{venue.name}'", get_object_name(venue, include_class_name: true, include_the: true)
  end
end
