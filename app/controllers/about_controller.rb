##
# Controller for the about pages.
#
# No actions are defined here. It serves up the files in app/views/about/* using the app/views/layouts/about.html.erb layout.
##
class AboutController < ApplicationController
  before_action :get_subpages

  def page
    begin
      render 'about/' + params[:page]
    rescue ActionView::MissingTemplate
      redirect_to '404', status: 404
    end
  end

  ##
  # Returns a list of all the pages in the about folder.
  # This is used by the about layout page to render the navigation.
  ##
  def get_subpages
    action = params[:page] || ''

    action_sections = action.split('/')

    @root_page = action_sections[0]

    @subpages_dir = "#{Rails.root}/app/views/about/#{@root_page}/"

    @subpages = []

    exclude = ['index.html.erb']
    @alias = {
      'eutc' => 'EUTC'
    }

    unless File.directory?(@subpages_dir)
      @subpages_dir = "#{Rails.root}/app/views/about/"
      @root_page = nil
    end

    Dir.foreach(@subpages_dir) do |file|
      if !File.directory?(File.join(@subpages_dir, file)) and !exclude.include? file
        @subpages << file.gsub(/\.html\.erb/, '')
      end
    end
  end
end
