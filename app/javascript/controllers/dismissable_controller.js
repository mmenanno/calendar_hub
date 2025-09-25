import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["progress"]
  static values = {
    delay: { type: Number, default: 5000 }
  }

  connect () {
    if (this.progressTarget) {
      try {
        // animate width over the delay
        this.progressTarget.style.transitionProperty = 'width'
        this.progressTarget.style.transitionTimingFunction = 'linear'
        this.progressTarget.style.transitionDuration = `${this.delayValue}ms`
        requestAnimationFrame(() => {
          this.progressTarget.style.width = '100%'
        })
      } catch (e) { /* noop */ }
    }
    if (this.delayValue > 0) {
      this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
    }
  }

  disconnect () {
    if (this.timeout) clearTimeout(this.timeout)
  }

  dismiss () {
    this.element.remove()
  }
}
