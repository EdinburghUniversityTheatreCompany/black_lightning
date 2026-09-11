module Reimbursements
  ##
  # The record BackfillReimbursementsAreas#down needs in order to be reversible:
  # which area each budget was in, and whom that area named.
  #
  # The backfill re-homes a line by reading "Area: Category" out of its NAME, so
  # a line that never carried that prefix — one created inside an area, moved
  # there by hand, or adopted by a spreadsheet import — came back from a
  # rollback with its name intact and its area_id gone, and re-migrating did not
  # put it back. Nothing said so. The area's owner gate rode on the same loss:
  # AreaBackfill#seed_owners! seeds an area from its children's OWN owner rows,
  # so an area whose only owner-carrying line was the unprefixed one came back
  # naming nobody — which switches sign-off off for every line under it.
  #
  # RECORDING rather than inferring, the shape AreaRename uses for names and for
  # the same reason: a rule reading the name cannot tell a line the backfill
  # homed from one a person moved, so it would either re-home the wrong lines or
  # refuse a rollback over ordinary finance work. Recording the owner list makes
  # the reversal exact as well: seeding from the children is an approximation
  # that loses whatever finance edited on the area itself.
  #
  # A SERVICE rather than migration code, for AreaBackfill's reason: test and CI
  # databases are schema-loaded, so a data migration never runs there and could
  # never be tested.
  module AreaMembership
    # Raised rather than skipped: a rollback that CANNOT record where the lines
    # were must not look like one that had nothing to record.
    class MissingRecordError < StandardError; end

    RECORDED_COLUMN = "area_before_rollback".freeze

    # The area's own identity, not its id: #down deletes the rows, so an id
    # would dangle. (name, cost_centre_id, financial_year_id) is what Area's
    # uniqueness validation treats as one area, and what AreaBackfill keys its
    # find_or_create on. Owners are numeric Person ids, what sync_owner_ids!
    # takes — not Person#record_id, which is a string.
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

    # Puts every recorded line back in the area it was in — the ones the
    # backfill has already re-homed from their names included, which is how the
    # OWNER list gets back onto an area the backfill could only seed from its
    # children. The record is spent either way, so a second rollback records
    # afresh rather than restoring from a stale one.
    def self.restore!(scope: Budget.all)
      ensure_column!(scope)

      ActiveRecord::Base.transaction do
        owner_ids_by_area_id = {}
        scope.where.not(RECORDED_COLUMN => nil).find_each do |budget|
          recorded = budget.read_attribute(RECORDED_COLUMN)
          # The RECORD, never the area the line currently holds: that one is
          # AreaBackfill's name-based guess, and where the two disagree —
          # exactly the hand-move this record exists for — the guess decides
          # which area the recorded OWNER list lands on. One show's sign-off
          # then comes back naming another show's owners, which is worse than
          # either failure the record prevents. Idempotent where they agree,
          # since #area_for keys on the same triple.
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

    # find_or_create, because the area may be gone: the backfill recreates only
    # the areas some line's NAME reproduces, and the recorded triple is the
    # whole identity of the one this line was in.
    def self.area_for(recorded)
      Area.find_or_create_by!(name: recorded["name"],
                              cost_centre_id: recorded["cost_centre_id"],
                              financial_year_id: recorded["financial_year_id"])
    end
    private_class_method :area_for

    # The recorded list is what the area named before the rollback, so it wins
    # over AreaBackfill's seeding. Including when it is EMPTY: an area that
    # named nobody is a real state (its lines skip sign-off entirely), so here
    # the where.not(person_id: []) that sync_owner_ids! compiles to is the
    # answer rather than the trap.
    def self.restore_owners!(owner_ids_by_area_id)
      Area.where(id: owner_ids_by_area_id.keys).find_each do |area|
        area.sync_owner_ids!(owner_ids_by_area_id.fetch(area.id))
      end
    end
    private_class_method :restore_owners!

    # The LIVE schema, not the memoized column list: one rollback run can revert
    # the migration that adds this column and then the one that reads it.
    def self.ensure_column!(scope)
      return if scope.model.connection.column_exists?(scope.model.table_name, RECORDED_COLUMN)

      raise MissingRecordError,
            "#{RECORDED_COLUMN} is gone, so which area each line was in cannot be recorded or " \
            "restored — the backfill is no longer reversible"
    end
    private_class_method :ensure_column!
  end
end
