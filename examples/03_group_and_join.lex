# Group-by aggregation and join operations

import "std.list" as list

import "std.str" as str

import "../src/value" as val

import "../src/frame" as frame

import "../src/group" as grp

import "../src/join" as jn

import "../src/inspect" as inspect

fn make_orders() -> frame.DataFrame {
  let regions := list.cons(val.vstr("West"), list.cons(val.vstr("East"), list.cons(val.vstr("West"), list.cons(val.vstr("East"), list.cons(val.vstr("West"), [])))))
  let amounts := list.cons(val.vint(120), list.cons(val.vint(85), list.cons(val.vint(200), list.cons(val.vint(310), list.cons(val.vint(95), [])))))
  let cols := list.cons(("region", regions), list.cons(("amount", amounts), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

fn make_targets() -> frame.DataFrame {
  let regions := list.cons(val.vstr("West"), list.cons(val.vstr("East"), []))
  let targets := list.cons(val.vint(400), list.cons(val.vint(350), []))
  let cols := list.cons(("region", regions), list.cons(("target", targets), []))
  match frame.from_columns(cols) {
    Ok(df) => df,
    Err(_) => frame.empty(),
  }
}

# Group by region, compute sum and count
fn regional_summary() -> Str {
  let orders := make_orders()
  let specs := list.cons(grp.agg_spec("total_amount", "amount", grp.agg_sum()), list.cons(grp.agg_spec("order_count", "amount", grp.agg_count()), []))
  match grp.group_by(orders, "region") {
    Err(e) => str.concat("GroupBy error: ", e.message),
    Ok(gf) => inspect.to_markdown(grp.agg(gf, specs), 10),
  }
}

# Join aggregated data with targets
fn vs_target() -> Str {
  let orders := make_orders()
  let targets := make_targets()
  let specs := list.cons(grp.agg_spec("total_amount", "amount", grp.agg_sum()), [])
  match grp.group_by(orders, "region") {
    Err(e) => str.concat("Error: ", e.message),
    Ok(gf) => {
      let agg_df := grp.agg(gf, specs)
      match jn.inner_join(agg_df, targets, "region") {
        Err(e) => str.concat("Join error: ", e.message),
        Ok(joined) => inspect.to_markdown(joined, 10),
      }
    },
  }
}

# Value counts — quick frequency table, very useful for agents doing EDA
fn region_counts() -> Str {
  match grp.value_counts(make_orders(), "region") {
    Err(e) => str.concat("Error: ", e.message),
    Ok(vc) => inspect.to_markdown(vc, 10),
  }
}

fn main() -> Str {
  str.concat(regional_summary(), str.concat("\n\n", str.concat(vs_target(), str.concat("\n\n", region_counts()))))
}

