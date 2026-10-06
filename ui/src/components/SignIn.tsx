import Alert from '@mui/material/Alert'
import Box from '@mui/material/Box'
import Button from '@mui/material/Button'
import Paper from '@mui/material/Paper'
import Stack from '@mui/material/Stack'
import Typography from '@mui/material/Typography'
import { startSignIn } from '../auth'

export default function SignIn({ error }: { error: string | null }) {
  return (
    <Box sx={{ height: '100%', display: 'grid', placeItems: 'center', p: 2 }}>
      <Paper variant="outlined" sx={{ p: 5, maxWidth: 440, width: '100%' }}>
        <Stack spacing={2.5}>
          <Typography variant="h5" component="h1" sx={{ fontWeight: 700 }}>
            Developer Portal Assistant
          </Typography>
          <Typography color="text.secondary">
            Find APIs, create applications, subscribe and get credentials by asking. Sign in with your Developer
            Portal account; the assistant works with your permissions.
          </Typography>
          {error && <Alert severity="error">{error}</Alert>}
          <Button variant="contained" size="large" onClick={() => void startSignIn()}>
            Sign in
          </Button>
        </Stack>
      </Paper>
    </Box>
  )
}
