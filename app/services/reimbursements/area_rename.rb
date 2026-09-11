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
    # Both directions are idempotent: #strip! finds nothing left to strip on a
    # second run, and #restore! finds the prefix already there. A migration that
    # half-ran is re-run whole.
    #
    # One transaction, as AreaBackfill's is: half a rename is a budget list
    # written in two naming conventions with nothing on it to say which lines
    # were reached.
    def self.strip!(scope: Budget.all)
      rewrite(scope) { |budget, area| BudgetImport.bare_name(budget.name, area.name) }
    end

    # The reverse, and the reason the chain of migrations still rolls back:
    # BackfillReimbursementsAreas#down refuses to unwind an area whose name no
    # longer reproduces from any of its budgets, which is exactly what #strip!
    # leaves behind — correctly, since afterwards the area's name is the only
    # place the grouping lives.
    def self.restore!(scope: Budget.all)
      rewrite(scope) do |budget, area|
        already_prefixed = BudgetImport.bare_name(budget.name, area.name) != budget.name
        already_prefixed ? budget.name : "#{area.name}: #{budget.name}"
      end
    end

    # update_column, never update!: a bookkeeping rename must not be vetoed by an
    # unrelated validation on a row it is not there to fix, and must not fire
    # Budget#inherit_area_scoping, which would stamp an unstamped legacy line
    # with its area's year and cost centre as a side effect of a rename.
    def self.rewrite(scope)
      ActiveRecord::Base.transaction do
        scope.where.not(area_id: nil).includes(:area).find_each do |budget|
          area = budget.area
          next if area.nil? || area.name.blank?

          rewritten = yield(budget, area)
          budget.update_column(:name, rewritten) unless rewritten == budget.name
        end
      end
    end
    private_class_method :rewrite
  end
end
