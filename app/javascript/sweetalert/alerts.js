// Uses the Toast and PersistentToast method defined in the index.js file to display flash messages.

// Flash messages carry names, titles and URL values people typed, so they only ever become text:
// SweetAlert's titleText, or elements filled with text nodes. Never a string of HTML.
function messageList(messages) {
  const list = document.createElement('ul')
  for (const message of messages) {
    const item = document.createElement('li')
    item.textContent = message
    list.append(item)
  }
  return list
}

function toastTitle(messages) {
  return messages.length === 1 ? { titleText: messages[0] } : { title: messageList(messages) }
}

async function showToast(alert_type, messages) {
  await Toast.fire({
  icon: alert_type,
  ...toastTitle(messages)
  })
}

async function showPersistentToast (alert_type, messages) {
  await PersistentToast.fire({
  icon: alert_type,
  ...toastTitle(messages),
  position: 'top'
  })
}

async function showError (messages) {
  // On an inner element, not customClass: SweetAlert's unlayered CSS centres its container and
  // outranks Tailwind's layered text-justify there.
  const content = document.createElement('div')
  content.className = 'text-justify'
  content.append(messages.length === 1 ? messages[0] : messageList(messages))

  await Swal.fire({
  icon: 'error',
  title: 'Oops...',
  html: content,
  allowOutsideClick: () => {
      const popup = Swal.getPopup()
      popup.classList.remove('swal2-show')
      setTimeout(() => {
      popup.classList.add('animate__animated', 'animation__shake')
      })
      setTimeout(() => {
      popup.classList.remove('animate__animated', 'animation__shake')
      }, 500)
      return false
  }
  })
}
// Render each type's messages. If the type is not success or error, it will be rendered as a persistent toast.
export async function showFlashAlerts(flash) {
  for (const [alertType, messages] of Object.entries(flash)) {
    switch (alertType) {
      case 'success':
        await showToast(alertType, messages);
        break;
      case 'error':
        await showError(messages);
        break;
      default:
        await showPersistentToast(alertType, messages);
        break;
    }
  }
}

// Make this available to inline methods.
window.showFlashAlerts = showFlashAlerts;
