# End-to-end columnar fast path: CSV -> filter -> sort -> group -> CSV.
#
# Every op here runs as one std.arrow / std.df kernel call over a flat
# columnar buffer — no interpreted per-row work. At 1M rows this
# pipeline is competitive with pandas (see bench/REPORT.md); the
# legacy List[Value] equivalent would take hours.
#
# Run:
#   lex run --allow-effects fs_read,fs_write,io examples/06_fast_pipeline.lex main '"/tmp/input.csv"' '"/tmp/out.csv"'

import "std.list" as list

import "std.str" as str

import "std.int" as int

import "../src/frame" as frame

import "../src/select" as sel

import "../src/sort" as srt

import "../src/group" as grp

import "../src/io" as fio

import "../src/inspect" as inspect

# The whole pipeline stays arrow-backed end to end. Note the sharp
# edge: an arrow-backed DataFrame's legacy `columns` map is empty, so
# closure-based ops (sel.filter_rows, the inspect walkers) see no
# data — stay on the `_fast` ops until you write the result out.
fn pipeline(in_path :: Str, out_path :: Str, cutoff :: Int) -> [fs_read, fs_write] Str {
  match fio.read_csv_fast(in_path) {
    Err(e) => str.concat("[", str.concat(e.code, str.concat("] ", e.message))),
    Ok(df) => match sel.filter_gt_int_fast(df, "x", cutoff) {
      Err(e) => str.concat("[", str.concat(e.code, str.concat("] ", e.message))),
      Ok(hot) => {
        let ranked := srt.sort_by_fast(hot, "x", false)
        let specs := list.cons(grp.agg_spec("total_x", "x", grp.agg_sum()), list.cons(grp.agg_spec("n", "x", grp.agg_count()), []))
        match grp.group_agg_fast(ranked, "g", specs) {
          Err(e) => str.concat("[", str.concat(e.code, str.concat("] ", e.message))),
          Ok(by_group) => match fio.write_csv_fast(out_path, by_group) {
            Err(e) => str.concat("[", str.concat(e.code, str.concat("] ", e.message))),
            Ok(_) => str.concat(int.to_str(by_group.nrows), str.concat(" group rows written to ", str.concat(out_path, str.concat("\n\nProvenance:\n", inspect.history(by_group))))),
          },
        }
      },
    },
  }
}

fn main(in_path :: Str, out_path :: Str) -> [fs_read, fs_write] Str {
  pipeline(in_path, out_path, 0)
}

