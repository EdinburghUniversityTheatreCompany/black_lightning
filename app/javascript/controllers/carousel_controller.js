import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "indicator"]
  static values = {
    current: { type: Number, default: 0 },
    interval: { type: Number, default: 5000 }
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

  // private

  #timer = null

  #show(index) {
    this.itemTargets.forEach((el, i) => el.classList.toggle("active", i === index))
    this.indicatorTargets.forEach((el, i) => el.classList.toggle("active", i === index))
    this.currentValue = index
  }
}
