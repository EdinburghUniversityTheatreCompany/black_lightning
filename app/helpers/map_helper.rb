module MapHelper
    def bedlam_latlng
        return [55.946324, -3.190721]
    end

    def venue_map(venue)
        return map(center: { latlng: venue.latlng, zoom: 16 }, markers: [venue.marker_info])
    end
end
