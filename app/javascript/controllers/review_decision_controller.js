import { Controller } from "@hotwired/stimulus"

// Stops a review card's Approve/Reject/override dropping unsaved edits: the Save
// form is separate from each decision form. A decision clicked with it dirty
// opens a dialog: Cancel, Save Changes (the edits ride along with save_changes=1)
// or Discard Changes. Every decision redirects, so each connect snapshots afresh.
const SKIP_FIELDS = new Set(["_method", "authenticity_token", "utf8"])

export default class extends Controller {
  static targets = ["editForm", "dialog", "title"]

  #pendingForm = null

  connect() {
    if (!this.hasEditFormTarget) return

    this.#snapshot = this.#serialize()
  }

  guard(event) {
    // Leftovers from a submit aborted after injection (its turbo-confirm
    // cancelled, say), cleared before the dirty check so an aborted Save can
    // never ride on a later Discard.
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

  cancel() {
    this.dialogTarget.close()
  }

  backdropClose({ target }) {
    if (target === this.dialogTarget) this.cancel()
  }

  // Every close lands here, Escape included, which never routes through
  // #cancel, so a dismissed dialog cannot leave a decision armed.
  closed() {
    this.#pendingForm = null
  }

  saveThenDecide() {
    this.#submitPending({ withEdits: true })
  }

  discardThenDecide() {
    this.#submitPending({ withEdits: false })
  }

  #submitPending({ withEdits }) {
    const form = this.#pendingForm
    if (!form) return

    this.#pendingForm = null
    this.#clearInjectedFields()
    if (withEdits) this.#injectEditFields(form)
    this.dialogTarget.close()
    // requestSubmit bypasses #guard (no click) and still runs the decision
    // form's turbo-confirm.
    form.requestSubmit()
  }

  // Every decision form in the card: an abandoned Save on one must not poison another.
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

  // Percent-encoded, so an "&" or "=" in a value cannot make a dirty form read
  // as pristine.
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
