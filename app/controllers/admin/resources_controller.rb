class Admin::ResourcesController < AdminController
  before_action :get_subpages

  layout 'admin/resources'

  def page
    render 'admin/resources/' + params[:page]
  end

  def get_subpages
    page = params[:page]

    action_sections = page.split('/')

    @root_page = action_sections[0]

    subpages_dir = "#{Rails.root}/app/views/admin/resources/#{@root_page}/"

    @subpages = []

    if File.directory?(subpages_dir)
      Dir.foreach(subpages_dir) do |file|
        unless File.directory?(File.join(subpages_dir, file))
          @subpages << file.gsub(/\.html\.erb/, '')
        end
      end
    end
  end
end
