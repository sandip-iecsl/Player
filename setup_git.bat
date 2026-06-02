@echo off
echo 🚀 Setting up Git repository for Aura Player...
echo.

REM Initialize git repository
echo 📁 Initializing Git repository...
git init

REM Add all files
echo 📦 Adding all files...
git add .

REM Create initial commit
echo 💾 Creating initial commit...
git commit -m "Initial commit - Aura Player Flutter app with iOS build setup"

echo.
echo ✅ Git repository initialized successfully!
echo.
echo 📋 Next steps:
echo 1. Create a new repository on GitHub
echo 2. Copy the remote URL from GitHub
echo 3. Run: git remote add origin YOUR_GITHUB_URL
echo 4. Run: git push -u origin main
echo.
echo 🔗 Then follow either:
echo - GITHUB_SETUP_GUIDE.md for GitHub Actions
echo - CODEMAGIC_SETUP_GUIDE.md for Codemagic (recommended)
echo.
pause