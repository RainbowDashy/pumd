///|
fn gcloud_result(exit_code : Int, stdout : String) -> GcloudProcessResult {
  { launched: true, exit_code, stdout, stderr: "process diagnostics" }
}

///|
async test "gcloud adapter detects a ready account and discards the access token" {
  let calls : Array[Array[String]] = []
  let mut next = 0
  let responses = [
    gcloud_result(
      0,
      (
        #|[{"account":"inactive-without-status@example.com"},{"account":"author@example.com","status":"ACTIVE"},{"account":"other@example.com","status":""}]
      ),
    ),
    gcloud_result(0, "sensitive-access-token\n"),
    gcloud_result(0, "docs-project\n"),
  ]
  let adapter = gcloud_adapter_with_runner(fn(arguments) {
    calls.push(arguments)
    let response = responses[next]
    next = next + 1
    response
  })

  match adapter.inspect() {
    Ok(GcloudStatus::Ready(active_account, active_project)) => {
      assert_eq(active_account, Some("author@example.com"))
      assert_eq(active_project, Some("docs-project"))
    }
    _ => fail("expected usable signed-in gcloud")
  }
  assert_eq(calls, [
    ["auth", "list", "--format=json", "--quiet"],
    ["auth", "print-access-token", "--quiet"],
    ["config", "get", "core/project", "--quiet"],
  ])
}

///|
async test "gcloud adapter treats empty accounts and unset project as unauthenticated" {
  let mut next = 0
  let responses = [gcloud_result(0, "[]")]
  let adapter = gcloud_adapter_with_runner(fn(_) {
    let response = responses[next]
    next = next + 1
    response
  })
  match adapter.inspect() {
    Ok(GcloudStatus::Unauthenticated) => ()
    _ => fail("expected empty account list to be unauthenticated")
  }

  let mut configured_project_next = 0
  let configured_project = gcloud_adapter_with_runner(fn(_) {
    let responses = [
      gcloud_result(
        0, "[{\"account\":\"author@example.com\",\"status\":\"ACTIVE\"}]",
      ),
      gcloud_result(0, "discard-me"),
      gcloud_result(0, "(unset)\n"),
    ]
    let response = responses[configured_project_next]
    configured_project_next = configured_project_next + 1
    response
  })
  match configured_project.inspect() {
    Ok(GcloudStatus::Ready(Some("author@example.com"), None)) => ()
    _ => fail("expected no active project for (unset)")
  }
}

///|
async test "gcloud adapter maps unavailable, auth, and malformed responses to safe typed errors" {
  let missing = gcloud_adapter_with_runner(fn(_) {
    {
      launched: false,
      exit_code: -1,
      stdout: "secret stdout",
      stderr: "secret stderr",
    }
  })
  match missing.inspect() {
    Ok(GcloudStatus::Missing) => ()
    _ => fail("expected unavailable gcloud")
  }

  let installed_but_broken = gcloud_adapter_with_runner(fn(_) {
    gcloud_result(1, "sensitive account-list failure")
  })
  match installed_but_broken.inspect() {
    Err(GuidedSetupError::AccountEnumerationFailed) => ()
    _ =>
      fail(
        "an installed gcloud account-list failure must not request installation",
      )
  }

  let mut next = 0
  let unauthenticated = gcloud_adapter_with_runner(fn(_) {
    let responses = [
      gcloud_result(
        0, "[{\"account\":\"author@example.com\",\"status\":\"ACTIVE\"}]",
      ),
      gcloud_result(1, "token"),
    ]
    let response = responses[next]
    next = next + 1
    response
  })
  match unauthenticated.inspect() {
    Ok(GcloudStatus::Unauthenticated) => ()
    _ => fail("expected rejected access token to be unauthenticated")
  }

  let malformed = gcloud_adapter_with_runner(fn(_) {
    gcloud_result(0, "not JSON")
  })
  match malformed.list_accounts() {
    Err(GuidedSetupError::AccountEnumerationFailed) => ()
    _ => fail("expected safe account enumeration failure")
  }
}

