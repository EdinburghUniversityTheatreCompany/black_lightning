module StarHelper
  def star_rating(rating)
    rating = rating.to_f

    return '' unless rating.present? && rating.positive?

    rating_decimal = rating - rating.floor
    
    half_star = rating_decimal >= 0.5

    stars = ''

    amount_of_stars = rating.floor
    (1..amount_of_stars).each do
      stars << '<i class="fas fa-star" aria-hidden=”true”></i>'
    end

    if half_star
      stars << '<i class="fas fa-star-half-alt" aria-hidden=”true”></i>'
    end

    stars << " (#{rating})" if (rating_decimal != 0.0 && rating_decimal != 0.5)

    return stars.html_safe
  end
end
