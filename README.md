# Weekly Planner

A single-file weekly planner: top priorities, a weekly task list, a Google Tasks Inbox, a habit tracker, a manual "blocked time" schedule per day, and an optional Google sign-in that pulls Calendar events and syncs Google Tasks. No build step, no backend — it's one static `index.html`.

## Run locally

Just open `index.html` in a browser, or serve it so relative URLs behave normally:

```
python3 -m http.server 8000
```

then visit http://localhost:8000

## Customize the look

Click the sliders icon next to "Today" to open the design panel — background/surface/text/accent/highlight colors, heading font, corner radius, and shadow style. Changes apply instantly and are saved in your browser. Use "Copy CSS" to grab the resulting token block.

## Google sign-in

Click **Sign in with Google** in the top-right corner. Google opens its own account-chooser and consent popup — you never enter a Client ID anywhere in the app itself; that's a one-time setup value the site owner configures in a separate file (see below). Signing in does two things, both running entirely client-side — no backend, nothing sent to any server but Google:

- **Calendar (read-only)**: your events show up alongside your manual "blocked" time, tagged with a small **G** badge (click one to open it in Google Calendar).
- **Google Tasks**: undated tasks appear in Inbox, dated tasks appear on their assigned day, and changes to titles, completion, dates, and deletions sync both ways. Week-only assignments stay undated in Google Tasks and are saved as private planner metadata.
- **Planner data sync**: priorities, habits, blocked time, local tasks, and week-only Google Task assignments are saved as a private file in your own Google Drive's hidden "app data" folder.

If you never sign in, everything still works exactly as before, saved only to this browser's `localStorage`. If the app isn't configured yet, or the popup is blocked or cancelled, a small message under the Sign in button explains what happened.

### One-time owner setup (~10 minutes)

The token popup still requires an OAuth **Web application Client ID** registered in [Google Cloud Console](https://console.cloud.google.com) — that's a Google platform requirement for any app reading a user's Calendar, Tasks, or Drive data, not something this app can skip. It's a public identifier (safe to commit), not a secret. You only do this once, in [`google-config.js`](google-config.js) — regular visitors never see it or paste it anywhere.

1. Create a new project (or pick an existing one).
2. **APIs & Services → Library** → enable **Google Calendar API**, **Google Drive API**, and **Google Tasks API**.
3. **APIs & Services → OAuth consent screen** → choose **External** → fill in app name + your email → under "Test users" add your own Google account (keeps the app in testing mode, so no Google review is needed for personal use).
   - Under **Data Access → Add or Remove Scopes**, add: `.../auth/calendar.readonly`, `.../auth/tasks`, `.../auth/drive.appdata`, `.../auth/userinfo.email`, `.../auth/userinfo.profile`.
4. **APIs & Services → Credentials → Create Credentials → OAuth client ID** → Application type: **Web application**.
5. Under **Authorized JavaScript origins**, add:
   - `http://localhost:8000` (for local use)
   - `https://achernyshova.github.io` (for the hosted version — see below)
6. Copy the **Client ID** it gives you (looks like `123...apps.googleusercontent.com`).
7. Open [`google-config.js`](google-config.js) and paste it in:

   ```js
   window.WEEKLY_PLANNER_CONFIG = {
     googleClientId: 'YOUR_CLIENT_ID.apps.googleusercontent.com'
   };
   ```

8. Commit and push. Do **not** put a client *secret*, API key, or any other credential in this file or repo — only the Client ID, which is meant to be public.

Your access token itself is never stored on disk; it lives in memory for the tab and is silently refreshed on future visits if you stay signed in to Google.

## Deploy for free (GitHub Pages)

This repo serves straight from the `main` branch via GitHub Pages:

**https://achernyshova.github.io/weekly-planner/**

Push to `main` and it updates automatically within a minute or two.

## Data

Planner data — priorities, habits, blocked time, local tasks, week assignments, and your theme — is saved in this browser's `localStorage`. Signing in also reads and writes your Google Tasks and mirrors planner-only data (except the theme) to a private file in your own Google Drive. Calendar events remain read-only. Nothing passes through a third-party server; your browser talks to Google directly.
