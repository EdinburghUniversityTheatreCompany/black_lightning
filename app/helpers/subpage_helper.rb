module SubpageHelper
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

    subpage_editable_blocks = subpage_editable_blocks.order(:ordering, :url).select { |editable_block| !editable_block.url.sub("#{root_url}/", '').include?('/') }

    if subpage_editable_blocks.any?
      subpages += subpage_editable_blocks
    elsif root_url.present?
      # If there are no subpages, move one layer up when generating the subpages. 
      return get_subpages(root_url.rpartition('/').first)
    end

    return subpages.uniq
  end

  def get_subpage_link(controller, page)
    page_url = page.url.sub(controller, '')
    page_url.delete_prefix!('/')

    return link_to page.name, controller: controller, action: :page, page: page_url
  end

  def strip_url(url)
    return url.delete_prefix('/').delete_suffix('/')
  end
end
