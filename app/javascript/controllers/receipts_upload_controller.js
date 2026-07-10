import { Controller } from "@hotwired/stimulus"
import { getMetaValue } from "../helpers"

// Immediate receipt add/remove for the expense edit page. Files go straight
// to the receipts endpoint (Airtable-backed, so no ActiveStorage direct
// upload) and the server's turbo stream replaces #receipts-gallery. Turbo
// Drive is disabled app-wide, so streams are piped through
// Turbo.renderStreamMessage by hand.
export default class extends Controller {
  static targets = ["input", "status"]
  static values = { url: String }

  pick() {
    this.inputTarget.click()
  }

  inputChanged() {
    this.#upload(this.inputTarget.files)
  }

  dragover(event) {
    event.preventDefault()
    this.element.querySelector(".dropzone")?.classList.add("dz-drag-hover")
  }

  dragleave() {
    this.element.querySelector(".dropzone")?.classList.remove("dz-drag-hover")
  }

  drop(event) {
    event.preventDefault()
    this.dragleave()
    this.#upload(event.dataTransfer.files)
  }

  async remove(event) {
    const { url, filename } = event.currentTarget.dataset
    if (!(await this.#confirm(`Remove ${filename} from this expense?`))) return

    this.#setStatus(`Removing ${filename}…`)
    await this.#request(url, { method: "DELETE" })
  }

  async #upload(files) {
    if (!files.length) return

    const body = new FormData()
    for (const file of files) body.append("receipts[]", file)
    this.inputTarget.value = ""

    this.#setStatus(files.length === 1 ? `Uploading ${files[0].name}…` : `Uploading ${files.length} files…`)
    await this.#request(this.urlValue, { method: "POST", body })
  }

  async #request(url, options) {
    try {
      const response = await fetch(url, {
        headers: { "X-CSRF-Token": getMetaValue("csrf-token"), "Accept": "text/vnd.turbo-stream.html" },
        credentials: "same-origin",
        ...options,
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      Turbo.renderStreamMessage(await response.text())
      this.#setStatus("")
    } catch {
      this.#setStatus("Something went wrong. Refresh the page and try again.")
    }
  }

  async #confirm(message) {
    if (!window.Swal) return window.confirm(message)

    const result = await window.Swal.mixin({ buttonsStyling: true }).fire({
      icon: "warning",
      title: "Are you sure?",
      html: message,
      showCancelButton: true,
      confirmButtonText: "Yes",
      cancelButtonText: "Cancel",
    })
    return Boolean(result.value)
  }

  #setStatus(message) {
    this.statusTarget.textContent = message
  }
}
