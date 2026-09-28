# CI: build DMG on GitHub Actions

The cloud agent that published this repo did not have the GitHub `workflow` token scope, so the workflow is stored here instead of `.github/workflows/`.

## Enable automatic DMG builds

On a machine with `gh` logged in as you:

```bash
gh auth refresh -h github.com -s repo,workflow
cd mac-ipad-display
mkdir -p .github/workflows
cp docs/ci/build-dmg.yml .github/workflows/build-dmg.yml
git add .github/workflows/build-dmg.yml
git commit -m "Enable macOS DMG GitHub Actions workflow"
git push
git tag -f v1.0.1 && git push -f origin v1.0.1   # or bump and tag a new release
```

Or run locally on a Mac:

```bash
./Scripts/make-dmg.sh
```
