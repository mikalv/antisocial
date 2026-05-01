alias Antisocial.{Repo, Chat.Channel}

Repo.insert!(%Channel{slug: "generelt", name: "#generelt", pin_required: false},
  on_conflict: :nothing,
  conflict_target: :slug
)