///|
async test "gcloud adapter parses projects conservatively" {
  let calls : Array[Array[String]] = []
  let adapter = gcloud_adapter_with_runner(fn(arguments) {
    calls.push(arguments)
    gcloud_result(
      0, "[{\"projectId\":\"active-project\",\"name\":\"Active\",\"lifecycleState\":\"ACTIVE\"},{\"projectId\":\"paused-project\",\"name\":\"Paused\",\"lifecycleState\":\"SUSPENDED\"},{\"projectId\":\"deleting-project\",\"name\":\"Deleting\",\"lifecycleState\":\"DELETE_REQUESTED\"}]",
    )
  })
  match adapter.list_projects("author@example.com") {
    Ok(projects) => {
      assert_eq(projects.length(), 3)
      match projects[0].availability {
        ProjectAvailability::Available => ()
        _ => fail("active project must be available")
      }
      match projects[1].availability {
        ProjectAvailability::Suspended => ()
        _ => fail("suspended lifecycle must remain suspended")
      }
      match projects[2].availability {
        ProjectAvailability::Inaccessible => ()
        _ => fail("unknown non-active lifecycle must be inaccessible")
      }
    }
    Err(_) => fail("expected project fixtures to parse")
  }
  assert_eq(calls, [
    [
      "projects", "list", "--format=json", "--quiet", "--account=author@example.com",
    ],
  ])

  let malformed = gcloud_adapter_with_runner(fn(_) {
    gcloud_result(0, "[{\"name\":\"missing id\"}]")
  })
  match malformed.list_projects("author@example.com") {
    Err(GuidedSetupError::ProjectEnumerationFailed) => ()
    _ => fail("expected malformed project data to fail safely")
  }

  let empty = gcloud_adapter_with_runner(fn(_) { gcloud_result(0, "[]") })
  match empty.list_projects("author@example.com") {
    Ok(projects) => assert_eq(projects.length(), 0)
    _ => fail("expected empty project array")
  }
}

///|
async test "gcloud adapter creates projects without enabling cloud APIs" {
  let calls : Array[Array[String]] = []
  let adapter = gcloud_adapter_with_runner(fn(arguments) {
    calls.push(arguments)
    gcloud_result(
      0,
      (
        #|{"projectId":"new-docs-project","name":"New Docs Project","lifecycleState":"ACTIVE"}
      ),
    )
  })
  match
    adapter.create_project("author@example.com", {
      project_id: "new-docs-project",
      display_name: "New Docs Project",
    }) {
    Ok(project) =>
      match project.availability {
        ProjectAvailability::Available => ()
        _ => fail("created active project should be available")
      }
    Err(_) => fail("expected project creation fixture to parse")
  }
  assert_eq(calls, [
    [
      "projects", "create", "new-docs-project", "--name=New Docs Project", "--no-enable-cloud-apis",
      "--format=json", "--quiet", "--account=author@example.com",
    ],
  ])
}

///|
async test "gcloud adapter inspects and idempotently enables only Google Docs API" {
  let calls : Array[Array[String]] = []
  let mut next = 0
  let adapter = gcloud_adapter_with_runner(fn(arguments) {
    calls.push(arguments)
    let responses = [
      gcloud_result(0, "[]"),
      gcloud_result(0, "[]"),
      gcloud_result(0, ""),
      gcloud_result(0, "[{\"config\":{\"name\":\"docs.googleapis.com\"}}]"),
    ]
    let response = responses[next]
    next = next + 1
    response
  })
  match adapter.inspect_docs_api("author@example.com", "docs-project") {
    Ok(false) => ()
    _ => fail("expected absent Docs API")
  }
  match adapter.enable_docs_api("author@example.com", "docs-project") {
    Ok(_) => ()
    _ => fail("expected Docs API enablement to verify")
  }
  assert_eq(calls, [
    [
      "services", "list", "--enabled", "--project=docs-project", "--filter=config.name=docs.googleapis.com",
      "--format=json", "--quiet", "--account=author@example.com",
    ],
    [
      "services", "list", "--enabled", "--project=docs-project", "--filter=config.name=docs.googleapis.com",
      "--format=json", "--quiet", "--account=author@example.com",
    ],
    [
      "services", "enable", "docs.googleapis.com", "--project=docs-project", "--quiet",
      "--account=author@example.com",
    ],
    [
      "services", "list", "--enabled", "--project=docs-project", "--filter=config.name=docs.googleapis.com",
      "--format=json", "--quiet", "--account=author@example.com",
    ],
  ])

  let already_enabled_calls : Array[Array[String]] = []
  let already_enabled = gcloud_adapter_with_runner(fn(arguments) {
    already_enabled_calls.push(arguments)
    gcloud_result(0, "[{\"config\":{\"name\":\"docs.googleapis.com\"}}]")
  })
  match already_enabled.enable_docs_api("author@example.com", "docs-project") {
    Ok(_) => ()
    _ => fail("enabled Docs API should be idempotent")
  }
  assert_eq(already_enabled_calls.length(), 1)

  let malformed = gcloud_adapter_with_runner(fn(_) {
    gcloud_result(0, "[{\"config\":{}}]")
  })
  match malformed.inspect_docs_api("author@example.com", "docs-project") {
    Err(GuidedSetupError::DocsApiInspectionFailed) => ()
    _ => fail("expected malformed service payload to fail safely")
  }
}
