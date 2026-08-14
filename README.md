# Weekly Planner

A single-file weekly planner: top priorities, a to-do list (week-only or assigned to specific days), a habit tracker, a manual "blocked time" schedule per day, and an optional Google sign-in that pulls your Calendar and syncs your tasks across devices via your own Google Drive. No build step, no backend — it's one static `index.html`.

## Run locally

Just open `index.html` in a browser, or serve it so relative URLs behave normally:

```
python3 -m http.server 8000
```

then visit http://localhost:8000

## Customize the look

Click the sliders icon next to "Today" to open the design panel — background/surface/text/accent/highlight colors, heading font, corner radius, and shadow style. Changes apply instantly and are saved in your browser. Use "Copy CSS" to grab the resulting token block.

## Sign in with Google (optional)

Click **Sign in** in the top-right corner. This does two things, both running entirely client-side — no backend, nothing sent to any server but Google:

- **Calendar (read-only)**: your events show up alongside your manual "blocked" time, tagged with a small **G** badge (click one to open it in Google Calendar).
- **Task sync**: your to-dos, priorities, habits, and blocked time are also saved as a private file in your own Google Drive's hidden "app data" folder (invisible in your normal Drive, not shared with anyone, not readable by any other app). Sign in from another device/browser with the same Google account and your tasks are pulled down automatically. Every change syncs back up a couple seconds after you stop typing.

If you never sign in, everything still works exactly as before, saved only to this browser's `localStorage`.

One-time setup (~10 minutes), in [Google Cloud Console](https://console.cloud.google.com):

1. Create a new project (or pick an existing one).
2. **APIs & Services → Library** → search "Google Calendar API" → **Enable**. Also search "Google Drive API" → **Enable**.
3. **APIs & Services → OAuth consent screen** → choose **External** → fill in app name + your email → under "Test users" add your own Google account (keeps the app in testing mode, so no Google review is needed for personal use).
   - Under **Data Access → Add or Remove Scopes**, add: `.../auth/calendar.readonly`, `.../auth/drive.appdata`, `.../auth/userinfo.email`, `.../auth/userinfo.profile`.
4. **APIs & Services → Credentials → Create Credentials → OAuth client ID** → Application type: **Web application**.
5. Under **Authorized JavaScript origins**, add:
   - `http://localhost:8000` (for local use)
   - `https://achernyshova.github.io` (for the hosted version — see below)
6. Copy the **Client ID** it gives you (looks like `123...apps.googleusercontent.com`).
7. In the app, open the design panel (sliders icon), paste the Client ID under "Google", then click **Sign in** in the top-right corner and approve access in the popup.

The Client ID is not a secret (it's safe to be public) — it's saved to this browser's localStorage so you only have to paste it once per browser. Your access token itself is never stored on disk; it lives in memory for the tab and is silently refreshed on future visits if you stay signed in to Google.

## Deploy for free (GitHub Pages)

This repo serves straight from the `main` branch via GitHub Pages:

**https://achernyshova.github.io/weekly-planner/**

Push to `main` and it updates automatically within a minute or two.

## Data

Everything — to-dos, priorities, habits, blocked time, your theme — is saved in this browser's `localStorage`, per week, regardless of sign-in. Signing in additionally mirrors your tasks (not your theme, and not Calendar events, which stay read-only) to a private file in your own Google Drive, so they follow you to other devices. Nothing ever passes through a third-party server — your browser talks to Google directly.
