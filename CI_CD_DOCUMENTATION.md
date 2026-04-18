# CI/CD End-to-End Testing Commands

This document contains the exact step-by-step terminal commands we used to test the entire automated CI/CD workflow natively on your local machine. 

By default, the CD pipeline destroys the testing environment to clean up after itself when it finishes. To allow you to view the automated deployment visually in your browser, **the Cleanup job inside `cd.yml` has been deliberately disabled**.

## 1. Wipe Active Workspaces
Before letting the automation take over, ensure you don't have any native platforms running that could clash with the automation.
```powershell
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml down -v
```

## 2. Commit Your Changes
`act` requires files to be committed to Git to detect them. Make your changes (like updating `style.css` to Version 5.0.0) and commit them:
```powershell
git add wp-content\themes\starter-theme\style.css
git commit -m "Bump theme version to 5.0.0"
```

## 3. Automated CI Pipeline (Pull Request)
This command triggers the `.github/workflows/ci.yml` pipeline to automatically run syntax checks, PHPCS formatting, and PHPStan security scans.
```powershell
act pull_request -W .github/workflows/ci.yml
```

## 4. Automated CD Deployment (Push to Main)
This command triggers `.github/workflows/cd.yml`. The automation will:
1. Build the new `.zip` artifact.
2. Spin up the WordPress Docker platform automatically.
3. Automatically deploy the new Version 5.0.0 artifact into the container.
4. Pass all HTTP health checks.
5. **Leave the platform running for you to view.**

*(Note: The `--artifact-server-path` is used so `act` has a local folder to store the zip artifacts it builds prior to deployment)*
```powershell
act push -W .github/workflows/cd.yml --artifact-server-path ./tmp-artifacts
```

## 5. Verify the Automation Visually!
Because we disabled the teardown step within the automation, the deployment is still live!
Open your browser to `http://tenant-alpha.localhost/wp-admin`, navigate to **Appearance > Themes**, and you will immediately see your newly deployed **Version: 5.0.0** theme automatically applied by the pipeline.

## 6. Ultimate Teardown (When you are finished)
When you are completely done testing and reviewing your deployed changes, strictly reset the environment and wipe out all local databases and testing configurations:
```powershell
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml down -v
```
