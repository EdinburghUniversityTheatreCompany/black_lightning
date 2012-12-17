##
# Controller for the about pages.
#
# No actions are defined here. It serves up the files in app/views/about/* using the app/views/layouts/about.html.erb layout.
##
class AboutController < ApplicationController
  before_filter :get_subpages

  ##
  # Returns a list of all the pages in the about folder.
  ##
  def get_subpages
    @subpages_dir = "#{Rails.root}/app/views/about"

    @subpages = []

    exclude = ['index.html.erb']
    @alias = {
      'eutc' => 'EUTC'
    }

    Dir.foreach(@subpages_dir) do |file|
      if not File.directory?(File.join(@subpages_dir, file)) and not exclude.include? file then
        @subpages << file.gsub(/\.html\.erb/, "")
      end
    end
  end
end
