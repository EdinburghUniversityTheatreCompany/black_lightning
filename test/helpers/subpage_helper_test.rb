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
    # The ordering is tested at the same time.
    subpages = [
      FactoryBot.create(:editable_block, url: 'admin/resources',            ordering: 1),
      FactoryBot.create(:editable_block, url: 'admin/resources/ball',       ordering: 2),
      FactoryBot.create(:editable_block, url: 'admin/resources/producing',  ordering: 3),
      FactoryBot.create(:editable_block, url: 'admin/resources/tech',       ordering: 4),
    ]

    not_to_be_included_page       = FactoryBot.create(:editable_block, url: 'admin/resources/ball/support', ordering: 0)
    other_not_to_be_included_page = FactoryBot.create(:editable_block, url: 'admin/resources/tech/sound',   ordering: 6)

    assert_equal subpages.collect(&:url), get_subpages('admin/resources').collect(&:url)

    # Get the pages at the current layer when the page has no subpages.

    assert_equal subpages.collect(&:url), get_subpages('admin/resources/producing').collect(&:url)
  end

  test 'get subpages when deeper' do
    subpages = [
      FactoryBot.create(:editable_block, url: 'admin/resources',                  ordering: 3),
      FactoryBot.create(:editable_block, url: 'admin/resources/tech',             ordering: 5),
      # Should be able to be lower, as it is on a different layer.
      FactoryBot.create(:editable_block, url: 'admin/resources/tech/lighting',    ordering: 1),
      FactoryBot.create(:editable_block, url: 'admin/resources/tech/projections', ordering: 2),
      FactoryBot.create(:editable_block, url: 'admin/resources/tech/sound',       ordering: 3),
    ]

    not_to_be_included_page       = FactoryBot.create(:editable_block, url: 'admin/resources/ball', ordering: 2)
    other_not_to_be_included_page = FactoryBot.create(:editable_block, url: 'admin/resources/tech/sound/assistants', ordering: -1)

    assert_equal subpages.collect(&:url), get_subpages('admin/resources/tech/lighting').collect(&:url)
  end

  test 'get subpage link with link_to' do
    root_folder = 'admin/resources'

    overview = FactoryBot.create(:editable_block, url: root_folder)

    generated_link = get_subpage_link(root_folder, overview)

    assert_equal link_to(overview.name, admin_resources_index_path), generated_link
    assert_equal link_to(overview.name, admin_resources_path), generated_link
    assert_equal link_to(overview.name, admin_resources_path('')), generated_link
  end

  test 'get subpage link for pages' do
    root_folder = 'admin/resources'

    secretary = FactoryBot.create(:editable_block, url: root_folder + '/secretary')
    overview = FactoryBot.create(:editable_block, url: root_folder)

    assert_equal "<a href=\"/admin/resources/secretary\">#{secretary.name}</a>", get_subpage_link(root_folder, secretary)
    assert_equal "<a href=\"/admin/resources\">#{overview.name}</a>", get_subpage_link(root_folder, overview)
    assert_equal "<a href=\"/admin/resources\">#{overview.name}</a>", get_subpage_link(root_folder, overview)
  end

  test 'get subpage_link for external links' do
    root_folder = 'admin/resources'

    url = 'https://wiki.bedlamtheatre.co.uk'
    
    external_link = FactoryBot.create(:editable_block, url: root_folder + '/wiki', content: "EXTERNAL_URL:     #{url}   ")
    this_should_not_cause_an_error = FactoryBot.create(:editable_block, url: root_folder + '/something')
  
    assert_equal "<a href=\"#{url}\">#{external_link.name}</a>", get_subpage_link(root_folder, external_link)
  end
end
