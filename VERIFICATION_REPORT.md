# Verification Report

Generated for the initial repository publication.

Local checks to run before release:

    bash -n scripts/apply-opencodex-desktop-menu.sh
    python3 /Users/kityhello/.codex/skills/github-publish-prep/scripts/validate_github_publish_prep.py .
    rg -n --hidden -g '!.git' -g '!VERIFICATION_REPORT.md' 'sk-[A-Za-z0-9]|gho_[A-Za-z0-9]|attestationSecret|apiKey|OPENAI_API_KEY|MOONSHOT_API_KEY|DASHSCOPE_API_KEY|ZAI_API_KEY|DEEPSEEK_API_KEY' .

Runtime validation is machine-specific and should be performed by running:

    bash scripts/apply-opencodex-desktop-menu.sh

