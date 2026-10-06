module Reimbursements
  ##
  # One-off: drop the "Area: " prefix from the budgets Phase 1's backfill homed,
  # now the area holds the grouping. "Cogito: Marketing" under area Cogito
  # becomes "Marketing".
  #
  # The prefix rule IS BudgetImport.bare_name, not a second regexp: what is
  # stripped and what is matched must be one rule, or a one-space drift buckets a
  # revision as a create and splits a show's spend across two lines.
  module AreaRename
    # Raised, not written: the pair would be one line to every reader and to the
    # importer's matcher, with nothing to say two rows went in.
    class CollisionError < StandardError; end

    # The recording column is gone (Phase 2b drops it). Raised, not skipped:
    # skipping makes a rollback that cannot restore the names look like one that did.
    class MissingRecordError < StandardError; end

    RECORDED_COLUMN = "name_before_area_rename".freeze

    # Idempotent: a second run finds the names already bare.
    def self.strip!(scope: Budget.all)
      ActiveRecord::Base.transaction do
        renames = planned_renames(scope)
        refuse_collisions!(renames, scope)
        # update_columns, never update!: a bookkeeping rename must not be vetoed by
        # an unrelated validation, nor fire Budget#inherit_area_scoping, which
        # would stamp an unstamped legacy line with its area's year and centre.
        renames.each do |budget, bare|
          budget.update_columns(name: bare, name_before_area_rename: budget.name)
        end
      end
    end

    # Byte-for-byte, and ONLY rows #strip! recorded that still carry the name it
    # left. Restoring by RULE would re-prefix lines the strip refused to touch,
    # making every area reproducible from its budgets and so disarming
    # BackfillReimbursementsAreas#down's refusal: a guard turned into a silent
    # delete of areas and their owners. It also lets a line finance has since
    # renamed keep its name.
    def self.restore!(scope: Budget.all)
      # The live schema, not the memoized column list: one rollback run can revert
      # the migration that adds this column, then this one.
      unless scope.model.connection.column_exists?(scope.model.table_name, RECORDED_COLUMN)
        raise MissingRecordError, "#{RECORDED_COLUMN} is gone, so the names #strip! took off " \
                                  "cannot be restored: the rollback window closed when it was dropped"
      end

      ActiveRecord::Base.transaction do
        scope.where.not(RECORDED_COLUMN => nil).includes(:area).find_each do |budget|
          next unless restorable?(budget)

          budget.update_columns(name: budget.name_before_area_rename, name_before_area_rename: nil)
        end
      end
    end

    # Reads the RECORDED string, not the area's current name: reading the name
    # made a renamed area skip, destroying its record one statement before the
    # column is dropped.
    def self.restorable?(budget)
      budget.area && budget.name == budget.name_before_area_rename.to_s.partition(":").last.strip
    end
    private_class_method :restorable?

    def self.planned_renames(scope)
      scope.where.not(area_id: nil).includes(:area).filter_map do |budget|
        area = budget.area
        next if area.nil? || area.name.blank?

        bare = BudgetImport.bare_name(budget.name, area.name)
        [ budget, bare ] unless bare == budget.name
      end
    end
    private_class_method :planned_renames

    # Refuses only a collision this run would CREATE; one already there is not
    # this rename's doing and would block it on data it cannot fix.
    def self.refuse_collisions!(renames, scope)
      bare_by_id = renames.to_h { |budget, bare| [ budget.id, bare ] }
      finals = scope.where.not(area_id: nil).map do |budget|
        [ budget, bare_by_id.fetch(budget.id, budget.name) ]
      end

      clashes = finals.group_by { |budget, final| [ budget.area_id, BudgetImport.match_key(final) ] }
                      .values
                      .select { |group| group.size > 1 && group.any? { |budget, _| bare_by_id.key?(budget.id) } }
      return if clashes.empty?

      raise CollisionError, collision_message(clashes)
    end
    private_class_method :refuse_collisions!

    def self.collision_message(clashes)
      pairs = clashes.map do |group|
        group.map { |budget, final| "#{budget.name.inspect} -> #{final.inspect}" }
             .join(" and ")
      end
      "stripping the area prefix would leave two lines in one area with the same name " \
        "(#{pairs.join('; ')}). Rename one of them before migrating"
    end
    private_class_method :collision_message
  end
end
