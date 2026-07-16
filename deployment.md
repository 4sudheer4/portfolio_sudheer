# Portfolio Deployment — AWS S3 + CloudFront

## Live URL
https://d2qjg27apdabg2.cloudfront.net

## Stack
- **S3 bucket:** `sudheer-portfolio-2026` (private, storage only)
- **CloudFront distribution ID:** `E2IBCVYCO49SEI` (serves the site, HTTPS, caching)
- **Cost:** $0 — CloudFront's always-free tier covers 1TB transfer + 10M requests/month, permanently (not a 12-month trial)

## One-time setup (already done)
- `aws configure` run with IAM access key
- `deploy.sh` created the bucket, CloudFront distribution, and bucket policy

---

## How to make a change and redeploy

1. **Edit the file** — `index.html` locally.

2. **Make sure only site files are in the deploy folder.** Don't run this from inside a git repo root, or `.git` will get uploaded too. Keep `index.html` in its own clean folder, e.g.:
   ```
   ~/portfolio-deploy/
     ├── index.html
     └── update.sh
   ```

3. **Push the update:**
   ```bash
   cd ~/portfolio-deploy
   ./update.sh sudheer-portfolio-2026 . E2IBCVYCO49SEI
   ```
   This syncs the file to S3 and invalidates CloudFront's cache so the change shows immediately.

4. **Verify:**
   ```bash
   aws s3 ls s3://sudheer-portfolio-2026/
   ```
   Should list only `index.html` — nothing else. If you ever see `.git`, `deploy.sh`, or similar in there, something got uploaded from the wrong folder — see Troubleshooting below.

5. Wait ~30-60 seconds, then hard-refresh the live URL (Cmd+Shift+R / Ctrl+Shift+R) to bypass browser cache.

---

## Troubleshooting

**AccessDenied on the live URL**
- Usually means `index.html` is missing or misnamed in the bucket. CloudFront's default root object is `index.html` exactly — check filename casing.
- Run `aws s3 ls s3://sudheer-portfolio-2026/` to confirm what's actually there.

**Changes not showing after redeploy**
- CloudFront caches aggressively. Confirm the invalidation ran:
  ```bash
  aws cloudfront create-invalidation --distribution-id E2IBCVYCO49SEI --paths "/*"
  ```
- Hard refresh, or test in an incognito window to rule out browser cache.

**Accidentally uploaded extra files (`.git`, scripts, etc.)**
```bash
aws s3 rm s3://sudheer-portfolio-2026/.git --recursive
aws s3 rm s3://sudheer-portfolio-2026/deploy.sh
aws cloudfront create-invalidation --distribution-id E2IBCVYCO49SEI --paths "/*"
```

**Check distribution status** (should say `Deployed`, not `InProgress`):
```bash
aws cloudfront get-distribution --id E2IBCVYCO49SEI --query 'Distribution.Status' --output text
```

**Check bucket policy is intact:**
```bash
aws s3api get-bucket-policy --bucket sudheer-portfolio-2026 --query Policy --output text
```

deploy.sh — the one-time setup. Creates the S3 bucket, sets up the CloudFront distribution, attaches the bucket policy. You already ran this once; running it again would try to recreate infrastructure that already exists (mostly harmless since I made the OAC step idempotent, but there's no reason to re-run it for a content change).
update.sh — for every change after that. Just syncs your files to the existing bucket and clears CloudFront's cache so the change shows up. Much faster since it skips all the bucket/distribution/policy creation steps.
Rule of thumb: deploy.sh once per site (initial launch), update.sh every time after (content edits).