module StarHelper
  def star_rating(rating)
    half_star = rating.to_i != rating

    stars = ''

    for i in 1..rating.floor
      stars << '<i class="icon-star"></i>'
    end

    if half_star
      stars << '<i class="icon-star-half"></i>'
    end

    return stars.html_safe
  end
end
