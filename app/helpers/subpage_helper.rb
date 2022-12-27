# This is all more convoluted than it should be. Not sure how to fix it unfortunately while keeping the nesting intact.

# This is all going to be somewhat outdated with the summer 2022 Bootstrap redesign, but I will only remove things after it's been completed. ~ Mick
module SubpageHelper
  EXTERNAL_URL_PREFIX = 'EXTERNAL_URL:'

  def get_subpage_root_url(root_folder, root_page)
    root_page = '' if root_page == 'overview' || root_page.nil?

    root_folder = strip_url(root_folder)
    root_page = strip_url(root_page)

    root_url = root_page == '' ? root_folder : "#{root_folder}/#{root_page}"
    
    return strip_url(root_url).downcase
  end

  def strip_url(url)
    return url.delete_prefix('/').delete_suffix('/')
  end

  def get_subpage_editable_blocks(subpage_type)
    subpage_editable_blocks = Admin::EditableBlock.where('url LIKE ?', "#{subpage_type}%")
    # Organise according to ordering, and if those are equal, alphabetically.
    # Reject the subpages that are further than one layer deep.
    # Example: (about/tree -> tree -> does not contain a / so is kept) (about/tree/apple -> tree/apple -> contains a / so is rejected)
    return subpage_editable_blocks.order(:ordering, :name).reject { |editable_block| editable_block.url.count('/') > subpage_type.count('/') + 1 }
  end

  # Get the children for the public front-end navbar, with subpage_type being about, get_involved or archives
  def get_navbar_children(subpage_type)
    # Collect the blocks into a has with title and path.
    # If the item links to an external url, set that as the path, otherwise just set the path to the editable block path
    # We need to add a / to the path to make it absolute to the root url (bedlamtheatre.co.uk) rather than relative to the current page url.
    return get_subpage_editable_blocks(subpage_type).collect { |eb| { title: eb.name, path: eb.content&.start_with?(EXTERNAL_URL_PREFIX) ? eb.content.sub(EXTERNAL_URL_PREFIX, '').strip : "/#{eb.url}" } }
  end
end
