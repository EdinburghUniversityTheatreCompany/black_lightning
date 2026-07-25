import { Controller } from "@hotwired/stimulus"

// Guards a finance review card's Approve/Reject/override decision against
// silently dropping unsaved edits.
//
// The card's Save form is a SEPARATE <form> from each decision form, so hitting
// Approve or Reject used to submit the decision without the edits typed into the
// Save form. This controller snapshots the Save form on connect; when a decision
// button is clicked with the form dirty, it intercepts and opens a <dialog> with
// three choices (Cancel / Save Changes / Discard Changes). A pristine form is
// left alone, so any existing turbo-confirm on the decision form still fires.
//
// Progressive enhancement: with JS off, none of this runs and the buttons keep
// their server default (approve/reject without saving) — the server also accepts
// the edits + a save_changes flag in one request when "Save Changes" is chosen,
// so a save that fails validation aborts the decision server-side.
//
// Every save/decision here triggers a full navigation (the server redirects), so
// the snapshot is always fresh on the next connect; no in-page re-snapshot after
// a save is needed.
const SKIP_FIELDS = new Set(["_method", "authenticity_token", "utf8"])

export default class extends Controller {
  static targets = ["editForm", "dialog", "title"]

  #pendingForm = null

  connect() {
    // Same guard #guard has: with no edit form there is nothing to snapshot, and
    // reading editFormTarget would throw instead of degrading quietly.
    if (!this.hasEditFormTarget) return

    this.#snapshot = this.#serialize()
  }

  // Click handler on each decision submit control. Pristine form -> let the
  // click submit as usual (and any turbo-confirm run). Dirty -> stop the submit
  // and open the dialog, remembering which form to run afterwards.
  guard(event) {
    // Any [data-injected-edit] input still in the DOM is a leftover from a
    // submit that was aborted AFTER injection — the decision form's own
    // turbo-confirm being cancelled, say. It must never ride along on the NEXT
    // decision: that would commit (with save_changes=1) an edit the operator
    // went on to discard. Cleared before the dirty check, so a decision on a
    // form the operator has since reverted by hand is clean too.
    this.#clearInjectedFields()
    if (!this.hasEditFormTarget || !this.#dirty) return

    event.preventDefault()
    this.#pendingForm = event.currentTarget.form
    if (this.hasTitleTarget) {
      const verb = event.currentTarget.dataset.decisionVerb || "continuing"
      this.titleTarget.textContent = `Do you want to save the changes before ${verb}?`
    }
    this.dialogTarget.showModal()
  }

  // Cancel: close the dialog and stay on the page with the edits intact. The
  // close handler below is what forgets the pending decision.
  cancel() {
    this.dialogTarget.close()
  }

  // Clicking the backdrop (the dialog element itself, outside its content box)
  // is treated as Cancel.
  backdropClose({ target }) {
    if (target === this.dialogTarget) this.cancel()
  }

  // Every way the dialog closes funnels through the native close event —
  // including the Escape key, which never routes through #cancel(). Forget the
  // pending decision here so a dismissed dialog can't leave one armed.
  closed() {
    this.#pendingForm = null
  }

  // Save Changes: carry the Save form's fields (plus a save_changes flag) into
  // the decision form and submit it, so the server saves then decides in one
  // request.
  saveThenDecide() {
    this.#submitPending({ withEdits: true })
  }

  // Discard Changes: run the decision as-is, without the unsaved edits.
  discardThenDecide() {
    this.#submitPending({ withEdits: false })
  }

  #submitPending({ withEdits }) {
    const form = this.#pendingForm
    if (!form) return

    this.#pendingForm = null
    // Discard must submit a form carrying NO injected fields, whether or not an
    // earlier Save attempt on this card left some behind (see #guard).
    this.#clearInjectedFields()
    if (withEdits) this.#injectEditFields(form)
    this.dialogTarget.close()
    // requestSubmit fires a submit event (not a click), so it bypasses #guard
    // and lets any turbo-confirm on the decision form still run.
    form.requestSubmit()
  }

  // Across every decision form in this card, not just the one being submitted:
  // an abandoned Save on the override form must not poison a later Reject.
  #clearInjectedFields() {
    this.element.querySelectorAll("[data-injected-edit]").forEach((el) => el.remove())
  }

  #injectEditFields(form) {
    for (const [name, value] of new FormData(this.editFormTarget).entries()) {
      if (SKIP_FIELDS.has(name)) continue
      form.appendChild(this.#hiddenInput(name, value))
    }
    form.appendChild(this.#hiddenInput("save_changes", "1"))
  }

  #hiddenInput(name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    input.dataset.injectedEdit = ""
    return input
  }

  get #dirty() {
    return this.#serialize() !== this.#snapshot
  }

  // Percent-encoded, so the separators can never appear inside a value: joining
  // `name=value` raw let one set of field values serialise identically to a
  // different set (a description containing "&" or "="), and the dirty check
  // then decided real unsaved edits were pristine and dropped them.
  #serialize() {
    const parts = []
    for (const [name, value] of new FormData(this.editFormTarget).entries()) {
      if (SKIP_FIELDS.has(name)) continue
      parts.push(`${encodeURIComponent(name)}=${encodeURIComponent(value)}`)
    }
    return parts.join("&")
  }

  #snapshot = ""
}
