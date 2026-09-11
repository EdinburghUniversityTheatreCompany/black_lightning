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

    # Byte-for-byte, and ONLY the rows #strip! recorded. Restoring by rule
    # instead would re-prefix lines the strip deliberately refused to touch,
    # making every area reproducible from its budgets — which disarms
    # BackfillReimbursementsAreas#down's refusal and turns it into a silent
    # delete of areas and their owner rows.
    def self.restore!(scope: Budget.all)
      ActiveRecord::Base.transaction do
        scope.where.not(name_before_area_rename: nil).find_each do |budget|
          budget.update_columns(name: budget.name_before_area_rename,
                                name_before_area_rename: nil)
        end
      end
    end

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
