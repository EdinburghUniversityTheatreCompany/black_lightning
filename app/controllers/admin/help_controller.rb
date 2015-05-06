##
# Controller for help files for the administration site.
#
# Views should be located in app/views/admin/help. Please also define a method here (even if it is empty) to keep track of these files.
#
# Note that there is currently no help index file. If it becomes necessary to write a significant number of help files, it may be worth making one.
##
class Admin::HelpController < AdminController
  ##
  # GET /admin/help/markdown
  ##
  def kramdown
    @title = 'kramdown Help'

    respond_to do |format|
      format.html # index.html.erb
      format.text do
        render inline: IO.read("#{Rails.root}/app/views/admin/help/kramdown.html.md")
      end
    end
  end

  ##
  # GET /admin/help/venue_location
  ##
  def venue_location
    @title = 'Venue Location Help'
  end
end
