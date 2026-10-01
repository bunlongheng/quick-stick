import './globals.css'
import type { Metadata, Viewport } from 'next'
import { Doto, IBM_Plex_Sans } from 'next/font/google'

// Swap the whole look from here: change the import and these two loaders.
// Everything downstream reads --qs-display / --qs-body.
// Doto is the dot-matrix face the FC app titles with.
const display = Doto({
  subsets: ['latin'],
  variable: '--qs-display',
  display: 'swap',
})

const body = IBM_Plex_Sans({
  weight: ['400', '500'],
  subsets: ['latin'],
  variable: '--qs-body',
  display: 'swap',
})

// The board is the screen. No zoom, no bounce, and the keyboard shrinks the
// page instead of shoving it up.
export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  viewportFit: 'cover',
  interactiveWidget: 'resizes-content',
}

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
    <html lang="en" className={`${display.variable} ${body.variable}`}>
      <body>{children}</body>
    </html>
  )
}
