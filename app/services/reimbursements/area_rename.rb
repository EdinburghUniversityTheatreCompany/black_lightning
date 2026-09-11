module Reimbursements
  ##
  # One-off: drop the "Area: " prefix from the budgets Phase 1's backfill homed,
  # now that the grouping lives in the area rather than in a naming convention.
  # "Cogito: Marketing" under area Cogito becomes "Marketing".
  #
  # A SERVICE rather than migration code, for AreaBackfill's reason: test and CI
  # databases are schema-loaded, so a data migration never runs there and could
  # never be tested.
  #
  # THE PREFIX RULE IS BudgetImport.bare_name, not a second regexp here. The
  # importer has to read both spellings of every line for as long as any
  # committee's sheet still writes the prefix, so the rule that decides what is
  # stripped and the rule that decides what matches are the same rule — two
  # copies that drift by a space or a capital would bucket a revision as a
  # create and split a show's spend across two lines.
  module AreaRename
    # Two lines in one area that #strip! would leave with the same name. Raised
    # rather than written: the pair is then one line to every reader and to the
    # importer's matcher, with nothing on screen to say two rows went in.
    class CollisionError < StandardError; end

    # reimbursements_budgets.name_before_area_rename is gone — Phase 2b drops it
    # once the rollback window closes. Raised rather than skipped: skipping
    # would turn a rollback that CAN'T restore the names into one that silently
    # doesn't.
    class MissingRecordError < StandardError; end

    RECORDED_COLUMN = "name_before_area_rename".freeze

    # Idempotent: a second run finds the names already bare. One transaction, as
    # AreaBackfill's is.
    def self.strip!(scope: Budget.all)
      ActiveRecord::Base.transaction do
        renames = planned_renames(scope)
        refuse_collisions!(renames, scope)
        renames.each do |budget, bare|
          budget.update_columns(name: bare, name_before_area_rename: budget.name)
        end
      end
    end

    # Byte-for-byte, and ONLY the rows #strip! recorded that still carry the name
    # it left them. Restoring by rule instead re-prefixes lines the strip
    # refused to touch, which makes every area reproducible from its budgets and
    # so disarms BackfillReimbursementsAreas#down's refusal — turning a guard
    # against unwinding a hand-edited area tree into a silent delete of areas
    # and their owner rows. A line finance has renamed since keeps the name
    # finance gave it, which is what recording the string rather than a rule
    # buys: the rule cannot tell "Publicity" from a name it never touched.
    def self.restore!(scope: Budget.all)
      # Asked of the live schema, not of the memoized column list: one rollback
      # run can revert the migration that re-adds this column and then this one.
      unless scope.model.connection.column_exists?(scope.model.table_name, RECORDED_COLUMN)
        raise MissingRecordError, "#{RECORDED_COLUMN} is gone, so the names #strip! took off " \
                                  "cannot be restored — the rollback window closed when it was dropped"
      end

      ActiveRecord::Base.transaction do
        scope.where.not(RECORDED_COLUMN => nil).includes(:area).find_each do |budget|
          next unless restorable?(budget)

          budget.update_columns(name: budget.name_before_area_rename, name_before_area_rename: nil)
        end
      end
    end

    # Is the name still the one #strip! left, and is there still an area for the
    # prefix to name? Read off the RECORDED string — the same tail #bare_name
    # takes — and never off the area's CURRENT name: doing that made a renamed
    # area skip and destroy its record one statement before the column is
    # dropped, while restoring there could not have disarmed anything.
    def self.restorable?(budget)
      budget.area && budget.name == budget.name_before_area_rename.to_s.partition(":").last.strip
    end
    private_class_method :restorable?

    # [[budget, bare name]] for every line whose name carries its own area's
    # prefix. update_columns, never update!: a bookkeeping rename must not be
    # vetoed by an unrelated validation on a row it is not there to fix, and
    # must not fire Budget#inherit_area_scoping, which would stamp an unstamped
    # legacy line with its area's year and cost centre as a side effect.
    def self.planned_renames(scope)
      scope.where.not(area_id: nil).includes(:area).filter_map do |budget|
        area = budget.area
        next if area.nil? || area.name.blank?

        bare = BudgetImport.bare_name(budget.name, area.name)
        [ budget, bare ] unless bare == budget.name
      end
    end
    private_class_method :planned_renames

    # A collision this run would CREATE — an area already holding "Marketing"
    # when its "Cogito: Marketing" is about to become one too. One that was
    # already there is left alone: it is not this migration's doing, and
    # refusing over it would block the rename on data it cannot fix.
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
        "(#{pairs.join('; ')}) — rename one of them before migrating"
    end
    private_class_method :collision_message
  end
end
