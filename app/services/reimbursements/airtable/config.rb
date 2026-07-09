module Reimbursements
  module Airtable
    ##
    # Airtable base/table/field identifiers for the reimbursements portal.
    #
    # Everything talks to Airtable by immutable field ID (never by field name)
    # so column renames in Airtable can't silently break the app — the same
    # convention bedlam-bacs uses. The IDs live in Rails credentials under
    # +reimbursements_airtable+, mirroring bedlam-bacs' field_ids.toml.
    class Config
      def self.from_credentials
        raw = Rails.application.credentials.reimbursements_airtable
        if raw.blank?
          raise "Missing reimbursements_airtable in Rails credentials " \
                "(base_id, tables, fields, status_options — see " \
                "docs/superpowers/specs/2026-07-09-reimbursements-setup-guide.md)"
        end
        new(raw)
      end

      def initialize(data)
        @data = data.to_h.deep_symbolize_keys.freeze
      end

      def base_id
        @data.fetch(:base_id)
      end

      def table_id(table)
        @data.fetch(:tables).fetch(table)
      end

      def fid(table, field)
        @data.fetch(:fields).fetch(table).fetch(field)
      end

      def status_label(status)
        @data.fetch(:status_options).fetch(status)
      end

      def field_name(table, field_id)
        @data.fetch(:fields).fetch(table).key(field_id)
      end
    end
  end
end
