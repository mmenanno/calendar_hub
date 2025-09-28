// Auto-submit a form when a field changes
import BaseController from "./base_controller"

export default class extends BaseController {
  submit(event) {
    const form = event.target?.form || this.element
    this.submitForm(form)
  }
}

