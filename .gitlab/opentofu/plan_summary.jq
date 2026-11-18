def action:
  .change.actions as $a |
  if ($a | index("create")) and ($a | index("delete")) then "replace"
  elif $a == ["create"] then "create"
  elif $a == ["update"] then "update"
  elif $a == ["delete"] then "delete"
  elif $a == ["read"] then "read"
  else ($a | join(" + ")) end;

def safe_text:
  explode | map(if . < 32 or . == 96 or . == 127 then 63 else . end) | implode;

def changed_fields:
  (.change.before // {}) as $before | (.change.after // {}) as $after |
  if ($before | type) == "object" and ($after | type) == "object" then
    ([($before | keys_unsorted[]), ($after | keys_unsorted[])] | unique |
      map(. as $key | select($before[$key] != $after[$key]) | safe_text) | .[:20])
  else [] end;

[.resource_changes[]? | select(.change.actions != ["no-op"]) |
  {address: (.address | safe_text), action: action, fields: changed_fields}] as $changes |
if ($changes | length) == 0 then
  "No resource changes."
else
  (["create", "update", "delete", "replace", "read"] |
    map(. as $kind | "\([$changes[] | select(.action == $kind)] | length) \($kind)") |
    join(", ")) +
  "\n\n```text\n" +
  ([$changes[:100][] | "\(.action): \(.address)" +
    (if (.fields | length) > 0 then " [fields: \(.fields | join(", "))]" else "" end)] | join("\n")) +
  "\n```" +
  (if ($changes | length) > 100 then "\n\nOnly the first 100 resources are shown." else "" end)
end
