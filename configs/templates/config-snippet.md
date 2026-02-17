# Config Snippet Template

Starter snippet for documenting runtime flags and managed defaults.

```ini
# Example: .env or runtime override notes
FEATURE_FLAG_EXAMPLE=1
API_BASE_URL=https://api.example.com
REQUEST_TIMEOUT_SECONDS=30
LOG_LEVEL=info
```

## Notes
- Keep secrets in environment variables, never committed files.
- Mark managed defaults separately from user-editable values.
- Add ownership comments when a setting is intentionally locked.
