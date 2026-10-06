import ContentCopyIcon from '@mui/icons-material/ContentCopy'
import VisibilityIcon from '@mui/icons-material/Visibility'
import VisibilityOffIcon from '@mui/icons-material/VisibilityOff'
import Alert from '@mui/material/Alert'
import Box from '@mui/material/Box'
import IconButton from '@mui/material/IconButton'
import Paper from '@mui/material/Paper'
import Stack from '@mui/material/Stack'
import Tooltip from '@mui/material/Tooltip'
import Typography from '@mui/material/Typography'
import { useState } from 'react'
import type { Credential } from '../types'

const credentialLabels: Record<string, string> = {
  consumerSecret: 'Consumer secret',
  clientSecret: 'Client secret',
  secretValue: 'Consumer secret',
  accessToken: 'Access token',
  apikey: 'API key',
}

function CredentialRow({ credential }: { credential: Credential }) {
  const [visible, setVisible] = useState(false)
  const [copied, setCopied] = useState(false)
  const label = credentialLabels[credential.name] ?? credential.name

  const copy = async () => {
    await navigator.clipboard.writeText(credential.value)
    setCopied(true)
    window.setTimeout(() => setCopied(false), 1500)
  }

  return (
    <Box>
      <Typography variant="body2" color="text.secondary">
        {label}
      </Typography>
      <Stack direction="row" spacing={0.5} sx={{ alignItems: 'center' }}>
        <Typography
          component="code"
          sx={{
            flex: 1,
            minWidth: 0,
            fontFamily: 'ui-monospace, Menlo, Consolas, monospace',
            fontSize: '0.85rem',
            overflowWrap: 'anywhere',
            maxHeight: 96,
            overflowY: 'auto',
          }}
        >
          {visible ? credential.value : '•'.repeat(Math.min(credential.value.length, 32))}
        </Typography>
        <Tooltip title={visible ? 'Hide' : 'Show'}>
          <IconButton size="small" aria-label={`${visible ? 'Hide' : 'Show'} ${label}`} onClick={() => setVisible(!visible)}>
            {visible ? <VisibilityOffIcon fontSize="small" /> : <VisibilityIcon fontSize="small" />}
          </IconButton>
        </Tooltip>
        <Tooltip title={copied ? 'Copied' : 'Copy'}>
          <IconButton size="small" aria-label={`Copy ${label}`} onClick={() => void copy()}>
            <ContentCopyIcon fontSize="small" />
          </IconButton>
        </Tooltip>
      </Stack>
    </Box>
  )
}

export default function CredentialCard({ credentials }: { credentials: Credential[] }) {
  const consumerKey = credentials.find((credential) => credential.consumerKey)?.consumerKey
  return (
    <Paper variant="outlined" sx={{ p: 2, maxWidth: 560 }}>
      <Stack spacing={1.5}>
        <Typography sx={{ fontWeight: 600 }}>Your credentials</Typography>
        {consumerKey && (
          <Box>
            <Typography variant="body2" color="text.secondary">
              Consumer key
            </Typography>
            <Typography component="code" sx={{ fontFamily: 'ui-monospace, Menlo, Consolas, monospace', fontSize: '0.85rem' }}>
              {consumerKey}
            </Typography>
          </Box>
        )}
        {credentials.map((credential) => (
          <CredentialRow key={`${credential.name}-${credential.value.slice(-8)}`} credential={credential} />
        ))}
        <Alert severity="warning" sx={{ py: 0 }}>
          Copy the consumer secret now. It cannot be shown again, and the assistant never sees it.
        </Alert>
      </Stack>
    </Paper>
  )
}
