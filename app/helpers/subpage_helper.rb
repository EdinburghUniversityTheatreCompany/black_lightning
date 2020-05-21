module SubpageHelper
  def get_subpage_root_page(page)
    return '' if page == 'overview' || page.nil?

    return normalize_link(page)
  end

  # TODO: test that going to something like ball resources returns the standard list
  def get_subpages(root_folder, root_page) 
    root_folder = normalize_link(root_folder)
    root_page = normalize_link(root_page)

    subpages_dir = "#{Rails.root}/app/views/#{root_folder}/#{root_page}"

    subpages = []

    if File.directory?(subpages_dir)
      Dir.foreach(subpages_dir) do |file|
        unless File.directory?(File.join(subpages_dir, file))
          file = file.gsub(/\.html\.erb/, '')
          if root_page.present?
            subpages << "#{root_page}/#{file}"
          else
            subpages << file
          end
        end
      end
    else
      # If there is no folder, move one layer up when generating the subpages
      return get_subpages(root_folder, root_page.rpartition('/').first) if root_page.present?
    end

    # Those are included by default by the subpage_sidebar layout.
    subpages.delete('')
    subpages.delete('overview')

    return subpages
  end

  def get_subpage_link(page, controller)
    page = normalize_link(page)

    if page.downcase == 'overview' || page == ''
      return link_to 'Overview', controller: controller
    else
      @alias = {} if @alias.nil?
      return link_to @alias[page] || page.humanize.titleize, controller: controller, action: :page, page: page
    end
  end

  private

  def normalize_link(page)
    if page[0] == '/'
      page = page[1..page.size]
    end

    if page.last == '/'
      page = page[0..(page.size() - 2)]
    end

    # TODO: Once we're on Ruby 2.5/Rails 6
    #page.delete_prefix!('/')
    #page.delete_suffix!('/')
    return page.downcase
  end
end