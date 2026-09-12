# MoshDeck site

Static landing page, beta setup, support and privacy pages. Source is `public/`; there is no build step, JavaScript, analytics, form, remote font or runtime dependency. The terminal illustration is explicitly labeled and contains synthetic text only.

Intended address: `moshdeck.chenrui.dev`, using Cloudflare Pages Direct Upload, consistent with the owner's existing app site. Publication is pending fresh Cloudflare authentication. There is no public TestFlight link; only the owner internal group is currently enabled.

## Preview

From the repository root:

```sh
python3 -m http.server 8768 --bind 127.0.0.1 --directory site/public
```

Open `http://127.0.0.1:8768`. Production security headers are in `public/_headers`; Python's preview server does not apply them.

## Publish

Use the personal account that owns the domain. The local account workflow deliberately unsets an unrelated environment token; CI should instead use a correctly scoped deployment secret.

```sh
env -u CLOUDFLARE_API_TOKEN npx --yes wrangler@4.129.0 whoami
# Once the Pages project exists:
env -u CLOUDFLARE_API_TOKEN npx --yes wrangler@4.129.0 pages deploy site/public --project-name moshdeck --branch main
```

Before first publication, inspect the Pages project and custom-domain DNS for collisions. Create a dedicated `moshdeck` project only if absent, attach the intended custom domain, then create its CNAME only if no existing record would be replaced. Verify HTTPS, page content, security headers and an unknown-path 404. Do not change apex-domain or other app records.

## Content maintenance

Keep setup labels aligned with the shipped app and its SSH scope. Do not claim external beta availability before Apple review and tester distribution are complete. Add a verified invitation link only when it exists. Keep privacy language consistent with actual app behavior and avoid collecting terminal output in support reports.

The setup guide links current primary documentation for macOS Remote Login, Tailscale and tmux. Reviewed September 12, 2026. It makes key authorization explicit and preserves existing `authorized_keys` entries; it does not offer a privileged auto-setup script.

## Local verification — September 12, 2026

Desktop (1440px) and phone (390px) landing-page screenshots were visually reviewed. The setup call-to-action navigated correctly; the setup page had no horizontal overflow at 390px. Support disclosure toggling passed at 390px, and support layout had no horizontal overflow at 320px. Browser console reported zero errors or warnings. All five pages' local asset, page and fragment links resolve. The local preview returns 404 for an unknown URL. Live Cloudflare headers, custom-domain TLS and actual iPhone Safari checks remain pending publication.
