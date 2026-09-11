module Reimbursements
  ##
  # One-off: give the budgets whose names already read "Area: Category" a real
  # area. Fringe wrote the grouping into 17 of its 31 budget names; the other 14
  # are genuine standalone overheads and are left alone.
  #
  # A SERVICE rather than migration code, because test and CI databases are
  # schema-loaded, so a data migration never runs there and could never be
  # tested.
  module AreaBackfill
    NAME_PATTERN = /\A(?<area>[^:]+):\s*(?<category>.+)\z/

    # Idempotent: a second run touches only budgets still without an area (the
    # scope excludes anything already homed, this run or an earlier one) and
    # only seeds owners for an area that has none yet.
    #
    # One transaction: MySQL gives migrations no automatic DDL transaction, so
    # without it a mid-run exception could leave budgets homed to an area whose
    # owners were never seeded — silently breaking that area's owner gate with
    # nothing on screen to explain it.
    #
    # Returns the ids of the areas it CREATED, never the ones it merely found:
    # a caller re-homing lines afterwards has to tell one this run minted from
    # one that was already there. AreaMembership's restore is such a caller —
    # this keys on the BUDGET's year and centre while the record keys on the
    # AREA's, so a line restored to its recorded area can leave the one created
    # here holding nothing at all.
    def self.run!(scope: Budget.all)
      created_ids = []
      ActiveRecord::Base.transaction do
        area_ids = []

        scope.where(area_id: nil).find_each do |budget|
          match = NAME_PATTERN.match(budget.name.to_s)
          next if match.nil?

          area = find_or_create_area(budget, match[:area].strip)
          created_ids << area.id if area.previously_new_record?
          budget.update_column(:area_id, area.id)
          area_ids << area.id
        end

        seed_owners!(area_ids.uniq)
      end
      created_ids.uniq
    end

    def self.find_or_create_area(budget, name)
      Area.find_or_create_by!(name: name,
                              cost_centre_id: budget.cost_centre_id,
                              financial_year_id: budget.financial_year_id)
    end
    private_class_method :find_or_create_area

    # An area with no owners means its budgets' claims silently stop hitting the
    # owner gate — the worst way to get this wrong. Seed from the union of the
    # children's, and KEEP their rows so the backfill has a true reverse.
    #
    # Scoped to the areas THIS run actually touched — run!(scope:) exists so a
    # cost-centre-only backfill is possible, and seeding every area regardless
    # would reach outside that caller's intent.
    def self.seed_owners!(area_ids)
      return if area_ids.empty?

      Area.where(id: area_ids).includes(budgets: :own_owners).find_each do |area|
        next if area.owner_ids.any?

        person_ids = area.budgets.flat_map { |b| b.own_owners.map(&:id) }.uniq
        area.sync_owner_ids!(person_ids) if person_ids.any?
      end
    end
    private_class_method :seed_owners!
  end
end
