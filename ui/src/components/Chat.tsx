import AddCommentOutlinedIcon from '@mui/icons-material/AddCommentOutlined'
import LogoutIcon from '@mui/icons-material/Logout'
import SendIcon from '@mui/icons-material/Send'
import Alert from '@mui/material/Alert'
import AppBar from '@mui/material/AppBar'
import Box from '@mui/material/Box'
import Button from '@mui/material/Button'
import CircularProgress from '@mui/material/CircularProgress'
import Container from '@mui/material/Container'
import IconButton from '@mui/material/IconButton'
import Paper from '@mui/material/Paper'
import Stack from '@mui/material/Stack'
import TextField from '@mui/material/TextField'
import Toolbar from '@mui/material/Toolbar'
import Tooltip from '@mui/material/Tooltip'
import Typography from '@mui/material/Typography'
import { useEffect, useRef, useState } from 'react'
import Markdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { sendDecision, sendMessage, SessionExpiredError } from '../api'
import { signOut } from '../auth'
import type { ApprovalOutcome, ChatItem, ChatResponse, Session } from '../types'
import ApprovalCard from './ApprovalCard'
import CredentialCard from './CredentialCard'

const suggestions = [
  'What APIs are available?',
  'What applications do I have?',
  'Help me start calling an API from a new application.',
]

interface ChatProps {
  session: Session
  onSessionExpired: () => void
}

