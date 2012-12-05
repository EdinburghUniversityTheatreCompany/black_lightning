class Admin::ResourcesController < AdminController
  before_filter :get_subpages

  layout "admin/resources"

  def get_subpages
    action = params[:action]

    action_sections = action.split("/")

    @root_page = action_sections[0]

    subpages_dir = "#{Rails.root}/app/views/admin/resources/#{@root_page}/"

    @subpages = []

    if File.directory?(subpages_dir) then
      Dir.foreach(subpages_dir) do |file|
        if not File.directory?(File.join(subpages_dir, file)) then
          @subpages << file.gsub(/\.html\.erb/, "")
        end
      end
    end
  end
end
