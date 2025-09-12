module MapHelper
    def bedlam_latlng
        [ 55.946324, -3.190721 ]
    end

    def venue_map(venue)
        return "The map could not be displayed because the venue does not have location data set" if venue.latlng.nil?

        map(center: { latlng: venue.latlng, zoom: 16 }, markers: [ venue.marker_info(true) ])
    end
end
