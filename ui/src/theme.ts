import { createTheme } from '@mui/material/styles'

export const theme = createTheme({
  palette: {
    primary: { main: '#ff7300', contrastText: '#ffffff' },
    background: { default: '#f6f7f9' },
  },
  shape: { borderRadius: 10 },
  typography: {
    fontFamily: '"Inter", "Segoe UI", system-ui, -apple-system, sans-serif',
    button: { textTransform: 'none', fontWeight: 600 },
  },
})
