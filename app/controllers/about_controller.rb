##
# Controller for the about pages.
##
class AboutController < ApplicationController
  include EditableBlockPage

  skip_authorization_check
end
