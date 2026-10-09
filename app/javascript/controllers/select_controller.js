import { Controller } from "@hotwired/stimulus"

// Builds a Tom Select for every select.simple-select2 in this element, including
// ones inserted later. Attributes on the <select>:
//   data-remote-source          search URL (JSON: { results: [{id, text}] })
//   data-query-field            search param name (default "q")
//   data-show-non-members       "1" to include non-members in user searches
//   data-placeholder            placeholder text
//   data-allow-clear            "true" for a clear button
//   data-minimum-input-length   chars before a search (default 0, or 2 when remote)
//   select2-with-tags           "true" to allow typed values (tags mode)
export default class extends Controller {
  #instances = new Map()
  #observer = null
  #TomSelect = null

  async connect() {
    this.#TomSelect = await import("tom-select").then(m => m.default)

    this.#initAll(this.element)

    this.#observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType !== Node.ELEMENT_NODE) continue
          if (node.matches?.("select.simple-select2")) {
            this.#initSelect(node)
          }
          node.querySelectorAll?.("select.simple-select2").forEach((el) => {
            if (!this.#instances.has(el)) this.#initSelect(el)
          })
        }
      }
    })
    this.#observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.#observer?.disconnect()
    this.#observer = null

    this.#instances.forEach((ts) => ts.destroy())
    this.#instances.clear()
  }

  #initAll(root) {
    root.querySelectorAll("select.simple-select2").forEach((el) => {
      if (!this.#instances.has(el)) {
        this.#initSelect(el)
      }
    })
  }

  #initSelect(el) {
    const placeholder = el.dataset.placeholder || "Select an option..."
    const allowClear = el.dataset.allowClear === "true"
    const hasTags = el.getAttribute("select2-with-tags") === "true"
    const remoteUrl = el.dataset.remoteSource
    const minLength = parseInt(el.dataset.minimumInputLength ?? (remoteUrl ? "2" : "0"), 10)

    const plugins = []
    if (allowClear) { plugins.push("clear_button") }
    // Without it, a chip can only be removed with the keyboard.
    if (el.multiple) { plugins.push("remove_button") }

    const options = {
      allowEmptyOption: allowClear,
      placeholder,
      plugins,
      render: {
        option_create: (data, escape) =>
          `<div class="create">Add <strong>${escape(data.input)}</strong>&hellip;</div>`
      }
    }

    if (hasTags) {
      options.create = true
      options.placeholder = "Select option or enter custom value..."

      // Opening with one item selected moves its text into the input to amend.
      let savedValue = null
      let lastTyped = null
      let inputListener = null

      options.onDropdownOpen = function () {
        if (this.items.length !== 1) return
        savedValue = this.items[0]
        const text = (this.options[savedValue] || {}).text || savedValue
        this.removeItem(savedValue, true)
        this.setTextboxValue(text)
        lastTyped = text

        // setTextboxValue fires no input event, so this sees only the user's typing.
        inputListener = (e) => { lastTyped = e.target.value }
        this.control_input.addEventListener("input", inputListener)
      }

      // Commit what was typed, or restore the original if it was cleared.
      // TomSelect has already emptied the input by now, hence lastTyped.
      options.onDropdownClose = function () {
        if (inputListener) {
          this.control_input.removeEventListener("input", inputListener)
          inputListener = null
        }

        if (savedValue !== null && this.items.length === 0) {
          const textToSave = lastTyped && lastTyped.trim()
          if (textToSave) {
            if (!this.options[textToSave]) {
              this.addOption({ value: textToSave, text: textToSave })
            }
            this.addItem(textToSave, true)
          } else {
            if (!this.options[savedValue]) {
              this.addOption({ value: savedValue, text: savedValue })
            }
            this.addItem(savedValue, true)
          }
        }
        savedValue = null
        lastTyped = null
      }
    }

    if (remoteUrl) {
      // Remote selects search from an input inside the dropdown.
      options.plugins = [...plugins, "dropdown_input"]
      options.valueField = "id"
      options.labelField = "text"
      options.searchField = ["text"]
      options.shouldLoad = (query) => query.length >= minLength
      options.load = (query, callback) => this.#ajaxLoad(el, query, callback)
      options.preload = false
    }

    // A required native select, hidden by TomSelect, blocks submit with a "not
    // focusable" error. The server validates instead.
    el.removeAttribute("required")

    const ts = new this.#TomSelect(el, options)
    this.#instances.set(el, ts)

    // The library is import()ed, so another controller cannot assume
    // el.tomselect exists by the time IT connects.
    el.dispatchEvent(new CustomEvent("select:ready", { bubbles: true }))
  }

  #ajaxLoad(el, query, callback) {
    // A URL object, because the source may already carry a query string (merge's ?exclude_id=).
    const url = new URL(el.dataset.remoteSource, window.location.origin)
    url.searchParams.set(el.dataset.queryField || "q", query)
    if (el.dataset.showNonMembers) url.searchParams.set("show_non_members", el.dataset.showNonMembers)

    fetch(url, {
      headers: { Accept: "application/json" },
      credentials: "same-origin"
    })
      .then((r) => r.json())
      .then((data) => callback(data.results || []))
      .catch(() => callback([]))
  }
}
