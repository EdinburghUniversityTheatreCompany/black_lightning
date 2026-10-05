import { Controller } from "@hotwired/stimulus"

// The Review queue's bulk toolbar. Card checkboxes join the toolbar form through
// their `form` attribute, so no card form is nested inside it.
export default class extends Controller {
  static targets = [
    "checkbox",
    "selectAll",
    "approveButton",
    "rejectButton",
    "overrideButton",
    "counter",
    "reason",
  ]

  connect() {
    this.refresh()
  }

  toggleAll() {
    this.checkboxTargets.forEach((cb) => {
      cb.checked = this.selectAllTarget.checked
    })
    this.refresh()
  }

  refresh() {
    const selected = this.selectedCount
    const none = selected === 0

    if (this.hasApproveButtonTarget) {
      this.approveButtonTarget.disabled = none
      // Select-all ticks flagged cards just like clean ones, so the confirm
      // carries the flagged count.
      const flagged = this.flaggedSelectedCount
      const base = `Approve ${selected} expense${selected === 1 ? "" : "s"}?`
      this.approveButtonTarget.dataset.turboConfirm =
        flagged === 0
          ? base
          : `${base} ${flagged} of them ${
              flagged === 1 ? "is" : "are"
            } flagged as needing attention. Check the reasons on the card${
              flagged === 1 ? "" : "s"
            } before continuing.`
    }
    if (this.hasRejectButtonTarget) {
      // The reason box is shared with Approve, so it cannot carry `required`.
      // Gating here stops the irreversible confirm firing over a reject the
      // server will refuse.
      const reasonGiven = !this.hasReasonTarget || this.reasonTarget.value.trim().length > 0
      this.rejectButtonTarget.disabled = none || !reasonGiven
      this.rejectButtonTarget.title = reasonGiven
        ? ""
        : "Type a reason above: it is emailed to the producer."
      this.rejectButtonTarget.dataset.turboConfirm = `Reject ${selected} expense${
        selected === 1 ? "" : "s"
      } and email each producer?`
    }
    if (this.hasOverrideButtonTarget) {
      // Gated like Reject: the server refuses a blank note.
      const noteGiven = !this.hasReasonTarget || this.reasonTarget.value.trim().length > 0
      this.overrideButtonTarget.disabled = none || !noteGiven
      this.overrideButtonTarget.title = noteGiven
        ? ""
        : "Say why above: it is the only record of the decision."
      this.overrideButtonTarget.dataset.turboConfirm = `Approve ${selected} claim${
        selected === 1 ? "" : "s"
      } without their budget owner's sign-off? Your name and reason are recorded against each one.`
    }
    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${selected} selected`
    }
    if (this.hasSelectAllTarget) {
      const total = this.checkboxTargets.length
      this.selectAllTarget.checked = total > 0 && selected === total
      this.selectAllTarget.indeterminate = selected > 0 && selected < total
    }
  }

  get selectedCount() {
    return this.checkboxTargets.filter((cb) => cb.checked).length
  }

  get flaggedSelectedCount() {
    return this.checkboxTargets.filter(
      (cb) => cb.checked && cb.dataset.flagged === "true",
    ).length
  }
}
