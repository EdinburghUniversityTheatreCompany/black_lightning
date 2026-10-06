module Reimbursements
  ##
  # The record BackfillReimbursementsAreas#down needs to be reversible: which
  # area each budget was in, and whom that area named.
  #
  # The backfill re-homes a line from the "Area: Category" in its NAME, so a line
  # created in an area, moved there by hand or adopted by an import came back from
  # a rollback with its area gone. The owner gate went the same way:
  # seed_owners! seeds from the children's OWN owner rows, so an area whose only
  # owner-carrying line was unprefixed came back naming nobody, which switches
  # sign-off off for every line under it.
  #
  # Recorded rather than inferred, as AreaRename does: a rule reading the name
  # cannot tell a line the backfill homed from one a person moved. Recording the
  # owner list makes the reversal exact where seeding is an approximation.
  module AreaMembership
    # Raised, not skipped: a rollback that cannot record where the lines were
    # must not look like one with nothing to record.
    class MissingRecordError < StandardError; end

    RECORDED_COLUMN = "area_before_rollback".freeze

    # The area's identity, not its id: #down deletes the rows, so an id would
    # dangle. (name, cost_centre_id, financial_year_id) is what Area's uniqueness
    # and AreaBackfill's find_or_create treat as one area. Owners are numeric
    # Person ids, what sync_owner_ids! takes, not Person#record_id strings.
    def self.record!(scope: Budget.all)
      ensure_column!(scope)

      ActiveRecord::Base.transaction do
        scope.where.not(area_id: nil).includes(area: :area_ownerships).find_each do |budget|
          area = budget.area
          next if area.nil?

          budget.update_columns(RECORDED_COLUMN => recorded_for(area))
        end
      end
    end

    # Puts every recorded line back in its recorded area, including ones the
    # backfill already re-homed, which is how the OWNER list gets back onto an
    # area the backfill could only seed. The record is spent either way, so a
    # second rollback records afresh.
    def self.restore!(scope: Budget.all)
      ensure_column!(scope)

      ActiveRecord::Base.transaction do
        owner_ids_by_area_id = {}
        scope.where.not(RECORDED_COLUMN => nil).find_each do |budget|
          recorded = budget.read_attribute(RECORDED_COLUMN)
          # The RECORD, never the line's current area, which is the backfill's
          # name-based guess: for a hand-moved line the guess would land the
          # recorded owner list on another show, giving one show's sign-off to
          # another's owners. Idempotent where they agree (same triple).
          area = area_for(recorded)
          budget.update_columns(area_id: area.id, RECORDED_COLUMN => nil)
          owner_ids_by_area_id[area.id] = Array(recorded["owner_person_ids"])
        end
        restore_owners!(owner_ids_by_area_id)
      end
    end

    def self.recorded_for(area)
      { "name" => area.name,
        "cost_centre_id" => area.cost_centre_id,
        "financial_year_id" => area.financial_year_id,
        "owner_person_ids" => area.area_ownerships.map(&:person_id) }
    end
    private_class_method :recorded_for

    # find_or_create: the area may be gone, since the backfill recreates only
    # the areas some line's name reproduces.
    def self.area_for(recorded)
      Area.find_or_create_by!(name: recorded["name"],
                              cost_centre_id: recorded["cost_centre_id"],
                              financial_year_id: recorded["financial_year_id"])
    end
    private_class_method :area_for

    # The recorded list wins over AreaBackfill's seeding, even when EMPTY: an area
    # naming nobody is a real state, so the where.not(person_id: []) that
    # sync_owner_ids! compiles to is the answer here, not the trap.
    def self.restore_owners!(owner_ids_by_area_id)
      Area.where(id: owner_ids_by_area_id.keys).find_each do |area|
        area.sync_owner_ids!(owner_ids_by_area_id.fetch(area.id))
      end
    end
    private_class_method :restore_owners!

    # The live schema, not the memoized column list: one rollback run can revert
    # the migration that adds this column, then the one that reads it.
    def self.ensure_column!(scope)
      return if scope.model.connection.column_exists?(scope.model.table_name, RECORDED_COLUMN)

      raise MissingRecordError,
            "#{RECORDED_COLUMN} is gone, so which area each line was in cannot be recorded or " \
            "restored, so the backfill is no longer reversible"
    end
    private_class_method :ensure_column!
  end
end
