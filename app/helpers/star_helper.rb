module StarHelper
  def star_rating(rating)
    rating = rating.to_f

    half_star = rating.floor != rating

    stars = ''

    amount_of_stars = rating.floor
    (1..amount_of_stars).each do
      stars << '<i class="fas fa-star" aria-hidden=”true”></i>'
    end

    if half_star
      stars << '<i class="fas fa-star-half-alt" aria-hidden=”true”></i>'
    end

    return stars.html_safe
  end
end
