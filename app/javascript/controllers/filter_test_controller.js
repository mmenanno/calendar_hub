import DebouncedFormController from "./debounced_form_controller"

export default class extends DebouncedFormController {
  static targets = ["source", "input"]
  static values = {
    url: String,
    delay: { type: Number, default: 250 }
  }

  async submit() {
    if (!this.anyFilled()) {
      const result = document.getElementById('filter_test_result')
      if (result) {
        result.innerHTML = ''
      }
      return
    }

    // Use parent class submit method
    await super.submit()
  }

  anyFilled() {
    return this.inputTargets.some((input) => input.value.trim().length > 0)
  }
}
