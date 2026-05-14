// Load a CSV, profile it, compute stats — typical agent EDA loop
import "std.list" as list
import "std.str" as str
import "src/value" as val
import "src/frame" as frame
import "src/io" as io
import "src/stats" as stats
import "src/inspect" as inspect
import "src/sort" as srt

// Effect annotation: this function reads from the filesystem
fn analyse_csv(path :: Str) -> [fs.read] Str {
  match io.read_csv(path) {
    Err(e) => str.concat("[FRAME_IO_READ] ", e.message)
    Ok(df) =>
      // Step 1: agent-friendly summary (shape, column types, null counts)
      let overview  = inspect.summary(df)

      // Step 2: statistical description of numeric columns
      let desc_df   = stats.describe(df)
      let desc_md   = inspect.to_markdown(desc_df, 10)

      // Step 3: null report so agent knows data quality issues
      let null_df   = inspect.null_report(df)
      let null_md   = inspect.to_markdown(null_df, 20)

      // Step 4: compact JSON payload for LLM context (up to 5 sample rows)
      let payload   = inspect.to_json_payload(df, 5)

      str.concat(overview,
        str.concat("\n\n## Descriptive Stats\n",
          str.concat(desc_md,
            str.concat("\n\n## Null Report\n",
              str.concat(null_md,
                str.concat("\n\n## Sample Payload\n", payload)
              )
            )
          )
        )
      )
  }
}

// Write a cleaned copy back to disk (drops rows with any null)
fn clean_and_save(in_path :: Str, out_path :: Str) -> [fs.read, fs.write] Str {
  match io.read_csv(in_path) {
    Err(e) => str.concat("Read error: ", e.message)
    Ok(df) =>
      // Filter out rows that contain any null value
      let pred = fn(row) -> Bool {
        list.all(row, fn(pair) -> Bool {
          match pair {
            (_, v) => if val.is_null(v) { false } else { true }
          }
        })
      }
      match sel.filter_rows(df, "no_nulls", pred) {
        Err(e)       => str.concat("Filter error: ", e.message)
        Ok(clean_df) =>
          match io.write_csv(out_path, clean_df) {
            Err(e) => str.concat("Write error: ", e.message)
            Ok(_)  =>
              str.concat(
                int.to_str(clean_df.nrows),
                str.concat(" rows written to ", out_path)
              )
          }
      }
  }
}
