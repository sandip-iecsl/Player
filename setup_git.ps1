Write-Host "🚀 Setting up Git repository for Aura Player..." -ForegroundColor Green
Write-Host ""

# Check if git is installed
try {
    git --version | Out-Null
    Write-Host "✅ Git is installed" -ForegroundColor Green
} catch {
    Write-Host "❌ Git is not installed. Please install Git first:" -ForegroundColor Red
    Write-Host "   Download from: https://git-scm.com/download/windows" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit
}

# Initialize git repository
Write-Host "📁 Initializing Git repository..." -ForegroundColor Cyan
git init

# Add all files
Write-Host "📦 Adding all files..." -ForegroundColor Cyan
git add .

# Create initial commit
Write-Host "💾 Creating initial commit..." -ForegroundColor Cyan
git commit -m "Initial commit - Aura Player Flutter app with iOS build setup"

Write-Host ""
Write-Host "✅ Git repository initialized successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Next steps:" -ForegroundColor Yellow
Write-Host "1. Create a new repository on GitHub (https://github.com/new)" -ForegroundColor White
Write-Host "2. Copy the repository URL from GitHub" -ForegroundColor White
Write-Host "3. Run: git remote add origin YOUR_GITHUB_URL" -ForegroundColor White
Write-Host "4. Run: git push -u origin main" -ForegroundColor White
Write-Host ""
Write-Host "🔗 Then follow either:" -ForegroundColor Yellow
Write-Host "- GITHUB_SETUP_GUIDE.md for GitHub Actions" -ForegroundColor White
Write-Host "- CODEMAGIC_SETUP_GUIDE.md for Codemagic (recommended)" -ForegroundColor White
Write-Host ""

# Ask user which option they prefer
Write-Host "Which build service would you like to use?" -ForegroundColor Cyan
Write-Host "1. GitHub Actions (Free, more complex setup)" -ForegroundColor White
Write-Host "2. Codemagic (500 free minutes/month, easier setup)" -ForegroundColor White
Write-Host ""
$choice = Read-Host "Enter your choice (1 or 2)"

switch ($choice) {
    "1" {
        Write-Host ""
        Write-Host "📖 Opening GitHub Actions setup guide..." -ForegroundColor Green
        Write-Host "Follow the instructions in GITHUB_SETUP_GUIDE.md" -ForegroundColor Yellow
        if (Test-Path "GITHUB_SETUP_GUIDE.md") {
            Start-Process "GITHUB_SETUP_GUIDE.md"
        }
    }
    "2" {
        Write-Host ""
        Write-Host "📖 Opening Codemagic setup guide..." -ForegroundColor Green
        Write-Host "Follow the instructions in CODEMAGIC_SETUP_GUIDE.md" -ForegroundColor Yellow
        if (Test-Path "CODEMAGIC_SETUP_GUIDE.md") {
            Start-Process "CODEMAGIC_SETUP_GUIDE.md"
        }
        Write-Host ""
        Write-Host "🌐 Opening Codemagic website..." -ForegroundColor Green
        Start-Process "https://codemagic.io"
    }
    default {
        Write-Host "Invalid choice. Please read both guide files and choose." -ForegroundColor Red
    }
}

Write-Host ""
Read-Host "Press Enter to exit"