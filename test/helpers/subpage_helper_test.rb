require 'test_helper'

class SubpageHelperTest < ActionView::TestCase
  test 'get subpage root page' do
    assert_equal '', get_subpage_root_page('overview')
    assert_equal '', get_subpage_root_page(nil)
    assert_equal '', get_subpage_root_page('')
    assert_equal '', get_subpage_root_page('/')
    assert_equal 'secretary', get_subpage_root_page('secretary')
    assert_equal 'secretary', get_subpage_root_page('secretary/')
    assert_equal 'secretary', get_subpage_root_page('/secretary/')
    assert_equal 'secretary/minutes', get_subpage_root_page('secretary/minutes')
    assert_equal 'secretary/minutes', get_subpage_root_page('secretary/minutes/')
    assert_equal 'pineapple/hexagon/viking', get_subpage_root_page('pineapple/hexagon/viking')
  end

  test 'get subpages at root' do
    subpages = [
      'archive', 'ball', 'business', 'constitution_and_production_guidelines',
      'library', 'marketing', 'membership_checker', 'miscellaneous', 'production_schedule',
      'secretary', 'stage_set_and_wardrobe', 'tech'
    ]

    assert_equal subpages, get_subpages('/admin/resources/', '')
  end

  test 'get subpages at something without nesting' do
    subpages = [
      'archive', 'ball', 'business', 'constitution_and_production_guidelines',
      'library', 'marketing', 'membership_checker', 'miscellaneous', 'production_schedule',
      'secretary', 'stage_set_and_wardrobe', 'tech'
    ]

    assert_equal subpages, get_subpages('admin/resources', 'ball')
  end

  test 'will include the parent when two layers deep' do
    # For example, tech, tech/lighting & tech/sound when you're at tech/lighting.
    subpages = %w[tech tech/lighting tech/projection tech/sound]

    assert_equal subpages, get_subpages('admin/resources', 'tech/lighting')
  end

  # Tests if the link can handle differently styled page names
  test 'get subpages at secretary' do
    subpages = %w[secretary secretary/current_minutes secretary/minutes_archive secretary/miscellaneous secretary/rehearsal_schedules]

    root_folder = 'admin/resources/'

    assert_equal subpages, get_subpages(root_folder, 'secretary')
    assert_equal subpages, get_subpages(root_folder, '/Secretary/')
    assert_equal subpages, get_subpages(root_folder, '/seCretAry')
    assert_equal subpages, get_subpages(root_folder, 'secretary/')
  end

  test 'get subpage link' do
    assert_equal link_to('Act', get_involved_path('act')), get_subpage_link('act', 'get_involved')
    assert_equal link_to('Overview', about_index_path), get_subpage_link('', 'about')
    assert_equal link_to('Overview', admin_resources_path), get_subpage_link('overview', '/admin/resources')
  end

  test 'get subpage link for resources' do
    root_folder = '/admin/resources'
    assert_equal '<a href="/admin/resources/secretary">Secretary</a>', get_subpage_link('/secretary', root_folder)
    assert_equal '<a href="/admin/resources/secretary/minutes">Secretary/Minutes</a>', get_subpage_link('secretary/minutes/', root_folder)
    assert_equal '<a href="/admin/resources">Overview</a>', get_subpage_link('', root_folder)
    assert_equal '<a href="/admin/resources">Overview</a>', get_subpage_link('OVerVieW', root_folder)
  end
end
