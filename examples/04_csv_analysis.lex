# Load a CSV, profile it, compute stats — typical agent EDA loop

import "std.list" as list

import "std.str" as str

import "std.int" as int

import "../src/value" as val

import "../src/frame" as frame

import "../src/io" as fio

import "../src/stats" as stats

import "../src/inspect" as inspect

import "../src/select" as sel

# Effect annotation: the legacy CSV reader goes through std.io ([io]).
# For large files prefer `fio.read_csv_fast` ([fs_read]) — see
# examples/06_fast_pipeline.lex.
fn analyse_csv(path :: Str) -> [io] Str {
  match fio.read_csv(path) {
    Err(e) => str.concat("[", str.concat(e.code, str.concat("] ", e.message))),
    Ok(df) => {
      let overview := inspect.summary(df)
      let desc_md := inspect.to_markdown(stats.describe(df), 10)
      let null_md := inspect.to_markdown(inspect.null_report(df), 20)
      let payload := inspect.to_json_payload(df, 5)
      str.concat(overview, str.concat("\n\n## Descriptive Stats\n", str.concat(desc_md, str.concat("\n\n## Null Report\n", str.concat(null_md, str.concat("\n\n## Sample Payload\n", payload))))))
    },
  }
}

# Write a cleaned copy back to disk (drops rows with any null)
fn clean_and_save(in_path :: Str, out_path :: Str) -> [io] Str {
  match fio.read_csv(in_path) {
    Err(e) => str.concat("Read error: ", e.message),
    Ok(df) => {
      let pred := fn (row :: List[(Str, val.Value)]) -> Bool {
        list.fold(row, true, fn (acc :: Bool, pair :: (Str, val.Value)) -> Bool {
          acc and match pair {
            (_, v) => if val.is_null(v) {
              false
            } else {
              true
            },
          }
        })
      }
      match sel.filter_rows(df, "no_nulls", pred) {
        Err(e) => str.concat("Filter error: ", e.message),
        Ok(clean_df) => match fio.write_csv(out_path, clean_df) {
          Err(e) => str.concat("Write error: ", e.message),
          Ok(_) => str.concat(int.to_str(clean_df.nrows), str.concat(" rows written to ", out_path)),
        },
      }
    },
  }
}

