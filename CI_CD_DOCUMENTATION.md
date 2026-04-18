# CI/CD End-to-End Testing Commands

This document contains the exact step-by-step terminal commands we used to test the entire CI/CD workflow sequentially on your local machine.

## 1. Commit Your Changes
`act` requires files to be committed to Git to detect them. We updated the version in `style.css` and committed it.

```powershell
git add wp-content\themes\starter-theme\style.css
git commit -m "Bump theme version to 4.0.0"
```

## 2. Test the CI Pipeline Locally (Pull Request)
This command triggers the `.github/workflows/ci.yml` pipeline to run the syntax checks, PHPCS formatting, and PHPStan security scans.

```powershell
act pull_request -W .github/workflows/ci.yml
```

## 3. Test the CD Pipeline Locally (Deployment)
This command triggers `.github/workflows/cd.yml` to build the `.zip` artifacts and test the deployment. 

*Note: The `--artifact-server-path` flag is strictly required so `act` can store the `.zip` file between the Build step and the Deploy step.*

```powershell
act push -W .github/workflows/cd.yml --artifact-server-path ./tmp-artifacts
```
*(At the end of this run, the CD pipeline automatically executes `docker compose down -v` to clean up the workspace, meaning your containers will be stopped.)*

## 4. Manually View the Changes in WordPress
Because the `act` CD pipeline destroyed the testing containers after verifying they worked, we use these commands to bring the actual "Production" cluster back online and inject the code to verify it visually in the browser.

**Boot up the platform:**
```powershell
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
```

**Inject the active theme manually to the running container:**
```powershell
docker cp ./wp-content/themes/starter-theme wp-alpha:/var/www/html/wp-content/themes/
```

**Verify:**
Open your browser to `http://tenant-alpha.localhost/wp-admin`, navigate to **Appearance > Themes**, and you will see "Version: 4.0.0".

## 5. Ultimate Teardown
If you ever need to completely reset the environment and wipe all databases, volumes, and monitoring data:

```powershell
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml down -v
```
