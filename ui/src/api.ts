import { config } from './config'
import type { ChatResponse, Session } from './types'

// Thrown when the agent no longer accepts the user's token.
export class SessionExpiredError extends Error {}

const post = async (session: Session, path: string, body: unknown): Promise<ChatResponse> => {
  const response = await fetch(`${config.agentUrl}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.accessToken}` },
    body: JSON.stringify(body),
  })
  if (response.status === 401) {
    throw new SessionExpiredError('Your session has expired.')
  }
  const payload = await response.json()
  if (!response.ok) {
    throw new Error(payload.message ?? 'The assistant could not complete the request.')
  }
  return payload as ChatResponse
}

export const sendMessage = (session: Session, sessionId: string, message: string): Promise<ChatResponse> =>
  post(session, '/chat', { sessionId, message })

export const sendDecision = (
  session: Session,
  sessionId: string,
  approvalId: string,
  approved: boolean,
): Promise<ChatResponse> => post(session, '/chat/decisions', { sessionId, decisions: [{ id: approvalId, approved }] })
