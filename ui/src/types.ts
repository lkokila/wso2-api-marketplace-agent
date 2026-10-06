// Shapes of the agent's chat API (see agent/README.md).

export interface Session {
  accessToken: string
  idToken: string
  userName: string
  expiresAt: number
}

export interface ApprovalDetail {
  label: string
  value: string
}

export interface Approval {
  id: string
  toolName: string
  action: string
  details: ApprovalDetail[]
}

export interface Credential {
  name: string
  value: string
  consumerKey?: string
}

export interface ChatResponse {
  status: 'COMPLETED' | 'APPROVAL_REQUIRED'
  message: string
  approvals: Approval[]
  credentials: Credential[]
}

export type ApprovalOutcome = 'pending' | 'approved' | 'rejected'

// One entry in the conversation as the user sees it.
export type ChatItem =
  | { kind: 'user'; id: string; text: string }
  | { kind: 'assistant'; id: string; text: string }
  | { kind: 'approval'; id: string; approval: Approval; outcome: ApprovalOutcome }
  | { kind: 'credentials'; id: string; credentials: Credential[] }
  | { kind: 'error'; id: string; text: string }
