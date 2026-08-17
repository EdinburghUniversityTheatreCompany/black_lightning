import { Controller } from "@hotwired/stimulus"

const STYLESHEET_PATH = "widget/v1.css"
const SCRIPT_PATH = "widget/v1.en.js"
const SCRIPT_ID = "pretix-widget-script"

// Opens the pretix ticket widget in a dialog, loading pretix's assets on first use.
//
// The base URL defaults to the shop's own domain and must stay in step with
// PretixHelper::SHOP_URL — pretix.eu serves no widget stylesheet (v1.en.css there redirects to
// a 404), so both the script and the CSS come from the shop itself.
export default class extends Controller {
  static targets = ["dialog", "widgetContainer", "title"]
  static values = {
    baseUrl: { type: String, default: "https://tickets.bedlamtheatre.co.uk/" },
    listType: { type: String, default: "list" }
  }

  #eventUrl = null

  open({ params: { slug, name } }) {
    if (this.hasTitleTarget && name) this.titleTarget.textContent = name
    this.#loadPretixAssets()
    this.#buildWidget(`${this.baseUrlValue}${slug}/`)
    this.dialogTarget.showModal()
  }

  // pretix replaces the <pretix-widget> element with its own rendered markup as soon as it
  // builds it, so the element can only be configured once — setting `event` on what it leaves
  // behind is writing to markup nothing reads, and every later open would keep showing the
  // first show. Drop in a fresh element instead and ask pretix to build that.
  #buildWidget(eventUrl) {
    if (this.#eventUrl === eventUrl) {
      this.widgetContainerTarget.scrollTop = 0
      return
    }
    this.#eventUrl = eventUrl

    const widget = document.createElement("pretix-widget")
    widget.setAttribute("event", eventUrl)
    widget.setAttribute("list-type", this.listTypeValue)
    this.widgetContainerTarget.replaceChildren(widget)
    this.widgetContainerTarget.scrollTop = 0

    // On the first open the script is still loading and builds this widget itself once ready;
    // after that nothing watches the DOM, so new elements have to be announced.
    window.PretixWidget?.buildWidgets()
  }

  #loadPretixAssets() {
    const stylesheetUrl = `${this.baseUrlValue}${STYLESHEET_PATH}`
    // A show page adds the same stylesheet and script, and Turbo keeps head elements across
    // visits — so match on what is actually loaded rather than on our own markers alone.
    if (!document.querySelector(`link[href="${stylesheetUrl}"]`)) {
      const link = document.createElement("link")
      link.rel = "stylesheet"
      link.href = stylesheetUrl
      document.head.appendChild(link)
    }

    if (window.PretixWidget || document.getElementById(SCRIPT_ID)) return

    const script = document.createElement("script")
    script.id = SCRIPT_ID
    script.src = `${this.baseUrlValue}${SCRIPT_PATH}`
    script.async = true
    document.head.appendChild(script)
  }
}
