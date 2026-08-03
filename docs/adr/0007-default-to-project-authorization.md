# Default to project authorization

Version one will default to Project Authorization: the author selects a Google Cloud project, supplies its Desktop OAuth client, and owns its consent configuration and quota. Managed Authorization remains the intended future onboarding improvement, but deferring it avoids making the initial release responsible for a shared production OAuth identity, verification, quota, abuse handling, and operational support; the setup wizard will reduce the user-owned configuration burden without using ADC as the normal interactive authorization path.
