import { Controller } from "@hotwired/stimulus"

/**
 * Base controller with common utilities for all Stimulus controllers
 */
export default class BaseController extends Controller {
  /**
   * Get CSRF token from meta tag
   * @returns {string|null} CSRF token or null if not found
   */
  getCsrfToken() {
    const token = document.querySelector('meta[name="csrf-token"]')
    return token ? token.content : null
  }

  /**
   * Make a fetch request with CSRF token and common headers
   * @param {string} url - The URL to fetch
   * @param {Object} options - Fetch options (method, body, etc.)
   * @returns {Promise<Response>} Fetch promise
   */
  async fetchWithCsrf(url, options = {}) {
    const token = this.getCsrfToken()
    const { headers: customHeaders, ...restOptions } = options
    const defaultHeaders = {
      'X-CSRF-Token': token || '',
      'Accept': 'text/vnd.turbo-stream.html'
    }

    return fetch(url, {
      credentials: 'same-origin',
      ...restOptions,
      headers: { ...defaultHeaders, ...customHeaders },
    })
  }

  /**
   * Submit a form using requestSubmit with fallback
   * @param {HTMLFormElement} form - The form to submit
   */
  submitForm(form) {
    if (!form) return

    if (form.requestSubmit) {
      form.requestSubmit()
    } else {
      form.submit()
    }
  }

  /**
   * Render Turbo stream response
   * @param {string} html - HTML response to render
   */
  renderTurboStream(html) {
    if (html && html.trim() && window.Turbo && typeof window.Turbo.renderStreamMessage === 'function') {
      window.Turbo.renderStreamMessage(html)
    }
  }

  /**
   * Show a client-side toast in #toast-anchor (mirrors app/views/shared/_toast.html.erb)
   * @param {string} message - Plain-text message
   * @param {'success'|'error'} variant - Toast style
   */
  showToast(message, variant = 'success') {
    const anchor = document.getElementById('toast-anchor')
    if (!anchor) return

    const error = variant === 'error'
    const toast = document.createElement('div')
    toast.className = 'pointer-events-auto max-w-sm rounded-lg border px-3 py-2 text-sm shadow-lg backdrop-blur'
    toast.style.background = 'rgba(15,23,42,.9)'
    toast.style.borderColor = 'rgba(51,65,85,.7)'
    toast.dataset.controller = 'dismissable'
    toast.dataset.dismissableDelayValue = error ? '8000' : '2500'
    toast.innerHTML = `
      <div class="flex items-start gap-2">
        <span class="mt-0.5 inline-flex h-4 w-4 shrink-0 items-center justify-center rounded-full ${error ? 'bg-rose-500/20 text-rose-300' : 'bg-emerald-500/20 text-emerald-300'}" aria-hidden="true">${error ? '!' : '✓'}</span>
        <span class="min-w-0 flex-1 break-words text-slate-200">${error ? '<span class="sr-only">Error: </span>' : ''}${this.escapeHtml(message)}</span>
        <button type="button" class="-mr-1 shrink-0 cursor-pointer rounded px-1 leading-none text-slate-400 transition hover:text-slate-200" data-action="dismissable#dismiss" aria-label="Dismiss notification">&times;</button>
      </div>
      <div class="pointer-events-none mt-1 h-0.5 w-full bg-transparent">
        <div class="h-full w-0 ${error ? 'bg-rose-400/60' : 'bg-emerald-400/60'}" data-dismissable-target="progress"></div>
      </div>`
    anchor.appendChild(toast)
  }

  /**
   * Create a debounced function
   * @param {Function} func - Function to debounce
   * @param {number} delay - Delay in milliseconds
   * @returns {Function} Debounced function
   */
  debounce(func, delay) {
    let timeoutId
    return (...args) => {
      clearTimeout(timeoutId)
      timeoutId = setTimeout(() => func.apply(this, args), delay)
    }
  }

  /**
   * Set loading state on a button
   * @param {HTMLButtonElement} button - Button element
   * @param {boolean} loading - Whether button is loading
   * @param {string} loadingText - Text to show when loading
   */
  setButtonLoading(button, loading, loadingText = 'Loading...') {
    if (!button) return

    if (loading) {
      button.dataset.originalText = button.innerHTML
      button.disabled = true
      button.innerHTML = `<span class="inline-flex items-center gap-2">
        <svg class="h-4 w-4 animate-spin text-slate-300" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z"></path>
        </svg>
        ${loadingText}
      </span>`
    } else {
      button.disabled = false
      button.innerHTML = button.dataset.originalText || button.innerHTML
    }
  }

  /**
   * Escape HTML to prevent XSS
   * @param {string} str - String to escape
   * @returns {string} Escaped string
   */
  escapeHtml(str) {
    return (str || '').replace(/[&<>"']/g, c => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;'
    }[c]))
  }
}
