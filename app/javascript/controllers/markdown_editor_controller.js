import { Controller } from "@hotwired/stimulus"
import Editor from "@toast-ui/editor"

export default class extends Controller {
  static values = {
    uploadUrl: String,
    height: { type: String, default: "300px" },
    itemType: String,
    itemId: String
  }

  connect() {
    this.#textarea = this.element.querySelector("textarea")
    if (!this.#textarea) return

    // Capture form ref now — Toast UI Editor clears this.element's innerHTML on
    // init, detaching the textarea from the DOM and making textarea.form null.
    const form = this.#textarea.closest("form")

    this.#editor = new Editor({
      el: this.element,
      initialValue: this.#textarea.value,
      previewStyle: "tab",
      height: this.heightValue,
      initialEditType: "markdown",
      hooks: {
        addImageBlobHook: (blob, callback) => this.#uploadImage(blob, callback)
      }
    })

    // Re-append the textarea after Editor cleared this.element, hidden.
    this.#textarea.style.display = "none"
    this.element.appendChild(this.#textarea)

    this.#editor.on("change", () => this.#sync())

    this.#boundSync = () => this.#sync()
    form?.addEventListener("submit", this.#boundSync, { capture: true })
  }

  disconnect() {
    this.#textarea?.form?.removeEventListener("submit", this.#boundSync, { capture: true })
    this.#editor?.destroy()
    this.#editor = null
  }

  // Private

  #textarea = null
  #editor = null
  #boundSync = null

  #sync() {
    this.#textarea.value = this.#editor.getMarkdown()
  }

  async #uploadImage(blob, callback) {
    const formData = new FormData()
    formData.append("image", blob, blob.name || "upload.png")
    if (this.itemTypeValue) formData.append("item_type", this.itemTypeValue)
    if (this.itemIdValue) formData.append("item_id", this.itemIdValue)

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    const response = await fetch(this.uploadUrlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": csrfToken },
      body: formData
    })

    if (response.ok) {
      const { url, alt } = await response.json()
      callback(url, alt)
    } else {
      callback("", "Upload failed")
    }
  }
}
