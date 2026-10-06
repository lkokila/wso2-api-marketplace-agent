import Box from '@mui/material/Box'
import CircularProgress from '@mui/material/CircularProgress'
import { useEffect, useState } from 'react'
import { clearSession, completeSignIn, loadSession } from './auth'
import Chat from './components/Chat'
import SignIn from './components/SignIn'
import type { Session } from './types'

const CALLBACK_PATH = '/callback'

export default function App() {
  const [session, setSession] = useState<Session | null>(loadSession)
  const [signInError, setSignInError] = useState<string | null>(null)
  const callbackQuery = new URLSearchParams(window.location.search)
  // The identity provider returns here after sign-in (with a code) and after sign-out (without).
  const redeeming = window.location.pathname === CALLBACK_PATH && (callbackQuery.has('code') || callbackQuery.has('error'))

  useEffect(() => {
    if (window.location.pathname !== CALLBACK_PATH) {
      return
    }
    if (!redeeming) {
      window.history.replaceState(null, '', '/')
      return
    }
    completeSignIn(new URLSearchParams(window.location.search))
      .then(setSession)
      .catch((error: Error) => setSignInError(error.message))
      .finally(() => window.history.replaceState(null, '', '/'))
  }, [redeeming])

  if (session) {
    return (
      <Chat
        session={session}
        onSessionExpired={() => {
          clearSession()
          setSession(null)
          setSignInError('Your session has expired. Please sign in again.')
        }}
      />
    )
  }
  if (redeeming && !signInError) {
    return (
      <Box sx={{ height: '100%', display: 'grid', placeItems: 'center' }}>
        <CircularProgress />
      </Box>
    )
  }
  return <SignIn error={signInError} />
}
