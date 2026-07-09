module Reimbursements
  ##
  # Producer-facing reimbursements portal. Data lives in Airtable (via the
  # cache-fronted Store), not ActiveRecord, so CanCanCan has nothing to check:
  # every action is available to any signed-in member and scoped to their own
  # linked People record.
  class BaseController < ApplicationController
    before_action :authenticate_user!
    skip_authorization_check

    # Injection seams for functional tests (this suite has no mocking library).
    class_attribute :store_builder, default: -> { Store.new }
    class_attribute :extractor_builder, default: -> { Extractor.new }

    helper_method :current_person

    private

    def store
      @store ||= store_builder.call
    end

    def extractor
      @extractor ||= extractor_builder.call
    end

    def person_link
      @person_link ||= PersonLink.new(store: store)
    end

    def current_person
      return @current_person if defined?(@current_person)

      @current_person = person_link.person_for(current_user)
    end
  end
end
