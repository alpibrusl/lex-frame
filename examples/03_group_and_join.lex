// Group-by aggregation and join operations
import "std.list" as list
import "std.str" as str
import "src/value" as val
import "src/frame" as frame
import "src/group" as grp
import "src/join" as jn
import "src/inspect" as inspect

fn make_orders() -> frame.DataFrame {
  let regions = list.cons(val.VStr("West"),  list.cons(val.VStr("East"),  list.cons(val.VStr("West"),  list.cons(val.VStr("East"),  list.cons(val.VStr("West"),  [])))))
  let amounts = list.cons(val.VInt(120),     list.cons(val.VInt(85),      list.cons(val.VInt(200),     list.cons(val.VInt(310),     list.cons(val.VInt(95),      [])))))
  let cols    = list.cons(("region", regions), list.cons(("amount", amounts), []))
  match frame.from_columns(cols) {
    Ok(df) => df
    Err(_) => frame.empty()
  }
}

fn make_targets() -> frame.DataFrame {
  let regions = list.cons(val.VStr("West"), list.cons(val.VStr("East"), []))
  let targets = list.cons(val.VInt(400),    list.cons(val.VInt(350),    []))
  let cols    = list.cons(("region", regions), list.cons(("target", targets), []))
  match frame.from_columns(cols) {
    Ok(df) => df
    Err(_) => frame.empty()
  }
}

// Group by region, compute sum and count
fn regional_summary() -> Str {
  let orders   = make_orders()
  let key_cols = list.cons("region", [])
  let specs    = list.cons(
    { col_name = "amount", op = grp.AggSum,   result_name = "total_amount" },
    list.cons(
      { col_name = "amount", op = grp.AggCount, result_name = "order_count" },
      []
    )
  )
  match grp.group_by(orders, key_cols) {
    Err(e)  => str.concat("GroupBy error: ", e.message)
    Ok(gf)  =>
      match grp.agg(gf, specs) {
        Err(e)      => str.concat("Agg error: ", e.message)
        Ok(summary) => inspect.to_markdown(summary, 10)
      }
  }
}

// Join aggregated data with targets
fn vs_target() -> Str {
  let orders   = make_orders()
  let targets  = make_targets()
  let key_cols = list.cons("region", [])
  let specs    = list.cons(
    { col_name = "amount", op = grp.AggSum, result_name = "total_amount" },
    []
  )
  match grp.group_by(orders, key_cols) {
    Err(e) => str.concat("Error: ", e.message)
    Ok(gf) =>
      match grp.agg(gf, specs) {
        Err(e)   => str.concat("Error: ", e.message)
        Ok(agg_df) =>
          match jn.inner_join(agg_df, targets, "region") {
            Err(e)    => str.concat("Join error: ", e.message)
            Ok(final) => inspect.to_markdown(final, 10)
          }
      }
  }
}

// Value counts — quick frequency table, very useful for agents doing EDA
fn region_counts() -> Str {
  match grp.value_counts(make_orders(), "region") {
    Err(e)  => str.concat("Error: ", e.message)
    Ok(vc)  => inspect.to_markdown(vc, 10)
  }
}
