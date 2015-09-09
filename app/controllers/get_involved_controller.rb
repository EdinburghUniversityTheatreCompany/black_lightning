##
# Controller for the get_involved pages.
#
# No actions are defined here. It serves up the files in app/views/get_involved/* using the app/views/layouts/get_involved.html.erb layout.
##
class GetInvolvedController < ApplicationController
  before_filter :get_subpages

  def opportunities
    @opportunities = Opportunity.approved.all
  end

  def page
    render 'get_involved/' + params[:page]
  end

  private

  ##
  # Returns a list of all the pages in the get_involved folder.
  ##
  def get_subpages
    action = params[:page]

    action_sections = action.split('/')

    @root_page = action_sections[0]

    @subpages_dir = "#{Rails.root}/app/views/get_involved/#{@root_page}"

    @subpages = []

    exclude = ['index.html.erb']
    @alias = {
      'ssw' => 'Stage, Set and Wardrobe'
    }

    unless File.directory?(@subpages_dir)
      @subpages_dir = "#{Rails.root}/app/views/get_involved/"
      @root_page = nil
    end

    Dir.foreach(@subpages_dir) do |file|
      if !File.directory?(File.join(@subpages_dir, file)) and !exclude.include? file
        @subpages << file.gsub(/\.html\.erb/, '')
      end
    end
  end
end
