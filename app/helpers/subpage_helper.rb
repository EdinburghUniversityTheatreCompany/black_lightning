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

  def get_subpages(root_url)
    root_url = strip_url(root_url)
     
    subpages = []

    # Add the current and all higher layers to the subpages (tech, tech/lightning and tech/lightning/design when you are currently at tech/lighting/design)
    temporary_root_url = root_url

    while temporary_root_url.present?
      editable_block = Admin::EditableBlock.find_by(url: temporary_root_url)
      subpages << editable_block if editable_block.present?
      temporary_root_url = temporary_root_url.rpartition('/').first
    end

    # The most top-level page should be at the top.
    subpages.reverse!

    subpage_editable_blocks = Admin::EditableBlock.where('url LIKE ?', "#{root_url}%")

    subpage_editable_blocks = subpage_editable_blocks.order(:ordering, :name).reject { |editable_block| editable_block.url.sub("#{root_url}/", '').include?('/') }

    if subpage_editable_blocks.any?
      subpages += subpage_editable_blocks
    elsif root_url.present?
      # If there are no subpages, move one layer up when generating the subpages.
      return get_subpages(root_url.rpartition('/').first)
    end

    return subpages.uniq
  end

  def get_subpage_link(controller, page, active)
    link_to page.name, get_subpage_url(controller, page), class: "nav-link #{'active' if active}"
  end

  def get_subpage_url(controller, page)
    if page.content.present? && page.content.start_with?(EXTERNAL_URL_PREFIX)
      page_url = page.content.sub(EXTERNAL_URL_PREFIX, '').strip

      return page_url
    else
      page_url = page.url.sub(controller, '')
      page_url.delete_prefix!('/')

      return url_for({ controller: controller, action: :page, page: page_url })
    end
  end

  def strip_url(url)
    return url.delete_prefix('/').delete_suffix('/')
  end

  # Get the children for the public front-end navbar, with subpage_type being about, get_involved or archives
  def get_navbar_children(subpage_type)
    subpage_editable_blocks = Admin::EditableBlock.where('url LIKE ?', "#{subpage_type}%")
    # Organise according to ordering, and if those are equal, alphabetically.
    # Reject the subpages that are further than one layer deep.
    # Example: (about/tree -> tree -> does not contain a / so is kept) (about/tree/apple -> tree/apple -> contains a / so is rejected)
    subpage_editable_blocks = subpage_editable_blocks.order(:ordering, :name).reject { |editable_block| editable_block.url.sub("#{subpage_type}/", '').include?('/') }

    # Collect the blocks into a has with title and path.
    # If the item links to an external url, set that as the path, otherwise just set the path to the editable block path
    return subpage_editable_blocks.collect { |eb| { title: eb.name, path: eb.content&.start_with?(EXTERNAL_URL_PREFIX) ? eb.content.sub(EXTERNAL_URL_PREFIX, '').strip : eb.url } }
  end
end
