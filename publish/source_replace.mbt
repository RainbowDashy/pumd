///|
/// Replace an existing Markdown source through an adjacent, fully-synced
/// temporary file. The adjacent rename keeps replacement atomic on the
/// source filesystem and cleanup is best-effort on every failure path.
pub async fn atomic_replace_source(
  path : String,
  source : String,
) -> Result[Unit, String] {
  let random = match @env.rand(16) {
    Some(value) => value
    None => return Err("could not generate source temporary name")
  }
  let suffix = @base64.encode(random[:], url_safe=true)
  let temporary = path + ".pumd-tmp-" + suffix
  let file = @async_fs.open(
    temporary,
    mode=@async_fs.WriteOnly,
    create_mode=@async_fs.CreateNew,
    permission=0o600,
  ) catch {
    _ => return Err("could not create source temporary file")
  }
  let written : Result[Unit, String] = try {
    file.write(source)
    file.sync()
    Ok(())
  } catch {
    _ => Err("could not write source temporary file")
  }
  file.close()
  let outcome = match written {
    Err(error) => Err(error)
    Ok(_) =>
      try {
        @async_fs.rename(temporary, path, replace=true)
        Ok(())
      } catch {
        _ => Err("could not replace Markdown source")
      }
  }
  match outcome {
    Ok(_) => Ok(())
    Err(error) => {
      @async_fs.remove(temporary) catch {
        _ => ()
      }
      Err(error)
    }
  }
}
