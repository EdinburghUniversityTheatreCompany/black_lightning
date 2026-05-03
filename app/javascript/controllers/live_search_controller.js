import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    delay: { type: Number, default: 1000 },
    randomButtonNames: { type: Array, default: ["RANDOM", "ON THIS DAY"] }
  }

  #timer = null

  scheduleSearch(event) {
    if (event.type === "submit" && this.#isPassthroughSubmit(event)) return

    if (event.type === "submit") {
      event.preventDefault()
      this.#clearTimer()
      this.#doSearch()
      return
    }

    this.#clearTimer()
    this.#timer = setTimeout(() => this.#doSearch(), this.delayValue)
  }

  disconnect() {
    this.#clearTimer()
  }

  #isPassthroughSubmit(event) {
    const submitter = event.submitter
    if (!submitter) return false
    const label = (submitter.value || submitter.textContent || "").trim().toUpperCase()
    return this.randomButtonNamesValue.some(name => name.toUpperCase() === label)
  }

  #clearTimer() {
    if (this.#timer) {
      clearTimeout(this.#timer)
      this.#timer = null
    }
  }

  #doSearch() {
    const form = this.element.querySelector("form") || this.element
    const params = new URLSearchParams(new FormData(form))
    params.delete("commit")

    const url = new URL(form.action || window.location.href)
    url.search = params.toString()
    history.replaceState({}, "", url.toString())

    fetch(url.toString(), {
      headers: { "Accept": "text/vnd.turbo-stream.html" },
      credentials: "same-origin"
    })
      .then(r => r.ok ? r.text() : null)
      .then(html => { if (html) Turbo.renderStreamMessage(html) })
  }
}
