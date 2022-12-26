##
# Controller for the get_involved pages.
#
# The pages are all defined as Editable Blocks.
##
class GetInvolvedController < ApplicationController
  skip_authorization_check

  def opportunities
    @opportunities = Opportunity.active

    @editable_block = Admin::EditableBlock.find_by(url: 'get_involved/opportunities')
  end

  def page
    @editable_block = Admin::EditableBlock.find_by!(url: @current_path.delete_prefix('/'))
  end
end
