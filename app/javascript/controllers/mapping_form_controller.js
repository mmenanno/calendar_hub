import BaseController from "./base_controller"

export default class extends BaseController {
  static targets = ["match", "pattern", "error", "submit"]

  connect () {
    this.validate()
  }

  validate () {
    const isRegex = this.matchTarget.value === 'regex'
    const pat = this.patternTarget.value
    let ok = true
    if (isRegex && pat.length > 0) {
      try {
        new RegExp(pat)
        ok = true
      } catch (e) {
        ok = false
      }
    }
    this.errorTarget.classList.toggle('hidden', ok)
    this.submitTarget.disabled = !ok
  }
}

