import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // The sign-in client's redirect URI and the agent's allowed origin are tied to this port.
  server: { port: 5173, strictPort: true },
  preview: { port: 5173, strictPort: true },
})
