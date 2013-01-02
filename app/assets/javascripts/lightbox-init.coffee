$ ->
  # Some clever bits to allow the zoomable class to work
  $(".zoomable").each (i, item) ->
    $item = $(item)
    container = $("<a href='#{$item.attr("src")}/display' title='#{$item.attr("title")}' class='lightbox-single'></a>")
    new_img = $item.clone()
    new_img.src = $item.src + "/thumb"

    container.append(new_img)

    $item.replaceWith(container)
    return

  $(".lightbox a, .lightbox-single").lightBox
    imageLoading: "/images/lightbox-ico-loading.gif"
    imageBtnClose: "/images/lightbox-btn-close.gif"
    imageBtnPrev: "/images/lightbox-btn-prev.gif"
    imageBtnNext: "/images/lightbox-btn-next.gif"
    imageBlank: "/images/lightbox-blank.gif"

  return
return