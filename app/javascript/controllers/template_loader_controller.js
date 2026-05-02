import { Controller } from "@hotwired/stimulus"

// Replaces the legacy app/assets/javascripts/admin/question_templates.js
// jQuery-based TemplateLoader class.
//
// This controller should be placed on a wrapper element that contains both
// the trigger button and the <dialog> rendered by Admin::ModalComponent.
// The ModalComponent sets data-template-loader-target="dialog" on the <dialog>.
//
// Behaviour:
//   * On connect, reads two <meta> tags:
//       - templates-base-url  — JSON endpoint for the template list
//       - templates-items-type — "questions" or "jobs"
//   * Fetches the template list and populates the list target (the modal
//     dropdown) via the native fetch API (no jQuery).
//   * When the user picks a template, shows a summary in the summary target
//     and enables the loadButton target.
//   * When the user clicks loadButton, for each template item it:
//       1. Queues the item in #insertQueue.
//       2. Processes the queue one item at a time:
//          a. Sets #pendingItem to the next queued item.
//          b. Clicks the appropriate stimulus-rails-nested-form "add" button.
//          c. The MutationObserver detects the inserted DOM node, fills it
//             from #pendingItem, then advances to the next queued item.
//
// Why MutationObserver:
//   stimulus-rails-nested-form inserts a cloned <template> synchronously on
//   button click, but we use the MutationObserver as a fallback in case the
//   synchronous count-check misses the insertion. MutationObserver is
//   library-agnostic and works reliably regardless of insertion mechanism.
//
// Why a queue (not a simple forEach + null reset):
//   MutationObserver callbacks are delivered as microtasks — asynchronously
//   after the current task completes. If we click all add-buttons in a tight
//   forEach loop and then reset #pendingItem to null, the observer fires after
//   the reset and finds no item to populate. The queue ensures we advance
//   #pendingItem only once a node is confirmed inserted and populated.
//
// Note: We intentionally read the meta tags on connect() rather than using
// Stimulus data-values on the controller element. The three views that use
// this controller set the meta tags in <head> (inside content_for :head),
// which keeps the view diff minimal and avoids threading values through partials.
export default class extends Controller {
  static targets = ["dialog", "list", "summary", "loadButton"]

  #baseUrl = null
  #itemsType = null
  #allTemplates = []
  #globalData = null
  #observer = null

  // Queue of { addButtonClass, item } objects — consumed one at a time
  #insertQueue = []
  // The item currently waiting to be populated by the MutationObserver
  #pendingItem = null

  connect() {
    this.#baseUrl = document.querySelector('meta[name="templates-base-url"]')?.content
    this.#itemsType = document.querySelector('meta[name="templates-items-type"]')?.content

    if (!this.#validateSetup()) return

    this.#setupObserver()
    this.#bindListDropdown()
    this.#loadTemplateList()
  }

  disconnect() {
    this.#observer?.disconnect()
    this.#observer = null
  }

  // Public Stimulus actions

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  backdropClose({ target }) {
    if (target === this.dialogTarget) this.dialogTarget.close()
  }

  // Private

  #validateSetup() {
    if (!this.#baseUrl) {
      alert("'templates-base-url' meta tag is missing or empty.")
      return false
    }

    if (!this.#baseUrl.endsWith(".json")) {
      this.#baseUrl += ".json"
    }

    if (!this.#itemsType || !["questions", "jobs"].includes(this.#itemsType)) {
      alert("'templates-items-type' meta tag must be 'questions' or 'jobs'.")
      return false
    }

    return true
  }

