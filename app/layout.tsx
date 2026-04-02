import './globals.css'
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Quick Stick',
  manifest: '/manifest.webmanifest',
  icons: [
    { url: '/icons/icon-192.png', sizes: '192x192', type: 'image/png' },
    { url: '/icons/icon-512.png', sizes: '512x512', type: 'image/png' },
    { rel: 'apple-touch-icon', url: '/icons/icon-192.png' },
  ],
  other: {
    'theme-color': '#000000',
    'mobile-web-app-capable': 'yes',
    'apple-mobile-web-app-capable': 'yes',
    'apple-mobile-web-app-status-bar-style': 'black',
  },
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
