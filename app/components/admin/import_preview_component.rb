# The review step of a bulk import (users, members, an event's crew): a Cancel button, the row
# count, and the form that posts each row's decision to confirm. The sections go in as the block.
class Admin::ImportPreviewComponent < ViewComponent::Base
  # event_name: the event a crew import adds to, named in the row count.
  def initialize(total:, cancel_path:, confirm_path:, cache_key:, event_name: nil)
    @total = total
    @cancel_path = cancel_path
    @confirm_path = confirm_path
    @cache_key = cache_key
    @event_name = event_name
  end
end
