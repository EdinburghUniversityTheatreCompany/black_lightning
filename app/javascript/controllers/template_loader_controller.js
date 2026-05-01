import { Controller } from "@hotwired/stimulus"

// Replaces the legacy app/assets/javascripts/admin/question_templates.js
// jQuery-based TemplateLoader class.
//
// Behaviour:
//   * On connect, reads two <meta> tags:
//       - templates-base-url  — JSON endpoint for the template list
//       - templates-items-type — "questions" or "jobs"
//   * Fetches the template list and populates #template_list (the modal
//     dropdown) via the native fetch API (no jQuery).
//   * When the user picks a template, shows a summary in #template_summary
//     and enables the #template_load button.
//   * When the user clicks #template_load, for each template item it:
//       1. Queues the item in #insertQueue.
//       2. Processes the queue one item at a time:
//          a. Sets #pendingItem to the next queued item.
//          b. Clicks the appropriate Cocoon "add fields" button.
//          c. The MutationObserver detects the inserted DOM node, fills it
//             from #pendingItem, then advances to the next queued item.
//
// Why MutationObserver instead of `addEventListener("cocoon:after-insert")`:
//   Cocoon fires its events via jQuery's custom-event system, not the browser's
//   native CustomEvent dispatch. Standard `addEventListener` cannot receive them.
//   MutationObserver is library-agnostic and survives the eventual Cocoon →
//   stimulus-rails-nested-form migration in Task 10.
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

  // Watch for DOM nodes added by Cocoon so we can populate them with template
  // data. We observe the entire document body because Cocoon inserts nodes at
  // the form level, which may be outside this controller's element (the modal).
  #setupObserver() {
    this.#observer = new MutationObserver((mutations) => {
      if (!this.#pendingItem) return

      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType !== Node.ELEMENT_NODE) continue
          if (this.#fillInsertedNode(node)) {
            // Successfully filled this node. Defer the advance so this
            // callback fully completes before the next add-button click fires.
            // This prevents Cocoon's second insertion from landing in the same
            // observer batch as the first, which would cause it to be skipped.
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
  // recognisable Cocoon-inserted row for our item type.
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
    const list = document.getElementById("template_list")
    const loadButton = document.getElementById("template_load")
    if (!list || !loadButton) return

    list.addEventListener("change", () => this.#handleTemplateSelection())
    loadButton.addEventListener("click", () => this.#loadTemplate())
  }

  #handleTemplateSelection() {
    const list = document.getElementById("template_list")
    const loadButton = document.getElementById("template_load")
    const summary = document.getElementById("template_summary")
    if (!list || !loadButton || !summary) return

    const templateId = list.value

    if (!templateId) {
      summary.innerHTML = ""
      this.#globalData = null
      loadButton.classList.add("disabled")
      return
    }

    const selected = this.#allTemplates.find((t) => String(t.id) === String(templateId))

    if (selected) {
      this.#globalData = selected
      this.#updateSummary()
      loadButton.classList.remove("disabled")
    } else {
      console.error("Selected template not found:", templateId)
      summary.innerHTML = "<p>Error: Template not found</p>"
      loadButton.classList.add("disabled")
    }
  }

  #updateSummary() {
    const summary = document.getElementById("template_summary")
    if (!summary) return

    const items = this.#itemsType === "questions"
      ? (this.#globalData.questions ?? []).map((q) => q.question_text)
      : (this.#globalData.staffing_jobs ?? []).map((j) => j.name)

    const list = document.createElement("ul")
    list.id = "template_items_list"
    items.forEach((text) => {
      const li = document.createElement("li")
      li.textContent = text
      list.appendChild(li)
    })

    summary.innerHTML = "<h3>Items</h3>"
    summary.appendChild(list)
  }

  #loadTemplate() {
    if (!this.#globalData) return

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
  // setTimeout(0) task to ensure the previous Cocoon DOM insertion has fully
  // settled (including jQuery animations and TomSelect initialisation) before
  // the next add-button click fires.
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
      console.error(`Cocoon add button not found: .${addButtonClass}`)
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

    // jQuery/Cocoon inserts synchronously. Fill the new row immediately.
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
        const list = document.getElementById("template_list")
        if (!list) return

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
