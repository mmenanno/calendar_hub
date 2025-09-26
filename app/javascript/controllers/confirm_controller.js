import { Controller } from "@hotwired/stimulus"

// Usage:
// - Add data-controller="confirm" and data-confirm-message-value="..." to a link or to the form created by button_to
// - For links using turbo_method, the default click will be re-triggered when confirmed.
// - For forms, we will submit the form after confirmation.
export default class extends Controller {
  static values = { message: String }

  connect () {
    this.boundOnClick = this.onClick.bind(this)
    this.element.addEventListener("click", this.boundOnClick, { capture: true })
  }

  disconnect () {
    this.element.removeEventListener("click", this.boundOnClick, { capture: true })
  }

  onClick (event) {
    // Only intercept primary clicks
    if (event.defaultPrevented) return
    if (event.button !== 0) return

    event.preventDefault()
    event.stopPropagation()

    this.openModal(this.messageValue || this.element.dataset.confirm)
      .then(confirmed => {
        if (!confirmed) return
        // If this is a FORM (button_to), submit it; otherwise submit/navigate explicitly
        if (this.element.tagName === 'FORM') {
          this.element.requestSubmit ? this.element.requestSubmit() : this.element.submit()
        } else {
          this.followLink(this.element)
        }
      })
  }

  openModal (message) {
    return new Promise(resolve => {
      const dialog = document.createElement('dialog')
      dialog.className = "rounded-xl border border-slate-800 bg-slate-900/90 text-slate-100 p-0 max-w-md w-[92vw]"
      // Ensure the dialog is centered consistently across browsers/resets
      dialog.style.position = 'fixed'
      dialog.style.inset = '0'
      dialog.style.margin = 'auto'
      dialog.innerHTML = `
        <form method="dialog" class="p-5">
          <h2 class="mb-2 text-base font-semibold">${this.escapeHtml(this.translate('title') || 'Please Confirm')}</h2>
          <p class="mb-5 text-sm text-slate-300">${this.escapeHtml(message || this.translate('default') || 'Are you sure?')}</p>
          <div class="flex justify-end gap-2">
            <button value="cancel" class="cursor-pointer rounded-lg border border-slate-700 px-3 py-2 text-sm text-slate-200 hover:border-slate-500">${this.escapeHtml(this.translate('cancel') || 'Cancel')}</button>
            <button value="confirm" class="cursor-pointer rounded-lg bg-rose-600 px-3 py-2 text-sm font-medium text-white hover:bg-rose-500">${this.escapeHtml(this.translate('confirm') || 'Confirm')}</button>
          </div>
        </form>`

      document.body.appendChild(dialog)
      dialog.addEventListener('close', () => {
        const ok = dialog.returnValue === 'confirm'
        dialog.remove()
        resolve(ok)
      })
      if (typeof dialog.showModal === 'function') {
        dialog.showModal()
      } else {
        // Fallback if <dialog> not supported
        const confirmed = window.confirm(message || 'Are you sure?')
        dialog.remove()
        resolve(confirmed)
      }
    })
  }

  followLink (el) {
    const href = el.getAttribute('href')
    if (!href) return

    const turboMethod = el.dataset.turboMethod || el.getAttribute('data-turbo-method')
    const method = (turboMethod || 'get').toLowerCase()
    // For GET just visit via Turbo
    if (method === 'get') {
      if (window.Turbo && Turbo.visit) {
        Turbo.visit(href)
      } else {
        window.location.href = href
      }
      return
    }

    // For non‑GET, build and submit a form so Turbo processes it correctly
    const form = document.createElement('form')
    form.method = 'post'
    form.action = href
    form.dataset.turbo = 'true'

    const token = document.querySelector('meta[name="csrf-token"]')
    if (token) {
      const input = document.createElement('input')
      input.type = 'hidden'
      input.name = 'authenticity_token'
      input.value = token.content
      form.appendChild(input)
    }

    if (method !== 'post') {
      const override = document.createElement('input')
      override.type = 'hidden'
      override.name = '_method'
      override.value = method.toUpperCase()
      form.appendChild(override)
    }

    document.body.appendChild(form)
    form.submit()
  }

  escapeHtml (str) {
    return (str || '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]))
  }

  translate (key) {
    const translations = {
      title: 'Please Confirm',
      default: 'Are you sure?',
      cancel: 'Cancel',
      confirm: 'Confirm'
    }
    return translations[key]
  }
}
