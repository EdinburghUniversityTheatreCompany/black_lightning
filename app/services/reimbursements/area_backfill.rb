module Reimbursements
  ##
  # One-off: give the budgets whose names already read "Area: Category" a real
  # area. Fringe wrote the grouping into 17 of its 31 budget names; the other 14
  # are standalone overheads and are left alone.
  #
  # A service, not migration code: test databases are schema-loaded, so a data
  # migration never runs there.
  module AreaBackfill
    NAME_PATTERN = /\A(?<area>[^:]+):\s*(?<category>.+)\z/

    # Idempotent: only budgets still without an area are touched, and owners are
    # seeded only for an area that has none yet.
    #
    # One transaction: MySQL gives migrations no DDL transaction, so a mid-run
    # failure could leave budgets homed to an area whose owners were never seeded,
    # silently switching its owner gate off.
    #
    # Returns the ids of the areas it CREATED, not ones it found: AreaMembership's
    # restore must tell a minted area from an existing one, because this keys on
    # the BUDGET's year and centre while the record keys on the AREA's, so a
    # restored line can leave the minted area empty.
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

    # An area with no owners silently drops its budgets' claims out of the owner
    # gate, the worst way to get this wrong. Seeds from the union of the children's
    # owners and KEEPS their rows so the backfill has a true reverse. Only the areas
    # THIS run touched: an area finance left ownerless elsewhere must stay that way.
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
