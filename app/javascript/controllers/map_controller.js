import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    center: Array,
    zoom: Number,
    markers: { type: Array, default: [] }
  }

  async connect() {
    const [L] = await Promise.all([
      import("leaflet").then(m => m.default),
      import("leaflet/dist/leaflet.css"),
    ])

    // Leaflet finds its icons through CSS, which breaks once bundled, so drop the
    // detection and point at the copies in public/leaflet/.
    delete L.Icon.Default.prototype._getIconUrl
    L.Icon.Default.mergeOptions({
      iconUrl: "/leaflet/marker-icon.png",
      iconRetinaUrl: "/leaflet/marker-icon-2x.png",
      shadowUrl: "/leaflet/marker-shadow.png",
    })

    this.map = L.map(this.element).setView(this.centerValue, this.zoomValue)

    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 18,
      attribution: '&copy; <a href="http://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(this.map)

    this.markersValue.forEach(({ latlng, popup, open_popup }) => {
      const marker = L.marker(latlng).addTo(this.map)
      if (popup) {
        marker.bindPopup(popup)
        if (open_popup) marker.openPopup()
      }
    })
  }

  disconnect() {
    this.map?.remove()
  }
}
