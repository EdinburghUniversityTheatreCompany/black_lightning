##
# Controller for the get_involved pages.
#
# No actions are defined here. It serves up the files in app/views/get_involved/* using the app/views/layouts/get_involved.html.erb layout.
##
class GetInvolvedController < ApplicationController
  before_filter :get_subpages

  def opportunities
    @opportunities = Opportunity.where({ approved: true }).all
  end

  private
  ##
  # Returns a list of all the pages in the get_involved folder.
  ##
  def get_subpages
    action = params[:action]

    action_sections = action.split("/")

    @root_page = action_sections[0]

    @subpages_dir = "#{Rails.root}/app/views/get_involved/#{@root_page}"

    @subpages = []

    exclude = ['index.html.erb']
    @alias = {
      'ssw' => 'Stage, Set and Wardrobe'
    }

    if not File.directory?(@subpages_dir) then
      @subpages_dir = "#{Rails.root}/app/views/get_involved/"
      @root_page = nil
    end

    Dir.foreach(@subpages_dir) do |file|
      if not File.directory?(File.join(@subpages_dir, file)) and not exclude.include? file then
        @subpages << file.gsub(/\.html\.erb/, "")
      end
    end
  end
end
