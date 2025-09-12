module StarHelper
  def star_rating(rating)
    rating = rating.to_f

    # Return empty if there is no valid rating.
    return "" unless rating.present? && rating.positive?

    rating_decimal = rating - rating.floor

    half_star = rating_decimal >= 0.5

    stars = ""

    # Appends a star equal to the whole number part of the rating.
    amount_of_stars = rating.floor
    (1..amount_of_stars).each do
      stars << '<i class="fas fa-star" aria-hidden=”true”></i>'
    end

    # Appends a half star if the decimal part >= 0.5
    if half_star
      stars << '<i class="fas fa-star-half-alt" aria-hidden=”true”></i>'
    end

    # Only multiples of 0.5 can be shown in visual stars, so this appensd the numeric rating
    # if the rating is not a multiple of 0.5. The number of stars shown will be rounded down.

    stars << " (#{rating})" if rating_decimal != 0.0 && rating_decimal != 0.5

    stars.html_safe
  end
end