  // Watch for DOM nodes added by stimulus-rails-nested-form so we can
  // populate them with template data. We observe the entire document body
  // because nested-form inserts nodes at the form level, outside this
  // controller's element.
  #setupObserver() {
    this.#observer = new MutationObserver((mutations) => {
      if (!this.#pendingItem) return

      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType !== Node.ELEMENT_NODE) continue
          if (this.#fillInsertedNode(node)) {
            // Defer the advance so this callback fully completes before the
            // next add-button click fires, preventing multiple insertions from
            // landing in the same observer batch.
            queueMicrotask(() => this.#advanceQueue())
            return
          }
        }
      }
    })

    this.#observer.observe(document.body, { childList: true, subtree: true })
  }

  // Try to populate the inserted node. Returns true if this node matched and
  // was filled (even if some fields were absent), false if the node is not a
  // recognisable nested-form-inserted row for our item type.
  #fillInsertedNode(node) {
    const item = this.#pendingItem

    if (this.#itemsType === "questions") {
      if (node.classList?.contains("question")) {
        const textField = node.querySelector('[name$="[question_text]"]')
        const typeField = node.querySelector('[name$="[response_type]"]')
        if (textField) textField.value = item.question_text ?? ""
        if (typeField) typeField.value = item.response_type ?? ""
        return true
      }

      if (node.classList?.contains("email")) {
        const emailField = node.querySelector('[name$="[email]"]')
        if (emailField) emailField.value = item.email ?? ""
        return true
      }
    } else if (this.#itemsType === "jobs") {
      // Staffing job rows do not have a specific identifying class like
      // "question". Instead they contain a [name$="[name]"] input, which is
      // enough to identify them as the right target.
      const nameField = node.querySelector('[name$="[name]"]')
      if (nameField) {
        nameField.value = item.name ?? ""
        return true
      }
    }

    return false
  }

  #bindListDropdown() {
    if (!this.hasListTarget || !this.hasLoadButtonTarget) return

    this.listTarget.addEventListener("change", () => this.#handleTemplateSelection())
    this.loadButtonTarget.addEventListener("click", () => this.#loadTemplate())
  }

  #handleTemplateSelection() {
    const list = this.listTarget
    const loadButton = this.loadButtonTarget
    const summary = this.summaryTarget

    const templateId = list.value

    if (!templateId) {
      summary.innerHTML = ""
      this.#globalData = null
      loadButton.disabled = true
      return
    }

    const selected = this.#allTemplates.find((t) => String(t.id) === String(templateId))

    if (selected) {
      this.#globalData = selected
      this.#updateSummary()
      loadButton.disabled = false
    } else {
      console.error("Selected template not found:", templateId)
      summary.innerHTML = "<p>Error: Template not found</p>"
      loadButton.disabled = true
    }
  }

  #updateSummary() {
    const summary = this.summaryTarget
    const fragment = document.createDocumentFragment()

    const heading = document.createElement("p")
    heading.className = "text-xs font-semibold text-gray-500 uppercase tracking-wide mt-3 mb-1"
    heading.textContent = "Preview"
    fragment.appendChild(heading)

    const list = document.createElement("ul")
    list.className = "space-y-1"

    if (this.#itemsType === "questions") {
      const questions = this.#globalData.questions ?? []
      questions.forEach((q) => {
        const li = document.createElement("li")
        li.className = "flex items-start gap-2 text-sm py-1 border-b border-gray-100 last:border-0"

        const text = document.createElement("span")
        text.className = "flex-1 text-gray-800"
        text.textContent = q.question_text ?? ""

        if (q.response_type) {
          const badge = document.createElement("span")
          badge.className = "text-xs px-1.5 py-0.5 rounded bg-gray-100 text-gray-500 shrink-0 font-mono"
          badge.textContent = q.response_type.replace(/_/g, " ")
          li.appendChild(text)
          li.appendChild(badge)
        } else {
          li.appendChild(text)
        }

        list.appendChild(li)
      })
    } else {
      const jobs = this.#globalData.staffing_jobs ?? []
      jobs.forEach((j) => {
        const li = document.createElement("li")
        li.className = "text-sm text-gray-800 py-1 border-b border-gray-100 last:border-0"
        li.textContent = j.name ?? ""
        list.appendChild(li)
      })
    }

    fragment.appendChild(list)
    summary.innerHTML = ""
    summary.appendChild(fragment)
  }

  #loadTemplate() {
    if (!this.#globalData) return

    this.dialogTarget.close()

    this.#insertQueue = []

    if (this.#itemsType === "questions") {
      const questions = this.#globalData.questions ?? []
      questions.forEach((item) => {
        this.#insertQueue.push({ addButtonClass: "question_add_button", item })
      })

      const emails = this.#globalData.notify_emails ?? []
      emails.forEach((item) => {
        this.#insertQueue.push({ addButtonClass: "notify_email_add_button", item })
      })
    } else if (this.#itemsType === "jobs") {
      const jobs = this.#globalData.staffing_jobs ?? []
      jobs.forEach((item) => {
        this.#insertQueue.push({ addButtonClass: "staffing_job_add_button", item })
      })
    }

    this.#advanceQueue()
  }

  // Pull the next item off the queue. Each item is processed in a separate
  // setTimeout(0) task to ensure the previous nested-form DOM insertion has
  // fully settled (including TomSelect initialisation) before the next
  // add-button click fires.
  #advanceQueue() {
    if (this.#insertQueue.length === 0) {
      this.#pendingItem = null
      return
    }

    setTimeout(() => this.#processNextItem(), 0)
  }

  #processNextItem() {
    if (this.#insertQueue.length === 0) {
      this.#pendingItem = null
      return
    }

    const { addButtonClass, item } = this.#insertQueue.shift()

    const button = document.querySelector(`.${addButtonClass}`)
    if (!button) {
      console.error(`nested-form add button not found: .${addButtonClass}`)
      this.#advanceQueue()
      return
    }

    // Snapshot the current row count so we can identify the newly added row.
    const containerSelector = this.#containerSelectorFor(addButtonClass)
    const countBefore = containerSelector
      ? document.querySelectorAll(containerSelector).length
      : -1

    // Set pending BEFORE the click so the MutationObserver backup path can
    // also fill the row if the synchronous count check fails.
    this.#pendingItem = item

    button.click()

    // stimulus-rails-nested-form inserts synchronously. Fill the new row immediately.
    if (containerSelector && countBefore >= 0) {
      const rows = document.querySelectorAll(containerSelector)
      if (rows.length > countBefore) {
        const newRow = rows[rows.length - 1]
        this.#fillRow(newRow, item)
        this.#pendingItem = null
        this.#advanceQueue()
        return
      }
    }

    // Fallback: MutationObserver will fill the row and advance the queue.
  }

  // Returns a CSS selector that matches inserted rows for a given add-button class.
  #containerSelectorFor(addButtonClass) {
    if (addButtonClass === "question_add_button")     return ".nested-fields.question"
    if (addButtonClass === "notify_email_add_button") return ".nested-fields.email"
    if (addButtonClass === "staffing_job_add_button") return ".nested-fields"
    return null
  }

  // Fill a row's fields from a template item.
  #fillRow(row, item) {
    if (this.#itemsType === "questions") {
      if (row.classList?.contains("question")) {
        const textField = row.querySelector('[name$="[question_text]"]')
        const typeField = row.querySelector('[name$="[response_type]"]')
        if (textField) textField.value = item.question_text ?? ""
        if (typeField) typeField.value = item.response_type ?? ""
      } else if (row.classList?.contains("email")) {
        const emailField = row.querySelector('[name$="[email]"]')
        if (emailField) emailField.value = item.email ?? ""
      }
    } else if (this.#itemsType === "jobs") {
      const nameField = row.querySelector('[name$="[name]"]')
      if (nameField) nameField.value = item.name ?? ""
    }
  }

  #loadTemplateList() {
    fetch(this.#baseUrl, {
      headers: { Accept: "application/json" },
      credentials: "same-origin"
    })
      .then((r) => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json()
      })
      .then((data) => {
        if (!Array.isArray(data) || data.length === 0) {
          console.log("Template list is empty or not an array")
          return
        }

        this.#allTemplates = data
        const list = this.listTarget

        data.forEach((template) => {
          const option = document.createElement("option")
          option.value = template.id
          option.textContent = template.name
          list.appendChild(option)
        })

        // TomSelect is initialized before this async fetch completes.
        // Sync its internal option store from the now-populated <select>.
        list.tomselect?.sync()
      })
      .catch((err) => {
        console.error("Failed to load template list:", err)
      })
  }
}
