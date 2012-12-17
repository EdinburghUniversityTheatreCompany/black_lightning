##
# Controller for the get_involved pages.
#
# No actions are defined here. It serves up the files in app/views/get_involved/* using the app/views/layouts/get_involved.html.erb layout.
##
class GetInvolvedController < ApplicationController
  before_filter :get_subpages

  ##
  # Returns a list of all the pages in the get_involved folder.
  ##
  def get_subpages
    @subpages_dir = "#{Rails.root}/app/views/get_involved"

    @subpages = []

    exclude = ['index.html.erb']
    @alias = {
      'ssw' => 'Stage, Set and Wardrobe'
    }

    Dir.foreach(@subpages_dir) do |file|
      if not File.directory?(File.join(@subpages_dir, file)) and not exclude.include? file then
        @subpages << file.gsub(/\.html\.erb/, "")
      end
    end
  end
end
