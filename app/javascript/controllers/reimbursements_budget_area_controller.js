import { Controller } from "@hotwired/stimulus"

// The budget form's area picker against its owners list. The area owns and its
// budgets inherit, so owners chosen while an area is chosen would be written to
// a table Budget#owners never reads — the server refuses that post outright.
// This is what stops the operator reaching the refusal: choosing an area
// disables the whole fieldset, which also stops the browser posting owner_ids
// at all (a disabled fieldset submits none of its controls, the empty hidden
// field included, so the budget's own owner rows are left alone rather than
// synced to nothing).
export default class extends Controller {
  static targets = ["area", "owners", "notice"]

  connect() {
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
