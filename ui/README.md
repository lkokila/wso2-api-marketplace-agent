# UI

React chat UI for the Devportal agent (Vite, TypeScript, MUI).

## Run

Prerequisites: API Manager and the agent running (see [../agent/README.md](../agent/README.md)).

```sh
scripts/write-config.sh   # writes .env.local (git-ignored) and registers the sign-in client if needed
npm install
npm run dev               # http://localhost:5173
```

The first time, open `https://localhost:9443` in the same browser and accept API Manager's
self-signed certificate, or the sign-in redirect will be blocked.

The port is fixed at 5173: the sign-in client's redirect URI and the agent's allowed origin
both point at it. To change it, set `UI_ORIGIN` in `../.env`, delete
`../.local/ui-client.json`, re-run both `write-config.sh` scripts and update `vite.config.ts`.

## How it works

| File | Role |
|---|---|
| `src/auth.ts` | Sign-in with the authorization code flow and PKCE. The code is redeemed by the agent (`POST /agent/auth/token`), so the client secret never reaches the browser. Sign-out goes through the identity provider. |
| `src/api.ts` | Calls to the agent's chat and decision endpoints. |
| `src/components/Chat.tsx` | The conversation: messages, input, and the cards below. |
| `src/components/ApprovalCard.tsx` | An action awaiting the user's Approve or Reject. The input is locked until it is answered. |
| `src/components/CredentialCard.tsx` | Secrets delivered outside the model, masked until revealed, with copy buttons. |

## Limits

- The access token is kept in `sessionStorage` for the tab. There is no silent refresh:
  when it expires (one hour by default) the UI returns to the sign-in screen.
- A conversation lives in the page: reloading or choosing **New chat** starts a fresh one.
- Replies arrive whole; there is no streaming.
- There are no automated UI tests.
