import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

// Shared AJAX cache for all remote-source selects on this page.
// Cache is automatically cleared on page navigation (appropriate for user data).
const ajaxCache = {
  data: {},
  timestamps: {},
  maxAge: 60000, // 60 seconds TTL

  generateKey(url, params) {
    const sortedParams = Object.keys(params)
      .sort()
      .map(k => `${k}=${params[k]}`)
      .join("&")
    return `${url}?${sortedParams}`
  },

  get(key) {
    const timestamp = this.timestamps[key]
    if (timestamp && (Date.now() - timestamp) < this.maxAge) {
      return this.data[key]
    }
    delete this.data[key]
    delete this.timestamps[key]
    return null
  },

  set(key, value) {
    this.data[key] = value
    this.timestamps[key] = Date.now()
  }
}

// Replaces the legacy app/javascript/src/shared/select2.js jQuery plugin.
//
// Usage: Add data-controller="select" to any element that contains
// <select class="simple-select2"> descendants. All selects within the
// controller element are initialised automatically on connect, and any
// dynamically inserted selects (e.g. via Cocoon) are picked up by a
// MutationObserver scoped to the controller's element.
//
// Supported data attributes on the <select> element:
//   data-remote-source    URL for AJAX autocomplete (JSON: { results: [{id, text}] })
//   data-query-field      Query param name for the search term (default: "q")
//   data-show-non-members "1" to include non-members in user searches
//   data-placeholder      Placeholder text (default: "Select an option...")
//   data-allow-clear      "true" to show a clear button
//   data-minimum-input-length  Min chars before AJAX fires (default: 0 for local, 2 for remote)
//   select2-with-tags     "true" to allow creating custom option values (tags mode)
export default class extends Controller {
  // Holds {element => TomSelect} so we can destroy on disconnect
  #instances = new Map()
  #observer = null

  connect() {
    this.#initAll(this.element)

    // Watch for dynamically inserted selects (Cocoon, Turbo frames, etc.).
    // We can't rely on `addEventListener("cocoon:after-insert")` because
    // Cocoon fires via jQuery's custom event system, which doesn't dispatch
    // a native CustomEvent. MutationObserver is library-agnostic and survives
    // the eventual Cocoon → stimulus-rails-nested-form migration in Task 10.
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

  // Private

  #initAll(root) {
    root.querySelectorAll("select.simple-select2").forEach((el) => {
      if (!this.#instances.has(el)) {
        this.#initSelect(el)
      }
    })
  }

  #initSelect(el) {
    const placeholder = el.dataset.placeholder || "Select an option..."
    const allowClear  = el.dataset.allowClear === "true"
    const hasTags     = el.getAttribute("select2-with-tags") === "true"
    const remoteUrl   = el.dataset.remoteSource
    const minLength   = parseInt(el.dataset.minimumInputLength ?? (remoteUrl ? "2" : "0"), 10)

    const plugins = []
    if (allowClear) { plugins.push("clear_button") }

    const theme = window.location.pathname.startsWith("/admin") ? "default" : "bootstrap5"

    const options = {
      theme,
      allowEmptyOption: allowClear,
      placeholder,
      plugins,
      render: {
        // Show placeholder text inside the control area
        option_create: (data, escape) =>
          `<div class="create">Add <strong>${escape(data.input)}</strong>&hellip;</div>`
      }
    }

    if (hasTags) {
      options.create = true
      options.placeholder = "Select option or enter custom value..."
    }

    if (remoteUrl) {
      // Use the dropdown_input plugin so the search box appears inside the
      // dropdown (Bootstrap 5 theme is designed for this layout) and the
      // placeholder is shown correctly in the collapsed control.
      options.plugins = [...plugins, "dropdown_input"]
      options.valueField  = "id"
      options.labelField  = "text"
      options.searchField = ["text"]
      options.shouldLoad  = (query) => query.length >= minLength
      options.load        = (query, callback) => this.#ajaxLoad(el, query, callback)
      // Don't pre-load options — only fetch when the user types
      options.preload     = false
    }

    const ts = new TomSelect(el, options)
    this.#instances.set(el, ts)
  }

  #ajaxLoad(el, query, callback) {
    const remoteUrl       = el.dataset.remoteSource
    const queryField      = el.dataset.queryField || "q"
    const showNonMembers  = el.dataset.showNonMembers

    const params = {
      page: 1,
      _type: "query",
      [queryField]: query
    }

    if (showNonMembers) {
      params.show_non_members = showNonMembers
    }

    const cacheKey  = ajaxCache.generateKey(remoteUrl, params)
    const cached    = ajaxCache.get(cacheKey)

    if (cached) {
      // Return cached data asynchronously to match AJAX behaviour
      setTimeout(() => callback(cached), 0)
      return
    }

    const url = `${remoteUrl}?${new URLSearchParams(params).toString()}`

    fetch(url, {
      headers: { Accept: "application/json" },
      credentials: "same-origin"
    })
      .then((r) => r.json())
      .then((data) => {
        const results = data.results || []
        ajaxCache.set(cacheKey, results)
        callback(results)
      })
      .catch(() => callback([]))
  }
}
