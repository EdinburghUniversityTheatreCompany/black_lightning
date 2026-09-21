import { Controller } from "@hotwired/stimulus"

// Drives the Review queue's bulk-select toolbar: a select-all checkbox, a live
// "N selected" counter, enabling the Approve/Reject buttons only when at least
// one expense is ticked, and injecting the count into the reject confirmation
// ("Reject N expenses and email each producer?"). The per-item checkboxes live
// in the expense cards but are wired to the toolbar form via a shared `form`
// attribute, so no card form is nested inside the bulk form.
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
      // Approval commits real money to a BACS batch, and "Select all" ticks
      // flagged (needs-attention) cards indistinguishably from clean ones —
      // so the confirm carries the flagged count, the only warning between
      // a blanket select-all and approving a flagged expense.
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
      // Gated on the reason too, not just on a selection. The reason box is
      // shared with "Approve selected" and so cannot carry `required`, and
      // without this the irreversible "and email each producer?" confirm fired
      // BEFORE the server refused the blank reason — agreeing to something
      // that was never going to happen.
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
      // Gated on the note as well as on a selection, for the reason Reject is
      // gated on its reason: the note is the only record that finance bypassed
      // a control on several claims at once, and the server refuses a blank
      // one — so the confirm must not fire over a decision that cannot happen.
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
