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
    // Show first item without animation
    this.itemTargets.forEach((el, i) => el.classList.toggle("active", i === 0))
    this.#updateIndicators(0)
  }

  disconnect() {
    clearInterval(this.#timer)
  }

  next() {
    this.#go((this.currentValue + 1) % this.itemTargets.length, 1)
  }

  prev() {
    this.#go((this.currentValue - 1 + this.itemTargets.length) % this.itemTargets.length, -1)
  }

  goTo(event) {
    const index = Number(event.currentTarget.dataset.index)
    this.#go(index, index > this.currentValue ? 1 : -1)
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
  #sliding = false

  #go(nextIndex, direction) {
    if (this.#sliding || nextIndex === this.currentValue) return
    this.#sliding = true

    const outEl = this.itemTargets[this.currentValue]
    const inEl = this.itemTargets[nextIndex]

    // Add active first (makes it visible) then jump off-screen without transitioning.
    // Browsers don't commit style changes on visibility:hidden elements, so we must
    // make the element visible before setting the from-position.
    inEl.style.transition = "none"
    inEl.classList.add("active")
    inEl.style.transform = `translateX(${direction * 100}%)`

    // Force reflow to commit the no-transition jump before re-enabling transitions
    inEl.offsetWidth

    inEl.style.transition = ""
    inEl.style.transform = "translateX(0)"
    outEl.style.transform = `translateX(${-direction * 100}%)`

    // Use setTimeout rather than transitionend — more reliable across browsers
    setTimeout(() => {
      outEl.classList.remove("active")
      outEl.style.transform = ""
      inEl.style.transform = ""
      this.#sliding = false
    }, 550) // slightly longer than the 0.5s CSS transition

    this.currentValue = nextIndex
    this.#updateIndicators(nextIndex)
  }

  #updateIndicators(index) {
    this.indicatorTargets.forEach((el, i) => {
      el.classList.toggle("active", i === index)
      el.setAttribute("aria-current", i === index ? "true" : "false")
    })
  }
}
