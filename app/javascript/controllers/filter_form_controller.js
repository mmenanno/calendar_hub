import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["match", "pattern", "error"]

  validate() {
    const matchType = this.matchTarget.value
    const pattern = this.patternTarget.value

    if (matchType === "regex" && pattern) {
      try {
        new RegExp(pattern)
        this.errorTarget.classList.add("hidden")
      } catch (e) {
        this.errorTarget.classList.remove("hidden")
      }
    } else {
      this.errorTarget.classList.add("hidden")
    }
  }
}
