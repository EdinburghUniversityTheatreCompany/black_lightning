import { Controller } from "@hotwired/stimulus"

// The budget form's area picker against its owners list. The area owns and its
// budgets inherit, so owners chosen while an area is chosen would be written to
// a table Budget#owners never reads — the server refuses that post outright.
// This is what stops the operator reaching the refusal: choosing an area
// disables the whole fieldset, which also stops the browser posting owner_ids
// at all (a disabled fieldset submits none of its controls, the empty hidden
// field included, so the budget's own owner rows are left alone rather than
// synced to nothing).
//
// On the new-budget form it also narrows the area picker to the chosen cost
// centre: the server renders every centre's areas, each option tagged with its
// own, and refuses an area from another centre.
export default class extends Controller {
  static targets = ["area", "costCentre", "owners", "notice"]

  #areaOptions = []

  connect() {
    // The full list, kept so switching back to a centre can restore its areas.
    this.#areaOptions = [...this.areaTarget.options].filter((option) => option.value !== "")
    this.costCentreChanged()
  }

  // An option with no centre is an unplaced area, offered under every centre
  // as the server's own check allows. A choice the new centre does not hold
  // falls back to "No area" rather than being posted to be refused.
  costCentreChanged() {
    if (this.hasCostCentreTarget) {
      const centre = this.costCentreTarget.value
      const chosen = this.areaTarget.value
      const offered = this.#areaOptions.filter((option) => {
        const own = option.dataset.costCentreId
        return !own || own === centre
      })
      const blank = [...this.areaTarget.options].find((option) => option.value === "")
      this.areaTarget.replaceChildren(...[blank, ...offered].filter(Boolean))
      this.areaTarget.value = offered.some((option) => option.value === chosen) ? chosen : ""
    }
    this.areaChanged()
  }

  areaChanged() {
    if (!this.hasOwnersTarget) return

    const inArea = this.areaTarget.value !== ""
    this.ownersTarget.disabled = inArea
    // A disabled fieldset stops the browser SUBMITTING the select, but Tom
    // Select's own control is divs and goes on looking live inside one — so an
    // operator would pick owners that are then silently dropped.
    const ts = this.ownersTarget.querySelector("select.simple-select2")?.tomselect
    if (ts) { inArea ? ts.disable() : ts.enable() }
    if (this.hasNoticeTarget) this.noticeTarget.hidden = !inArea
  }
}
