import { useEffect, useState } from 'react'

export default function InstallPromptBanner() {
  const [showInstall, setShowInstall] = useState(false)
  const [deferredPrompt, setDeferredPrompt] = useState<any>(null)

  useEffect(() => {
    window.addEventListener('beforeinstallprompt', (e) => {
      // Prevent Chrome 67 and earlier from automatically showing the prompt
      e.preventDefault()
      // Stash the event so it can be triggered later.
      setDeferredPrompt(e)
      setShowInstall(true)
    })
    window.addEventListener('appinstalled', () => {
      setShowInstall(false)
      setDeferredPrompt(null)
    })
  }, [])

  const installPWA = async () => {
    if (deferredPrompt) {
      // Show the prompt
      deferredPrompt.prompt()
      // Wait for the user to respond to the prompt
      const choiceResult = await deferredPrompt.userChoice
      if (choiceResult.outcome === 'accepted') {
        console.log('User accepted the install prompt')
      } else {
        console.log('User dismissed the install prompt')
      }
      setDeferredPrompt(null)
      setShowInstall(false)
    }
  }

  return (
    showInstall && (
      <div className="fixed bottom-4 left-4 right-4 bg-green-600 text-white px-4 py-3 rounded-lg shadow-lg z-50 flex items-center justify-between">
        <div className="flex-1">
          Install Claudelance for a better offline experience?
        </div>
        <button onClick={installPWA} className="bg-white text-green-600 px-3 py-1 rounded">
          Install
        </button>
        <button onClick={() => setShowInstall(false)} className="text-white hover:underline ml-2">
          Close
        </button>
      </div>
    )
  )
}
