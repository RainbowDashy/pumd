///|
async test "credential-store capability does not infer write readiness from an absent credential" {
  let store : CredentialStore = {
    probe: fn() { Err(CredentialStoreError::MissingEntitlement) },
    load: fn() { Err(CredentialStoreError::NotConfigured) },
    replace: fn(_) { Err(CredentialStoreError::MissingEntitlement) },
    delete: fn() { Ok(()) },
  }
  guard (store.load)() is Err(CredentialStoreError::NotConfigured) else {
    fail("the regression fixture must allow an empty-store read")
  }
  guard credential_store_capability(store)
    is CredentialStoreCapability::Unavailable(
      CredentialStoreUnavailableReason::MissingEntitlement
    ) else {
    fail("a store that cannot safely write must be unavailable for setup")
  }
}

///|
async test "credential-store capability keeps locked, denied, and cleanup failures distinct" {
  fn store_with_probe(error : CredentialStoreError) -> CredentialStore {
    {
      probe: fn() { Err(error) },
      load: fn() { Err(CredentialStoreError::NotConfigured) },
      replace: fn(_) { Err(error) },
      delete: fn() { Err(error) },
    }
  }
  guard credential_store_capability(
      store_with_probe(CredentialStoreError::Locked),
    )
    is CredentialStoreCapability::Unavailable(
      CredentialStoreUnavailableReason::Locked
    ) else {
    fail("locked vaults need unlock guidance")
  }
  guard credential_store_capability(
      store_with_probe(CredentialStoreError::Denied),
    )
    is CredentialStoreCapability::Unavailable(
      CredentialStoreUnavailableReason::PermissionDenied
    ) else {
    fail("permission denial must not be described as a lock")
  }
  guard credential_store_capability(
      store_with_probe(CredentialStoreError::CleanupFailed),
    )
    is CredentialStoreCapability::Unavailable(
      CredentialStoreUnavailableReason::CleanupFailed
    ) else {
    fail("probe cleanup failures must be actionable and distinct")
  }
}

///|
test "credential-store catalog exposes stable identity, protection, and availability" {
  let catalog = credential_store_capability_catalog(
    "macOS Keychain",
    CredentialStoreCapability::Unavailable(
      CredentialStoreUnavailableReason::MissingEntitlement,
    ),
  )
  assert_eq(catalog.length(), 2)
  assert_eq(catalog[0].identifier, CredentialStoreIdentifier::Native)
  assert_eq(catalog[0].label, "macOS Keychain")
  assert_true(catalog[0].protection.contains("operating system"))
  guard catalog[0].capability is CredentialStoreCapability::Unavailable(_) else {
    fail("the native catalog entry must retain its capability result")
  }
  assert_eq(catalog[1].identifier, CredentialStoreIdentifier::File)
  assert_true(catalog[1].protection.contains("reduced protection"))
}

///|
test "interactive credential-store selection keeps disabled native and explicit file choices distinct" {
  guard credential_store_menu_choice(
      Some(""),
      CredentialStoreCapability::Usable,
    )
    is Ok(CredentialStoreMenuChoice::Native) else {
    fail("an available native vault should be the interactive default")
  }
  let unavailable = CredentialStoreCapability::Unavailable(
    CredentialStoreUnavailableReason::MissingEntitlement,
  )
  guard credential_store_menu_choice(Some("1"), unavailable)
    is Err(
      CredentialStoreMenuError::Disabled(
        CredentialStoreUnavailableReason::MissingEntitlement
      )
    ) else {
    fail("the visible native option must remain disabled")
  }
  guard credential_store_menu_choice(Some("2"), unavailable)
    is Ok(CredentialStoreMenuChoice::File) else {
    fail("file storage must remain an explicit selectable choice")
  }
  guard credential_store_menu_choice(Some(""), unavailable)
    is Err(CredentialStoreMenuError::Cancelled) else {
    fail("file storage must never become the fallback default")
  }
  guard credential_store_menu_choice(Some("r"), unavailable)
    is Err(CredentialStoreMenuError::Recheck) else {
    fail("an author must be able to recheck native availability in place")
  }
  let explanation = CredentialStoreUnavailableReason::MissingEntitlement.user_message()
  assert_true(explanation.contains("entitlement"))
  assert_false(explanation.contains("unlock"))
}
