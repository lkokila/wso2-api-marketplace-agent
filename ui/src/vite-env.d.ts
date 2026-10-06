/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_AGENT_URL: string
  readonly VITE_AUTHORIZE_URL: string
  readonly VITE_LOGOUT_URL: string
  readonly VITE_CLIENT_ID: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
