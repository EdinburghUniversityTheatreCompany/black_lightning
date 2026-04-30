// IT committee easter egg — triggered by the Konami code via konami_code_controller.js.
//
// Images live in app/assets/images/easter_egg/ and are resolved server-side by
// ItifyHelper, which passes fingerprinted asset URLs to the Stimulus controller
// via data-konami-code-heads-value / data-konami-code-pineapple-value.
// Call itify_init(headsArray, pineappleUrl) once on controller connect before
// calling itify_add().

var itify_count = 0
var HEADS = []
var PINEAPPLE_URL = null

var itify_init = function (heads, pineappleUrl) {
  HEADS = Array.isArray(heads) ? heads : []
  PINEAPPLE_URL = pineappleUrl || null
  itify_count = 0
}

var itify_add = function () {
  if (HEADS.length === 0) {
    console.warn('[itify] No head images available. Check ItifyHelper and data-konami-code-heads-value.')
    return
  }

  itify_count += 1

  var showGrandHead = itify_count === 15

  var div = document.createElement('div')
  div.style.position = 'fixed'
  div.className = '__itify_head'
  div.style.zIndex = showGrandHead ? '143143143' : '143143'
  div.style.outline = '0'
  div.style.transform = 'translate(-50%, -50%)'
  div.onclick = itify_add

  if (showGrandHead) {
    div.style.top = '50%'
    div.style.left = '50%'
  } else {
    var angle = Math.round(Math.random() * 10 - 5)
    div.style.top = Math.round(Math.random() * 100) + '%'
    div.style.left = Math.round(Math.random() * 100) + '%'
    div.style.transform += ' rotate(' + angle + 'deg)'
  }

  var img = document.createElement('img')
  img.style.opacity = '0'
  img.style.transition = 'all .1s linear'
  img.style.maxHeight = '200px'
  img.alt = 'IT committee member'
  img.onload = function () { img.style.opacity = '1' }
  img.src = HEADS[Math.floor(Math.random() * HEADS.length)]

  div.onmouseover = function () {
    var size = 1 + Math.round(Math.random() * 10) / 100
    var a = Math.round(Math.random() * 20 - 10)
    img.style.transform = 'rotate(' + a + 'deg) scale(' + size + ',' + size + ')'
  }
  div.onmouseout = function () {
    var size = 0.9 + Math.round(Math.random() * 10) / 100
    var a = Math.round(Math.random() * 6 - 3)
    img.style.transform = 'rotate(' + a + 'deg) scale(' + size + ',' + size + ')'
  }

  div.appendChild(img)
  document.getElementsByTagName('body')[0].appendChild(div)

  if (itify_count === 5) {
    itify_activate_terminal()
    itify_add_pineapple_button()
  }

  itify_updatecount()
}

var itify_updatecount = function () {
  var id = '__itify_count'
  var p = document.getElementById(id)

  if (p == null) {
    p = document.createElement('p')
    p.id = id
    p.style.position = 'fixed'
    p.style.bottom = '5px'
    p.style.left = '0px'
    p.style.right = '0px'
    p.style.zIndex = '1000000000'
    p.style.color = '#00ff00'
    p.style.textAlign = 'center'
    p.style.fontSize = '24px'
    p.style.fontFamily = "'Courier New', monospace"
    p.style.textTransform = 'uppercase'
    document.getElementsByTagName('body')[0].appendChild(p)
  }

  p.innerHTML = itify_count === 1 ? 'You ITified!' : 'You ITified ' + itify_count + ' times!'
}

var itify_activate_terminal = function () {
  if (!document.getElementById('__itify_css')) {
    var style = document.createElement('style')
    style.id = '__itify_css'
    style.textContent = [
      'body.itified::before {',
      '  content: "";',
      '  position: fixed;',
      '  inset: 0;',
      '  background: #808080;',
      '  mix-blend-mode: color;',
      '  z-index: 99998;',
      '  pointer-events: none;',
      '}',
      'body.itified h1,',
      'body.itified h2,',
      'body.itified h3,',
      'body.itified h4,',
      'body.itified h5,',
      'body.itified h6 {',
      '  position: relative;',
      '  z-index: 99999;',
      '  color: #00ff00 !important;',
      '}'
    ].join('\n')
    document.getElementsByTagName('head')[0].appendChild(style)
  }

  document.getElementsByTagName('body')[0].classList.add('itified')

  var words = ['Deployed', 'Optimised', 'Refactored', 'Compiled', 'Patched', 'Shipped', 'Debugged', 'Merged']
  var level = 6
  while (level >= 1) {
    var headers = document.getElementsByTagName('h' + level)
    for (var i = 0; i < headers.length; i++) {
      headers[i].innerHTML = words[Math.floor(Math.random() * words.length)] + ' ' + headers[i].innerHTML
    }
    level -= 1
  }
}

var itify_add_pineapple_button = function () {
  if (document.getElementById('__itify_pineapple_button')) return

  var button = document.createElement('div')
  button.id = '__itify_pineapple_button'
  button.onclick = itify_click_pineapple_button
  button.style.position = 'fixed'
  button.style.top = '10px'
  button.style.right = '10px'
  button.style.zIndex = '2147483640'
  button.setAttribute('aria-label', 'Hide the IT committee')

  if (PINEAPPLE_URL) {
    var img = document.createElement('img')
    img.src = PINEAPPLE_URL
    img.alt = 'Pineapple button'
    img.style.maxHeight = '150px'
    img.style.width = 'auto'
    img.style.cursor = 'pointer'
    img.style.display = 'block'
    button.appendChild(img)
  } else {
    button.textContent = '🍍'
    button.style.fontSize = '40px'
    button.style.cursor = 'pointer'
  }

  document.getElementsByTagName('body')[0].appendChild(button)
}

var itify_click_pineapple_button = function () {
  var body = document.getElementsByTagName('body')[0]

  var heads = document.getElementsByClassName('__itify_head')
  while (heads.length > 0) {
    heads[0].parentNode.removeChild(heads[0])
  }

  var count = document.getElementById('__itify_count')
  if (count) count.parentNode.removeChild(count)

  var button = document.getElementById('__itify_pineapple_button')
  if (button) button.parentNode.removeChild(button)

  var css = document.getElementById('__itify_css')
  if (css) css.parentNode.removeChild(css)

  body.classList.remove('itified')
  itify_count = 0
}

export default itify_add
export { itify_init, itify_add, itify_add_pineapple_button, itify_click_pineapple_button }