export default function Chat({ session, onSessionExpired }: ChatProps) {
  const [conversationId, setConversationId] = useState(() => crypto.randomUUID())
  const [items, setItems] = useState<ChatItem[]>([])
  const [draft, setDraft] = useState('')
  const [busy, setBusy] = useState(false)
  const endOfList = useRef<HTMLDivElement>(null)
  const awaitingApproval = items.some((item) => item.kind === 'approval' && item.outcome === 'pending')

  useEffect(() => {
    endOfList.current?.scrollIntoView({ behavior: 'smooth' })
  }, [items, busy])

  const append = (...newItems: ChatItem[]) => setItems((current) => [...current, ...newItems])

  const showResponse = (response: ChatResponse) => {
    const newItems: ChatItem[] = []
    if (response.message) {
      newItems.push({ kind: 'assistant', id: crypto.randomUUID(), text: response.message })
    }
    if (response.credentials.length > 0) {
      newItems.push({ kind: 'credentials', id: crypto.randomUUID(), credentials: response.credentials })
    }
    for (const approval of response.approvals) {
      newItems.push({ kind: 'approval', id: approval.id, approval, outcome: 'pending' })
    }
    append(...newItems)
  }

  const run = async (request: () => Promise<ChatResponse>) => {
    setBusy(true)
    try {
      showResponse(await request())
    } catch (error) {
      if (error instanceof SessionExpiredError) {
        onSessionExpired()
        return
      }
      append({ kind: 'error', id: crypto.randomUUID(), text: (error as Error).message })
    } finally {
      setBusy(false)
    }
  }

  const submit = (text: string) => {
    const message = text.trim()
    if (!message || busy || awaitingApproval) {
      return
    }
    setDraft('')
    append({ kind: 'user', id: crypto.randomUUID(), text: message })
    void run(() => sendMessage(session, conversationId, message))
  }

  const decide = (approvalId: string, approved: boolean) => {
    const outcome: ApprovalOutcome = approved ? 'approved' : 'rejected'
    setItems((current) =>
      // Drop other still-pending cards: the response lists whatever remains to be decided.
      current
        .filter((item) => item.kind !== 'approval' || item.outcome !== 'pending' || item.id === approvalId)
        .map((item) => (item.kind === 'approval' && item.id === approvalId ? { ...item, outcome } : item)),
    )
    void run(() => sendDecision(session, conversationId, approvalId, approved))
  }

  const startNewConversation = () => {
    setConversationId(crypto.randomUUID())
    setItems([])
    setDraft('')
  }

  return (
    <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      <AppBar position="static" color="inherit" elevation={0} sx={{ borderBottom: 1, borderColor: 'divider' }}>
        <Toolbar sx={{ gap: 1 }}>
          <Typography variant="h6" component="h1" sx={{ flexGrow: 1, fontWeight: 700 }}>
            Developer Portal Assistant
          </Typography>
          <Button startIcon={<AddCommentOutlinedIcon />} color="inherit" onClick={startNewConversation} disabled={busy}>
            New chat
          </Button>
          <Typography variant="body2" color="text.secondary" sx={{ display: { xs: 'none', sm: 'block' } }}>
            {session.userName}
          </Typography>
          <Tooltip title="Sign out">
            <IconButton aria-label="Sign out" onClick={() => signOut(session)}>
              <LogoutIcon />
            </IconButton>
          </Tooltip>
        </Toolbar>
      </AppBar>

      <Box sx={{ flex: 1, overflowY: 'auto' }}>
        <Container maxWidth="md" sx={{ py: 3 }}>
          {items.length === 0 && (
            <Stack spacing={2} sx={{ alignItems: 'center', mt: 8, textAlign: 'center' }}>
              <Typography variant="h5" sx={{ fontWeight: 700 }}>
                How can I help, {session.userName}?
              </Typography>
              <Typography color="text.secondary">
                Ask about APIs, or have me set up an application, a subscription and keys for you.
              </Typography>
              <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} sx={{ flexWrap: 'wrap', justifyContent: 'center' }}>
                {suggestions.map((suggestion) => (
                  <Button key={suggestion} variant="outlined" color="inherit" onClick={() => submit(suggestion)}>
                    {suggestion}
                  </Button>
                ))}
              </Stack>
            </Stack>
          )}
          <Stack spacing={2}>
            {items.map((item) => {
              switch (item.kind) {
                case 'user':
                  return (
                    <Box key={item.id} sx={{ display: 'flex', justifyContent: 'flex-end' }}>
                      <Paper elevation={0} sx={{ px: 2, py: 1.25, maxWidth: '80%', bgcolor: 'primary.main', color: 'primary.contrastText', whiteSpace: 'pre-wrap' }}>
                        {item.text}
                      </Paper>
                    </Box>
                  )
                case 'assistant':
                  return (
                    <Paper key={item.id} variant="outlined" sx={{ px: 2, py: 1.5, maxWidth: '90%', alignSelf: 'flex-start', minWidth: 0 }}>
                      <div className="markdown">
                        <Markdown remarkPlugins={[remarkGfm]}>{item.text}</Markdown>
                      </div>
                    </Paper>
                  )
                case 'approval':
                  return (
                    <ApprovalCard
                      key={item.id}
                      approval={item.approval}
                      outcome={item.outcome}
                      disabled={busy}
                      onDecide={(approved) => decide(item.id, approved)}
                    />
                  )
                case 'credentials':
                  return <CredentialCard key={item.id} credentials={item.credentials} />
                case 'error':
                  return (
                    <Alert key={item.id} severity="error" sx={{ alignSelf: 'flex-start' }}>
                      {item.text}
                    </Alert>
                  )
              }
            })}
            {busy && (
              <Stack direction="row" spacing={1.5} sx={{ alignItems: 'center', color: 'text.secondary' }}>
                <CircularProgress size={18} />
                <Typography variant="body2">Working…</Typography>
              </Stack>
            )}
            <div ref={endOfList} />
          </Stack>
        </Container>
      </Box>

      <Box sx={{ borderTop: 1, borderColor: 'divider', bgcolor: 'background.paper' }}>
        <Container maxWidth="md" sx={{ py: 1.5 }}>
          <Stack
            component="form"
            direction="row"
            spacing={1}
            sx={{ alignItems: 'flex-end' }}
            onSubmit={(event) => {
              event.preventDefault()
              submit(draft)
            }}
          >
            <TextField
              fullWidth
              multiline
              maxRows={6}
              size="small"
              autoFocus
              placeholder={awaitingApproval ? 'Approve or reject the action above to continue' : 'Ask about APIs, applications or subscriptions'}
              value={draft}
              disabled={awaitingApproval}
              onChange={(event) => setDraft(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === 'Enter' && !event.shiftKey && !event.nativeEvent.isComposing) {
                  event.preventDefault()
                  submit(draft)
                }
              }}
              slotProps={{ htmlInput: { 'aria-label': 'Message' } }}
            />
            <IconButton type="submit" color="primary" aria-label="Send" disabled={busy || awaitingApproval || !draft.trim()}>
              <SendIcon />
            </IconButton>
          </Stack>
        </Container>
      </Box>
    </Box>
  )
}
