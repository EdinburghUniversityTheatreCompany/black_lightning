import { Controller } from "@hotwired/stimulus"
import { getMetaValue } from "../helpers"
import { confirmDialog } from "../lib/confirm"

// Immediate receipt add/remove for the expense edit page. Files go to the
// receipts endpoint as a plain multipart POST (not an ActiveStorage direct
// upload) via fetch, so the turbo-stream reply that replaces #receipts-gallery
// is rendered by hand.
export default class extends Controller {
  static targets = ["input", "status", "zone"]
  static values = { url: String }

  pick() {
    this.inputTarget.click()
  }

  inputChanged() {
    this.#upload(this.inputTarget.files)
  }

  dragover(event) {
    event.preventDefault()
    this.zoneTarget.classList.add("border-primary", "bg-primary/5")
  }

  dragleave() {
    this.zoneTarget.classList.remove("border-primary", "bg-primary/5")
  }

  drop(event) {
    event.preventDefault()
    this.dragleave()
    this.#upload(event.dataTransfer.files)
  }

  async remove(event) {
    const { url, filename } = event.currentTarget.dataset
    if (!(await confirmDialog(`Remove ${filename} from this expense?`))) return

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

  #setStatus(message) {
    this.statusTarget.textContent = message
  }
}
