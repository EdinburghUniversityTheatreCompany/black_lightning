// pretix's script builds every <pretix-widget> on the page once, at the moment it runs, and
// nothing watches the DOM afterwards. Under Turbo that moment is always the wrong one: the
// script is appended to the head *before* the new body is swapped in, so it can build against
// the page being navigated away from — and on every later visit Turbo keeps the identical
// <script> tag and never re-runs it, so nothing builds a widget again until a full reload.
//
// So the build is taken over here, the way pretix documents for single-page apps: its
// self-build is switched off through pretixWidgetCallback and buildWidgets() is called once
// the element is in place.

const STYLESHEET_PATH = "widget/v1.css"
const SCRIPT_PATH = "widget/v1.en.js"

let loading = null

// Readiness is the builder, never window.PretixWidget itself: the bundle assigns that object
// near its start and buildWidgets at its very end, so a script that throws halfway — or that
// 200s with something other than the widget — leaves the object behind with nothing to build.
const readyWidget = () => (window.PretixWidget?.buildWidgets ? window.PretixWidget : null)

export function loadPretix(baseUrl) {
  ensureStylesheet(baseUrl)

  const pretix = readyWidget()
  if (pretix) return Promise.resolve(pretix)
  if (loading) return loading

  window.pretixWidgetCallback = () => { window.PretixWidget.build_widgets = false }

  loading = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = `${baseUrl}${SCRIPT_PATH}`
    script.async = true

    const fail = (message) => {
      script.remove()
      loading = null
      reject(new Error(message))
    }

    script.addEventListener("load", () => {
      const loaded = readyWidget()
      if (loaded) resolve(loaded)
      else fail(`The pretix widget script at ${script.src} defined no widget builder`)
    })
    script.addEventListener("error", () => fail(`The pretix widget could not be loaded from ${script.src}`))

    document.head.appendChild(script)
  })

  return loading
}

// Resolves with whether a widget was actually built, and never rejects: no caller is in a
// position to handle a failure better than the shop link put in its place.
//
// A fresh element every time is not tidiness: building a widget *replaces* the <pretix-widget>
// element with pretix's own markup, so an element can only ever be configured once. Turbo's
// cached snapshot of a show page holds that spent markup — a widget that looks right and does
// nothing — and the modal would otherwise keep showing the first show that was clicked.
export async function buildWidget(container, { baseUrl, eventUrl, listType }) {
  const widget = document.createElement("pretix-widget")
  widget.setAttribute("event", eventUrl)
  if (listType) widget.setAttribute("list-type", listType)
  container.replaceChildren(widget)
  container.scrollTop = 0

  let pretix
  try {
    pretix = await loadPretix(baseUrl)
  } catch (error) {
    console.warn(error) // eslint-disable-line no-console
    renderShopLink(container, eventUrl)
    return false
  }

  // The page can have moved on while the script loaded. buildWidgets() defers its own DOM scan
  // by a tick, so this is read slightly early rather than atomically — but a widget still
  // waiting elsewhere is picked up by its own call.
  if (!widget.isConnected) return false

  // Captured once, when the bundle ran, which is now whichever page first needed a widget —
  // so without this every sale for the rest of the session is attributed to that page.
  pretix.widget_data.referer = location.href
  pretix.buildWidgets()
  return true
}

// The <noscript> fallback is no help when the shop is down but JavaScript is working fine, and
// an empty box tells a visitor nothing about where else to buy a ticket.
function renderShopLink(container, eventUrl) {
  const message = document.createElement("div")
  message.className = "pretix-widget-info-message"
  const link = document.createElement("a")
  link.href = eventUrl
  link.target = "_blank"
  link.rel = "noopener"
  link.textContent = "open our ticket shop"
  message.append("The ticket shop could not be loaded here — please ", link, " instead.")
  container.replaceChildren(message)
}

function ensureStylesheet(baseUrl) {
  const href = `${baseUrl}${STYLESHEET_PATH}`
  // A show page links this itself and Turbo keeps head elements across visits, so match on what
  // is loaded rather than on a marker of our own.
  if (document.querySelector(`link[href="${href}"]`)) return

  const link = document.createElement("link")
  link.rel = "stylesheet"
  link.href = href
  document.head.appendChild(link)
}
