# Quest Types

Quest types are **files in this folder**, not an enum. Every `.gd` script
here (except `quest_type.gd` and files starting with `_`) is scanned at
startup and appears automatically in the `quest_type` dropdown of every
Quest resource in the Inspector.

## Making a new quest type

1. **Copy `_template.gd`** (it's a heavily commented "survive N seconds"
   example) and rename it, e.g. `break_boxes.gd`.
2. Change `type_id()` to a unique snake_case name, e.g. `"break_boxes"`.
   This string is what quest `.tres` files store, so don't rename it after
   quests use it.
3. Override the hooks you need (see below). Delete the rest.
4. That's it. Open any Quest in the Inspector - your type is in the list.

## The hooks

| Hook | When it fires |
|---|---|
| `on_accepted(entry)` | Right after the player takes the quest. Snapshot baselines, check "already done?" |
| `notify_enemy_defeated(entry, enemy)` | Any enemy died. `enemy` is the node - filter on type/boss/id/position |
| `notify_gears_changed(entry, total)` | Player gear total changed |
| `notify_location_flag(entry, flag_id)` | A LocationFlag area was touched |
| `notify_item_grabbed(entry, item_id)` | A QuestItem was picked up |
| `try_turn_in(entry)` | Player talked to the giver. Return `true` to complete (fetch-style) |
| `describe_progress(entry)` | Short HUD tracker text, e.g. `"gears 3/5"` |
| `describe_reminder(entry)` | What the giver says while the quest runs |

## Progress helpers (call from any hook)

- `progress(entry)` / `progress(entry, 5)` — add progress, auto-completes at
  `quest.goal_count()` (which is `target_count`)
- `set_progress(entry, n)` — absolute progress (baseline-style counting)
- `complete(entry)` — finish immediately

## Per-quest state

`entry.data` is a Dictionary that belongs entirely to your handler for the
lifetime of the active quest. Baselines, timers, sets of seen IDs - stash
anything there. One handler instance exists per active quest, so instance
variables on the handler are also safe.

## Quest resource fields you can lean on

- `target_count` — the goal number (via `quest.goal_count()`)
- `target_id` — free-form string id (flag id, item id, enemy id...)
- `target_enemy_scene` / `require_boss` — enemy filters (defeat quests)
- `has_time_limit` / `time_limit_seconds` — the manager ticks this down and
  auto-FAILS the quest at 0; you don't need to do anything
- `cred_reward`, `repeatable` — handled by the manager

## Existing types as reference

- `collect_gears.gd` — baseline snapshot + `set_progress` counting
- `defeat_enemy.gd` — event filtering ("elects" kills by type/boss/id)
- `reach_location.gd` — instant-complete-if-already-done + one-shot event
- `fetch_item.gd` — two-phase quest with a `try_turn_in` step
- `_template.gd` — commented starter (survive N seconds)

## Newer hooks

- `tick(entry, delta)` — called every frame while the quest is active.
  Use for custom clocks (see `defeat_timed.gd`'s streak window).
- `notify_breakable_destroyed(entry, breakable)` — a crate/barrel was
  smashed by the player (see `break_boxes.gd`).

## Built-in types

| file | what it does |
|---|---|
| collect_gears.gd | collect N gears (baseline snapshot) |
| defeat_enemy.gd | kill N enemies, filtered by scene/boss/id |
| defeat_timed.gd | kill N in one streak; clock starts on first kill, streak resets on timeout |
| break_boxes.gd | smash N breakables; target_id filters by scene name ("barrel"...) |
| reach_location.gd | touch a LocationFlag |
| fetch_item.gd | grab a QuestItem, return to the giver |
