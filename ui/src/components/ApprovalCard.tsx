import Box from '@mui/material/Box'
import Button from '@mui/material/Button'
import Chip from '@mui/material/Chip'
import Paper from '@mui/material/Paper'
import Stack from '@mui/material/Stack'
import Typography from '@mui/material/Typography'
import type { Approval, ApprovalOutcome } from '../types'

interface ApprovalCardProps {
  approval: Approval
  outcome: ApprovalOutcome
  disabled: boolean
  onDecide: (approved: boolean) => void
}

export default function ApprovalCard({ approval, outcome, disabled, onDecide }: ApprovalCardProps) {
  return (
    <Paper
      variant="outlined"
      sx={{ p: 2, maxWidth: 560, borderColor: outcome === 'pending' ? 'primary.main' : 'divider', borderWidth: 1.5 }}
    >
      <Stack spacing={1.5}>
        <Box>
          <Typography variant="overline" color="text.secondary" sx={{ lineHeight: 1.6 }}>
            {outcome === 'pending' ? 'The assistant wants to' : 'Requested action'}
          </Typography>
          <Typography sx={{ fontWeight: 600 }}>{approval.action}</Typography>
        </Box>
        <Box component="dl" sx={{ m: 0, display: 'grid', gridTemplateColumns: 'max-content 1fr', columnGap: 2, rowGap: 0.5 }}>
          {approval.details.map((detail) => (
            <Box key={detail.label} sx={{ display: 'contents' }}>
              <Typography component="dt" variant="body2" color="text.secondary">
                {detail.label}
              </Typography>
              <Typography component="dd" variant="body2" sx={{ m: 0, overflowWrap: 'anywhere' }}>
                {detail.value}
              </Typography>
            </Box>
          ))}
        </Box>
        {outcome === 'pending' ? (
          <Stack direction="row" spacing={1}>
            <Button variant="contained" disabled={disabled} onClick={() => onDecide(true)}>
              Approve
            </Button>
            <Button variant="outlined" color="inherit" disabled={disabled} onClick={() => onDecide(false)}>
              Reject
            </Button>
          </Stack>
        ) : (
          <Box>
            <Chip
              size="small"
              label={outcome === 'approved' ? 'Approved' : 'Rejected'}
              color={outcome === 'approved' ? 'success' : 'default'}
              variant="outlined"
            />
          </Box>
        )}
      </Stack>
    </Paper>
  )
}
