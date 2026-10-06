import { config } from './config'
import type { Session } from './types'

// Sign-in uses the authorization code flow with PKCE. The code is redeemed by the agent
// service, which holds the client secret; the browser only ever holds the resulting tokens,
// in sessionStorage so they last for the tab and survive a reload.

const SESSION_KEY = 'devportal-agent.session'
const PENDING_KEY = 'devportal-agent.pending-sign-in'

interface PendingSignIn {
  state: string
  codeVerifier: string
}

const base64Url = (bytes: Uint8Array): string =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

const randomString = (): string => base64Url(crypto.getRandomValues(new Uint8Array(32)))

export const loadSession = (): Session | null => {
  const stored = sessionStorage.getItem(SESSION_KEY)
  if (!stored) {
    return null
  }
  const session = JSON.parse(stored) as Session
  if (session.expiresAt <= Date.now()) {
    sessionStorage.removeItem(SESSION_KEY)
    return null
  }
  return session
}

export const clearSession = (): void => sessionStorage.removeItem(SESSION_KEY)

export const startSignIn = async (): Promise<void> => {
  const pending: PendingSignIn = { state: randomString(), codeVerifier: randomString() }
  sessionStorage.setItem(PENDING_KEY, JSON.stringify(pending))
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(pending.codeVerifier))
  const query = new URLSearchParams({
    response_type: 'code',
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    scope: config.scopes,
    state: pending.state,
    code_challenge: base64Url(new Uint8Array(digest)),
    code_challenge_method: 'S256',
  })
  window.location.assign(`${config.authorizeUrl}?${query}`)
}

const redeemCode = async (callbackQuery: URLSearchParams): Promise<Session> => {
  const problem = callbackQuery.get('error_description') ?? callbackQuery.get('error')
  if (problem) {
    throw new Error(problem)
  }
  const code = callbackQuery.get('code')
  const stored = sessionStorage.getItem(PENDING_KEY)
  sessionStorage.removeItem(PENDING_KEY)
  const pending = stored ? (JSON.parse(stored) as PendingSignIn) : null
  if (!code || !pending || pending.state !== callbackQuery.get('state')) {
    throw new Error('The sign-in response did not match a request from this browser tab.')
  }
  const response = await fetch(`${config.agentUrl}/auth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, codeVerifier: pending.codeVerifier, redirectUri: config.redirectUri }),
  })
  const body = await response.json()
  if (!response.ok) {
    throw new Error(body.message ?? 'Sign-in failed.')
  }
  const session: Session = {
    accessToken: body.accessToken,
    idToken: body.idToken,
    userName: body.userName,
    expiresAt: Date.now() + body.expiresIn * 1000,
  }
  sessionStorage.setItem(SESSION_KEY, JSON.stringify(session))
  return session
}

// An authorization code works once, but React's development mode runs effects twice.
let signInCompletion: Promise<Session> | null = null

export const completeSignIn = (callbackQuery: URLSearchParams): Promise<Session> => {
  signInCompletion ??= redeemCode(callbackQuery)
  return signInCompletion
}

export const signOut = (session: Session): void => {
  clearSession()
  const query = new URLSearchParams({
    id_token_hint: session.idToken,
    post_logout_redirect_uri: config.redirectUri,
  })
  window.location.assign(`${config.logoutUrl}?${query}`)
}
