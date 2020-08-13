require 'test_helper'

class SubpageHelperTest < ActionView::TestCase
  test 'get subpage root page' do
    assert_equal 'about', get_subpage_root_url('about', 'overview')
    assert_equal 'about', get_subpage_root_url('about', nil)
    assert_equal 'about', get_subpage_root_url('about', '')
    assert_equal 'about', get_subpage_root_url('about/', '/')
    assert_equal 'about/secretary', get_subpage_root_url('about', 'secretary')
    assert_equal 'about/secretary', get_subpage_root_url('about', 'secretary/')
    assert_equal 'about/secretary', get_subpage_root_url('about', '/secretary/')
    assert_equal 'about/secretary/minutes', get_subpage_root_url('about', 'secretary/minutes')
    assert_equal 'about/secretary/minutes', get_subpage_root_url('about', 'secretary/minutes/')
    assert_equal 'about/pineapple/hexagon/viking', get_subpage_root_url('about', 'pineapple/hexagon/viking')
  end

  test 'get subpages at root' do
    subpages = [
      FactoryBot.create(:editable_block, url: 'admin/resources'),
      FactoryBot.create(:editable_block, url: 'admin/resources/ball'),
      FactoryBot.create(:editable_block, url: 'admin/resources/producing'),
      FactoryBot.create(:editable_block, url: 'admin/resources/tech'),
    ]

    not_to_be_included_page       = FactoryBot.create(:editable_block, url: 'admin/resources/ball/support')
    other_not_to_be_included_page = FactoryBot.create(:editable_block, url: 'admin/resources/tech/sound')

    assert_equal subpages, get_subpages('admin/resources')

    # Get the pages at the current layer when the page has no subpages.

    assert_equal subpages, get_subpages('admin/resources/producing')
  end

  test 'get subpages when deeper' do
    subpages = [
      FactoryBot.create(:editable_block, url: 'admin/resources'),
      FactoryBot.create(:editable_block, url: 'admin/resources/tech'),
      FactoryBot.create(:editable_block, url: 'admin/resources/tech/lighting'),
      FactoryBot.create(:editable_block, url: 'admin/resources/tech/projections'),
      FactoryBot.create(:editable_block, url: 'admin/resources/tech/sound'),
    ]

    not_to_be_included_page       = FactoryBot.create(:editable_block, url: 'admin/resources/ball')
    other_not_to_be_included_page = FactoryBot.create(:editable_block, url: 'admin/resources/tech/sound/assistants')

    assert_equal subpages, get_subpages('admin/resources/tech/lighting')
  end

  test 'get subpage link with link_to' do
    root_folder = 'admin/resources'

    overview = FactoryBot.create(:editable_block, url: root_folder)

    generated_link = get_subpage_link(root_folder, overview)

    assert_equal link_to(overview.name, admin_resources_index_path), generated_link
    assert_equal link_to(overview.name, admin_resources_path), generated_link
    assert_equal link_to(overview.name, admin_resources_path('')), generated_link
  end

  test 'get subpage link' do
    root_folder = 'admin/resources'

    secretary = FactoryBot.create(:editable_block, url: root_folder + '/secretary')
    overview = FactoryBot.create(:editable_block, url: root_folder)

    assert_equal "<a href=\"/admin/resources/secretary\">#{secretary.name}</a>", get_subpage_link(root_folder, secretary)
    assert_equal "<a href=\"/admin/resources\">#{overview.name}</a>", get_subpage_link(root_folder, overview)
    assert_equal "<a href=\"/admin/resources\">#{overview.name}</a>", get_subpage_link(root_folder, overview)
  end
end
