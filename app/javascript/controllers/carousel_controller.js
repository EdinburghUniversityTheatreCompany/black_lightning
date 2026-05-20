import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "indicator"]
  static values = {
    current: { type: Number, default: 0 },
    interval: { type: Number, default: 6000 }
  }

  connect() {
    if (this.intervalValue > 0) {
      this.#timer = setInterval(() => this.next(), this.intervalValue)
    }
    this.#show(this.currentValue)
  }

  disconnect() {
    clearInterval(this.#timer)
  }

  next() {
    this.#show((this.currentValue + 1) % this.itemTargets.length)
  }

  prev() {
    this.#show((this.currentValue - 1 + this.itemTargets.length) % this.itemTargets.length)
  }

  goTo(event) {
    this.#show(Number(event.currentTarget.dataset.index))
  }

  pause() {
    clearInterval(this.#timer)
    this.#timer = null
  }

  resume() {
    if (this.intervalValue > 0 && !this.#timer) {
      this.#timer = setInterval(() => this.next(), this.intervalValue)
    }
  }

  // private

  #timer = null

  #show(index) {
    this.itemTargets.forEach((el, i) => el.classList.toggle("active", i === index))
    this.indicatorTargets.forEach((el, i) => {
      el.classList.toggle("active", i === index)
      el.setAttribute("aria-current", i === index ? "true" : "false")
    })
    this.currentValue = index
  }
}
