##
# Controller for the about pages.
#
# No actions are defined here. It serves up the files in app/views/about/* using the app/views/layouts/about.html.erb layout.
##
class AboutController < ApplicationController
  before_filter :get_subpages

  def page
    render 'about/' + params[:page]
  end

  ##
  # Returns a list of all the pages in the about folder.
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
