import "std.str" as str

import "std.list" as list

import "std.int" as int

import "../src/value" as val

import "../src/frame" as frame

import "../src/io" as io

import "../src/group" as grp

fn run_bench(path :: Str) -> [io] Str {
  match io.read_csv(path) {
    Err(e) => str.concat("load error: ", e.message),
    Ok(df) => {
      let shape := str.concat(int.to_str(df.nrows), str.concat(" x ", int.to_str(list.len(df.col_names))))
      let q1 := run_q1(df)
      let q3 := run_q3(df)
      let q4 := run_q4(df)
      let q5 := run_q5(df)
      str.join([str.concat("shape:  ", shape), str.concat("Q1 sum(v1) by id1              => ", q1), str.concat("Q3 sum(v1)+mean(v3) by id3     => ", q3), str.concat("Q4 mean(v1,v2,v3) by id4       => ", q4), str.concat("Q5 sum(v1,v2,v3) by id6        => ", q5)], "\n")
    },
  }
}

fn run_q1(df :: frame.DataFrame) -> Str {
  match grp.group_by(df, "id1") {
    Err(e) => str.concat("error: ", e.message),
    Ok(gf) => {
      let out := grp.agg(gf, [grp.agg_spec("sum_v1", "v1", grp.agg_sum())])
      str.concat(int.to_str(out.nrows), " groups")
    },
  }
}

fn run_q3(df :: frame.DataFrame) -> Str {
  match grp.group_by(df, "id3") {
    Err(e) => str.concat("error: ", e.message),
    Ok(gf) => {
      let out := grp.agg(gf, [grp.agg_spec("sum_v1", "v1", grp.agg_sum()), grp.agg_spec("mean_v3", "v3", grp.agg_mean())])
      str.concat(int.to_str(out.nrows), " groups")
    },
  }
}

fn run_q4(df :: frame.DataFrame) -> Str {
  match grp.group_by(df, "id4") {
    Err(e) => str.concat("error: ", e.message),
    Ok(gf) => {
      let out := grp.agg(gf, [grp.agg_spec("mean_v1", "v1", grp.agg_mean()), grp.agg_spec("mean_v2", "v2", grp.agg_mean()), grp.agg_spec("mean_v3", "v3", grp.agg_mean())])
      str.concat(int.to_str(out.nrows), " groups")
    },
  }
}

fn run_q5(df :: frame.DataFrame) -> Str {
  match grp.group_by(df, "id6") {
    Err(e) => str.concat("error: ", e.message),
    Ok(gf) => {
      let out := grp.agg(gf, [grp.agg_spec("sum_v1", "v1", grp.agg_sum()), grp.agg_spec("sum_v2", "v2", grp.agg_sum()), grp.agg_spec("sum_v3", "v3", grp.agg_sum())])
      str.concat(int.to_str(out.nrows), " groups")
    },
  }
}

