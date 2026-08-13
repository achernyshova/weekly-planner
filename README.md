# Weekly Planner

A single-file weekly planner: top priorities, a to-do list (week-only or assigned to specific days), a habit tracker, a manual "blocked time" schedule per day, and optional read-only Google Calendar sync. No build step — it's one static `index.html`.

## Run locally

Just open `index.html` in a browser, or serve it so relative URLs behave normally:

```
python3 -m http.server 8000
```

then visit http://localhost:8000

## Customize the look

Click the sliders icon next to "Today" to open the design panel — background/surface/text/accent/highlight colors, heading font, corner radius, and shadow style. Changes apply instantly and are saved in your browser. Use "Copy CSS" to grab the resulting token block.

## Connect Google Calendar (optional, read-only)

Calendar events show up alongside your manual "blocked" time, tagged with a small **G** badge (click one to open it in Google Calendar). Nothing is sent to any server — your browser talks to Google directly, and the access token lives only in memory for that tab (not saved to disk).

One-time setup (~10 minutes), in [Google Cloud Console](https://console.cloud.google.com):

1. Create a new project (or pick an existing one).
2. **APIs & Services → Library** → search "Google Calendar API" → **Enable**.
3. **APIs & Services → OAuth consent screen** → choose **External** → fill in app name + your email → under "Test users" add your own Google account (keeps the app in testing mode, so no Google review is needed for personal use).
4. **APIs & Services → Credentials → Create Credentials → OAuth client ID** → Application type: **Web application**.
5. Under **Authorized JavaScript origins**, add:
   - `http://localhost:8000` (for local use)
   - `https://YOUR_GITHUB_USERNAME.github.io` (for the hosted version — see below)
6. Copy the **Client ID** it gives you (looks like `123...apps.googleusercontent.com`).
7. In the app, open the design panel, paste the Client ID under "Google Calendar", click **Connect**, and approve access in the popup.

The Client ID is not a secret (it's safe to be public) — it's saved to this browser's localStorage so you only have to paste it once.

## Deploy for free (GitHub Pages)

This repo is set up to serve straight from the `main` branch via GitHub Pages:

```
https://YOUR_GITHUB_USERNAME.github.io/REPO_NAME/
```

Push to `main` and it updates automatically within a minute or two.

## Data

Everything — to-dos, priorities, habits, blocked time, your theme — is saved in this browser's `localStorage`, per week. Nothing leaves your machine except the optional Google Calendar read calls, which go straight from your browser to Google.
