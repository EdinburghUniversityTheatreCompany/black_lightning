import { Controller } from "@hotwired/stimulus"

// The budget form's area picker against its owners list. The area owns and its
// budgets inherit, so owners chosen alongside an area would go to a table
// Budget#owners never reads, and the server refuses that post. Choosing an area
// disables the whole fieldset, so the browser posts no owner_ids at all (empty
// hidden field included) and the budget's own owner rows are left alone rather
// than synced to nothing.
//
// On the new-budget form it also narrows the area picker to the chosen cost
// centre: the server renders every centre's areas and refuses one from another.
export default class extends Controller {
  static targets = ["area", "costCentre", "owners", "notice"]

  #areaOptions = []

  connect() {
    // The full list, kept so switching back to a centre can restore its areas.
    this.#areaOptions = [...this.areaTarget.options].filter((option) => option.value !== "")
    this.costCentreChanged()
  }

  // An unplaced area (no centre) is offered under every centre, as the server
  // allows. A choice the new centre lacks falls back to "No area" instead of
  // being posted to be refused.
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
    // Tom Select's control is divs and looks live inside a disabled fieldset, so
    // owners picked there would be silently dropped.
    const ts = this.ownersTarget.querySelector("select.simple-select2")?.tomselect
    if (ts) { inArea ? ts.disable() : ts.enable() }
    if (this.hasNoticeTarget) this.noticeTarget.hidden = !inArea
  }
}
