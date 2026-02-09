defmodule SocialScribe.Repo.Migrations.AddMeetingChatSessions do
  use Ecto.Migration

  def up do
    create table(:meeting_chat_sessions) do
      add :meeting_id, references(:meetings, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :preview, :text
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime

      timestamps()
    end

    create index(:meeting_chat_sessions, [:meeting_id, :user_id])
    create index(:meeting_chat_sessions, [:meeting_id, :user_id, :ended_at])

    alter table(:meeting_chat_messages) do
      add :chat_session_id, references(:meeting_chat_sessions, on_delete: :delete_all)
    end

    execute("""
    WITH sessions AS (
      INSERT INTO meeting_chat_sessions (meeting_id, user_id, preview, started_at, ended_at, inserted_at, updated_at)
      SELECT meeting_id, user_id, NULL, MIN(timestamp), MAX(timestamp), NOW(), NOW()
      FROM meeting_chat_messages
      GROUP BY meeting_id, user_id
      RETURNING id, meeting_id, user_id
    )
    UPDATE meeting_chat_messages m
    SET chat_session_id = s.id
    FROM sessions s
    WHERE m.meeting_id = s.meeting_id AND m.user_id = s.user_id AND m.chat_session_id IS NULL;
    """)

    alter table(:meeting_chat_messages) do
      modify :chat_session_id, :bigint, null: false
    end

    create index(:meeting_chat_messages, [:chat_session_id])
  end

  def down do
    drop index(:meeting_chat_messages, [:chat_session_id])

    alter table(:meeting_chat_messages) do
      remove :chat_session_id
    end

    drop index(:meeting_chat_sessions, [:meeting_id, :user_id, :ended_at])
    drop index(:meeting_chat_sessions, [:meeting_id, :user_id])
    drop table(:meeting_chat_sessions)
  end
end
