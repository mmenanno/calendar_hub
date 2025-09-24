import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "icon", "label"]
  static values = {
    key: String,
    defaultOpen: { type: Boolean, default: false },
    remember: { type: Boolean, default: true },
  }

  connect () {
    let initial = this.defaultOpenValue
    if (this.rememberValue) {
      const saved = this.storageGet()
      if (saved != null) initial = saved
    }
    this.open = initial
    this.render()
  }

  toggle () {
    this.open = !this.open
    this.render()
    if (this.rememberValue) this.storageSet(this.open)
  }

  render () {
    if (this.hasContentTarget) this.contentTarget.classList.toggle('hidden', !this.open)
    if (this.hasIconTarget) this.iconTarget.style.transform = this.open ? 'rotate(180deg)' : 'rotate(0)'
    if (this.hasLabelTarget) this.labelTarget.textContent = this.open ? 'Hide' : 'Show'
  }

  storageKey () { return `collapsible:${this.keyValue || this.element.id || ''}` }
  storageGet () { try { const v = localStorage.getItem(this.storageKey()); return v == null ? null : v === 'true' } catch { return null } }
  storageSet (val) { try { localStorage.setItem(this.storageKey(), String(val)) } catch {} }
}
