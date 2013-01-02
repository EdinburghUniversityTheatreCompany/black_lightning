$ ->
  # Some clever bits to allow the zoomable class to work
  $(".zoomable").each (i, item) ->
    $item = $(item)

    title = $item.attr("title") || ""
    container = $("<a href='#{$item.attr("src")}/display' title='#{title}' class='lightbox-single'></a>")
    new_img = $item.clone()
    new_img.attr('src', $item.attr('src') + "/thumb")

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